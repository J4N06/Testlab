# RADIUS Zertifikat Automation

Automatisches TLS-Zertifikat-Deployment für Windows NPS (RADIUS) Server über Kubernetes und ArgoCD.

## Wie es funktioniert

```
cert-manager          Kubernetes CronJob          Windows NPS Server
──────────            ──────────────────          ──────────────────
Erstellt  ──→  TLS Secret  ──→  deploy-cert.py  ──→  WinRM (NTLM)
Zertifikat      (tls.crt/key)   konvertiert zu PFX    Importiert Zert
(intern CA)                     verbindet via WinRM    Startet IAS neu
```

**Jeder Kunde ist vollständig isoliert:**
- Eigener Kubernetes Namespace
- Eigene ArgoCD Application
- Eigenes Zertifikat
- Eigene Credentials (nie im Git)

---

## Struktur

```
radius-cert-automation/
├── docker/
│   ├── Dockerfile          # Python 3.11 mit pywinrm + cryptography
│   └── deploy-cert.py      # Zertifikat lesen → PFX → WinRM → NPS
├── k8s/                    # Helm Chart (Templates für alle Kunden)
│   ├── Chart.yaml
│   ├── values.yaml         # Standardwerte
│   └── templates/
│       ├── namespace.yaml
│       ├── certificate.yaml
│       └── cronjob.yaml
├── clusterissuer.yaml      # Interne CA — einmalig anwenden
├── customers/
│   ├── kunde1/
│   │   ├── values.yaml     # Kundenspezifische Werte (im Git)
│   │   ├── secret.yaml     # Passwörter — Vorlage, NIE ins Git!
│   │   └── argocd-app.yaml # ArgoCD Application
│   └── kunde2/
│       └── ...
└── windows/
    ├── setup-winrm.ps1     # WinRM + Service Account einrichten
    └── test-connection.ps1 # Verbindung und Zertifikat testen

# Test-VM (Windows NPS Server für lokale Tests):
# → windows-vms/nps-test/
```

---

## Schritt-für-Schritt Anleitung

### Schritt 1 — Docker Image bauen und pushen

```bash
cd radius-cert-automation/docker

# Image bauen
docker build -t your-registry/radius-cert-deployer:latest .

# In Registry pushen
docker push your-registry/radius-cert-deployer:latest
```

`your-registry` mit der eigenen Container Registry ersetzen (z.B. `ghcr.io/j4n06`).

---

### Schritt 2 — Interne CA als Kubernetes Secret erstellen

Einmalig — das CA-Zertifikat das für alle RADIUS-Zertifikate verwendet wird:

```bash
# CA-Zertifikat und Key als Secret in cert-manager Namespace ablegen
kubectl create secret tls internal-ca-secret \
  --cert=ca.crt \
  --key=ca.key \
  -n cert-manager
```

Dann ClusterIssuer anwenden:

```bash
kubectl apply -f clusterissuer.yaml
```

Prüfen:

```bash
kubectl get clusterissuer internal-ca
# Erwartete Ausgabe: READY = True
```

---

### Schritt 3 — Windows NPS Server vorbereiten

Auf jedem Windows NPS Server als Administrator ausführen:

```powershell
.\windows\setup-winrm.ps1
```

Das Skript:
- Aktiviert WinRM über HTTPS (Port 5986)
- Erstellt eine Firewall-Regel
- Erstellt Service Account `svc-certdeploy`
- Zeigt das generierte Passwort **einmalig** an — sofort notieren!

---

### Schritt 4 — Kubernetes Secret erstellen (pro Kunde)

Das Passwort aus Schritt 3 verwenden:

```bash
kubectl create namespace radius-kunde1

kubectl create secret generic kunde1-credentials \
  --from-literal=windows_password='DAS-PASSWORT-AUS-SCHRITT-3' \
  --from-literal=pfx_password='EIN-SICHERES-PFX-PASSWORT' \
  -n radius-kunde1
```

> **Wichtig:** Secrets niemals in Git speichern. Die `secret.yaml` Dateien sind nur Vorlagen.

---

### Schritt 5 — ArgoCD Application deployen

```bash
kubectl apply -f customers/kunde1/argocd-app.yaml
```

ArgoCD deployt automatisch:
- Namespace `radius-kunde1`
- cert-manager Certificate für `radius.kunde1.ch`
- CronJob der täglich um 02:00 Uhr läuft

