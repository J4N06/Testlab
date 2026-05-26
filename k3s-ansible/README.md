# k3s auf Proxmox — Automatisches Setup

Terraform erstellt 3 Ubuntu 24.04 VMs in Proxmox, Ansible installiert darauf einen k3s-Cluster (1 Master, 2 Worker).

---

## Voraussetzungen

- Proxmox VE läuft auf dem Server
- Server hat Internetzugang
- Alle Befehle werden in der **Proxmox-Shell** ausgeführt (Web-UI → Node → Shell) als `root`

---

## Wichtig — diese Dateien kommen nie ins Git

| Datei | Inhalt |
|---|---|
| `terraform/terraform.tfvars` | Proxmox API-Token |
| `kubeconfig` | Cluster-Zugangsdaten |
| `k3s_key` / `k3s_key.pub` | SSH-Keypair — lokal generiert, nie ins Git |

---

## Schritt 1 — Proxmox Enterprise-Repos deaktivieren

Ohne Lizenz schlägt `apt update` mit 401-Fehlern fehl:

```bash
cat > /etc/apt/sources.list.d/pve-enterprise.sources << 'EOF'
Types: deb
URIs: https://enterprise.proxmox.com/debian/ceph-squid
Suites: trixie
Components: enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg

Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

cat > /etc/apt/sources.list.d/ceph.sources << 'EOF'
Types: deb
URIs: https://enterprise.proxmox.com/debian/ceph-squid
Suites: trixie
Components: enterprise
Enabled: no
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

apt update
```

---

## Schritt 2 — Tools installieren

```bash
# Git, Ansible, Python
apt install -y git ansible python3-pip curl unzip

# Ansible Collections
ansible-galaxy collection install community.general ansible.posix

# Terraform
TERRAFORM_VERSION="1.9.8"
wget -q -O terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip terraform.zip && mv terraform /usr/local/bin/ && rm terraform.zip
```

---

## Schritt 3 — GitHub SSH einrichten

GitHub akzeptiert kein Passwort mehr — SSH-Key für den Push einrichten:

```bash
# SSH-Key generieren (falls noch nicht vorhanden)
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""

# Public Key anzeigen und bei GitHub hinterlegen
cat /root/.ssh/id_ed25519.pub
```

**GitHub → Settings → SSH and GPG keys → New SSH key** → Key einfügen → Add SSH key