Prüfen in ArgoCD UI oder:

```bash
kubectl get certificate -n radius-kunde1
kubectl get cronjob -n radius-kunde1
```

---

### Schritt 6 — Verbindung testen

```powershell
.\windows\test-connection.ps1 `
  -TargetHost nps.kunde1.ch `
  -User "KUNDE1\svc-certdeploy" `
  -CertDomain radius.kunde1.ch
```

---

### Schritt 7 — Erstes Deployment manuell auslösen

```bash
# CronJob manuell als Job starten
kubectl create job --from=cronjob/kunde1-cert-deploy test-deploy-1 -n radius-kunde1

# Logs verfolgen
kubectl logs -f job/test-deploy-1 -n radius-kunde1
```

---

## Neuen Kunden hinzufügen

```bash
# 1. Ordner kopieren
cp -r customers/kunde1 customers/kunde3

# 2. values.yaml anpassen
#    name, namespace, domain, windows.host, windows.user

# 3. argocd-app.yaml anpassen
#    name: radius-kunde3
#    valueFiles: ../../customers/kunde3/values.yaml

# 4. Namespace und Secret erstellen
kubectl create namespace radius-kunde3
kubectl create secret generic kunde3-credentials \
  --from-literal=windows_password='...' \
  --from-literal=pfx_password='...' \
  -n radius-kunde3

# 5. ArgoCD Application deployen
kubectl apply -f customers/kunde3/argocd-app.yaml

# 6. In Git pushen
git add customers/kunde3/values.yaml customers/kunde3/argocd-app.yaml
git commit -m "Add Kunde3 RADIUS certificate automation"
git push
```

---

## CronJob Logs prüfen

```bash
# Letzte Ausführungen anzeigen
kubectl get jobs -n radius-kunde1

# Logs des letzten Jobs
kubectl logs -l app=cert-deployer -n radius-kunde1 --tail=50

# Alle Kunden gleichzeitig
for ns in $(kubectl get ns | grep radius | awk '{print $1}'); do
  echo "=== $ns ==="; kubectl logs -l app=cert-deployer -n $ns --tail=5 2>/dev/null
done
```

---

## Umgebungsvariablen

| Variable | Quelle | Beschreibung |
|---|---|---|
| `WINDOWS_HOST` | values.yaml | IP oder DNS des NPS Servers |
| `WINDOWS_USER` | values.yaml | `DOMAIN\svc-certdeploy` |
| `WINDOWS_PASS` | Kubernetes Secret | Windows Passwort |
| `CERT_DOMAIN` | values.yaml | RADIUS-Zertifikat Domain |
| `PFX_PASSWORD` | Kubernetes Secret | PFX Export-Passwort |
| `SLACK_WEBHOOK` | Optional — Secret | Slack Webhook URL |

---

## Troubleshooting

### WinRM Verbindung schlägt fehl

```bash
# Aus dem Cluster testen
kubectl run winrm-test --rm -it --image=python:3.11-slim -- bash
pip install pywinrm
python -c "import winrm; s=winrm.Session('https://nps.kunde1.ch:5986/wsman', auth=('user','pass'), transport='ntlm', server_cert_validation='ignore'); print(s.run_ps('hostname').std_out)"
```

Auf dem Windows Server prüfen:
```powershell
# WinRM Status
winrm enumerate winrm/config/listener
Get-Service WinRM

# Firewall
Get-NetFirewallRule -DisplayName "WinRM HTTPS Inbound"
```

### cert-manager Zertifikat wird nicht ausgestellt

```bash
kubectl describe certificate kunde1-radius-cert -n radius-kunde1
kubectl describe certificaterequest -n radius-kunde1
kubectl logs -n cert-manager deploy/cert-manager
```

### NPS Dienst startet nicht nach Zertifikat-Import

Auf dem Windows Server:
```powershell
Get-EventLog -LogName System -Source "IAS" -Newest 20
Get-Service IAS | Start-Service
```

---

## Sicherheitshinweise

- `secret.yaml` Dateien sind Vorlagen — nie mit echten Passwörtern ins Git
- `.gitignore` schützt vor versehentlichem Commit
- WinRM HTTPS verwendet self-signed Zertifikat (intern akzeptabel)
- Service Account `svc-certdeploy` hat nur lokale Admin-Rechte (kein Domain Admin)
- PFX-Passwort wird nach dem Import nicht mehr benötigt