```bash
# Verbindung testen — erwartet: "Hi J4N06! You've successfully authenticated..."
ssh -T git@github.com

# Key auch für lokalen SSH-Zugang autorisieren (wird von Terraform benötigt)
cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

---

## Schritt 4 — Repository clonen

```bash
git clone git@github.com:J4N06/Testlab.git
cd Testlab/k3s-ansible
```

---

## Schritt 5 — VM-SSH-Key erstellen

> Dieser Key ist **nicht** der GitHub-Key aus Schritt 3.
> `k3s_key` ist der Key mit dem Ansible auf die VMs zugreift — er wird beim VM-Erstellen automatisch eingespielt.

```bash
ssh-keygen -t ed25519 -f k3s_key -N ""
```

### Weitere Benutzer hinzufügen (optional)

Damit weitere Personen per SSH auf die VMs zugreifen können, ihre Public Keys in `team_keys.pub` eintragen (eine Zeile pro Key) und committen:

```
ssh-ed25519 AAAAC3... jan@laptop
ssh-ed25519 AAAAC3... lisa@pc
```

---

## Schritt 6 — Proxmox API-Token erstellen

Proxmox Web-UI → **Datacenter → API Tokens → Add**

| Feld | Wert |
|---|---|
| User | `root@pam` |
| Token ID | `terraform` |
| Privilege Separation | **nein** |

Den angezeigten Secret-Wert kopieren — er wird nur **einmal** angezeigt.

---

## Schritt 7 — Terraform konfigurieren

```bash
cd terraform
bash configure.sh
```

Das Skript fragt alle Parameter interaktiv ab (mit Standardwerten) und schreibt `terraform.tfvars` automatisch. Beim nächsten Aufruf werden die gespeicherten Werte als Vorschlag angezeigt.

---

## Schritt 8 — VMs erstellen

```bash
terraform init   # nur beim ersten Mal
bash apply.sh
```

`apply.sh` lädt den SSH-Key automatisch in den Agent — das ist nötig damit Terraform die VMs erstellen kann. Terraform lädt das Ubuntu 24.04 Cloud-Image herunter (~600 MB), erstellt die 3 VMs und schreibt `inventory/hosts.yml` automatisch.

---

## Schritt 9 — Verbindung testen

~60 Sekunden warten bis cloud-init fertig ist, dann:

```bash
cd ..
ansible all -m ping
```

Erwartete Ausgabe:
```
master  | SUCCESS
worker1 | SUCCESS
worker2 | SUCCESS
```

---

## Schritt 10 — k3s installieren

```bash
ansible-playbook site.yml
```

Dauert ca. 10–15 Minuten. Das Playbook durchläuft folgende Phasen:

### Was Ansible installiert

**1. Common (alle Nodes)**
- System-Updates
- Kernel-Module (`overlay`, `br_netfilter`) für Kubernetes-Networking
- Sysctl-Parameter (IP-Forwarding, Bridge-Filter)
- Swap deaktivieren (Kubernetes-Anforderung)
- Hostname auf den Inventar-Namen setzen

**2. k3s Master**
- k3s Server installieren mit:
  - Traefik deaktiviert (kein Ingress-Controller)
  - Flannel als CNI-Backend
  - API-Server auf Master-IP gebunden
- Node-Token auslesen (für Worker-Join)
- `kubeconfig` lokal ablegen (für direkten `kubectl`-Zugriff vom Proxmox-Host)

**3. k3s Worker (2x)**
- k3s Agent installieren
- Automatisch dem Master-Cluster beitreten via Node-Token

**4. ArgoCD**
- Namespace `argocd` erstellen
- ArgoCD via kubectl aus dem offiziellen Manifest installieren
- Service auf NodePort 30443 (HTTPS) umstellen
- Initiales Admin-Passwort ausgeben

**5. Monitoring**
- ArgoCD Application für `kube-prometheus-stack` deployen → ArgoCD übernimmt die Installation via Helm:
  - **Prometheus** — Metriken sammeln (Retention: 7 Tage)
  - **Grafana** — Dashboards auf Port 30300
  - **Alertmanager** — Alert-Verwaltung
  - **node-exporter** — Node-Metriken (CPU, RAM, Disk, Netzwerk)
  - **kube-state-metrics** — Pod/Deployment-Zustand
- Custom Dashboard "k3s Cluster Overview" automatisch in Grafana laden

---

## Schritt 11 — Cluster prüfen

```bash
ssh -i k3s_key ubuntu@192.168.2.21 "sudo kubectl get nodes"
```

Erwartete Ausgabe:
```
NAME      STATUS   ROLES           AGE   VERSION
master    Ready    control-plane   2m    v1.35.x+k3s1
worker1   Ready    <none>          1m    v1.35.x+k3s1
worker2   Ready    <none>          1m    v1.35.x+k3s1
```

Alle Pods prüfen:
```bash
ssh -i k3s_key ubuntu@192.168.2.21 "sudo kubectl get pods -A"
```

---

## Zugang — Installierte Services

| Service    | URL                        | Benutzer | Passwort             |
|------------|----------------------------|----------|----------------------|
| ArgoCD     | https://192.168.2.21:30443 | admin    | siehe unten          |
| Grafana    | http://192.168.2.21:30300  | admin    | admin                |

> Browser warnt bei ArgoCD wegen self-signed Zertifikat — einfach akzeptieren.

### ArgoCD Passwort auslesen

```bash
ssh -i k3s_key ubuntu@192.168.2.21 "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

### ArgoCD — Was wird angezeigt

Nach dem Login siehst du die App **kube-prometheus-stack** mit:
- Sync-Status (ist der Cluster identisch mit dem Helm-Chart?)
- Health-Status aller Pods (Prometheus, Grafana, Alertmanager, ...)
- Dependency-Graph aller Kubernetes-Objekte der App

### Grafana — Dashboards

Unter **Dashboards → Browse** sind vorhanden:
- **k3s Cluster Overview** — eigenes Dashboard (CPU, RAM, Netzwerk, Disk pro Node, Pod-Tabelle)
- **Kubernetes / Compute Resources** — Standard-Dashboards für Pods, Namespaces, Nodes

---

## Reset — Alles neu aufsetzen

```bash
cd terraform
bash destroy.sh   # VMs löschen
bash apply.sh     # VMs neu erstellen
cd ..
sleep 60          # cloud-init abwarten
ansible-playbook site.yml
```

