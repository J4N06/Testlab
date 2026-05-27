# NPS Test-VM

Windows Server 2025 VM auf Proxmox für RADIUS Zertifikat-Tests.  
Die VM wird aus dem Packer-Template geklont — kein manuelles Windows-Setup nötig.

```
windows-vms/nps-test/
├── main.tf / variables.tf / outputs.tf   # Proxmox VM (Template-Clone)
├── apply.sh / destroy.sh                 # SSH-Agent Wrapper
├── terraform.tfvars.example              # Vorlage (terraform.tfvars nicht ins Git!)
└── ansible/
    ├── playbook.yml
    ├── ansible.cfg
    ├── inventory/hosts.yml               # wird von Terraform generiert
    ├── group_vars/windows.yml            # WinRM Verbindungseinstellungen
    └── roles/nps-setup/                  # NPS, WinRM, Service Account
```

---

## Voraussetzungen

Das Windows Server 2025 Template muss zuerst mit Packer erstellt werden:

**→ [Packer Template erstellen](../packer/README.md)**

---

## Schritt 1 — VM aus Template klonen

```bash
cd windows-vms/nps-test

cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars anpassen (Proxmox-Token, template_vm_id=9000, IP)

terraform init
bash apply.sh
```

Terraform klont das Packer-Template (VM-ID 9000) als neue VM.  
Windows startet sofort — kein Installations-Assistent.

---

## Schritt 2 — IP statisch setzen

Nach dem ersten Boot in der Proxmox-Konsole als Administrator:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.2.30 -PrefixLength 24 -DefaultGateway 192.168.2.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.2.1
```

---

## Schritt 3 — Ansible: NPS + WinRM HTTPS einrichten

```bash
# Ansible Collections installieren (einmalig)
ansible-galaxy collection install ansible.windows community.windows

# Passwort als Umgebungsvariable (Packer2025! oder nach Sysprep neu gesetzt)
export WINDOWS_ADMIN_PASS="Packer2025!"

# Verbindung testen
ansible windows -m ansible.windows.win_ping

# Konfiguration ausführen
ansible-playbook ansible/playbook.yml -e "svc_certdeploy_password=Test1234!"
```

Ansible installiert:
- **NPS Rolle** (Network Policy and Access Services)
- **WinRM HTTPS** (Port 5986, self-signed Zertifikat)
- **Service Account** `svc-certdeploy` (für Zertifikat-Deployment)
- **Firewall-Regel** für Port 5986

---

## Schritt 4 — RADIUS Cert Automation testen

```bash
# Kubernetes Secret erstellen
kubectl create namespace radius-test
kubectl create secret generic nps-test-credentials \
  --from-literal=windows_password='Test1234!' \
  --from-literal=pfx_password='TestPfx2024!' \
  -n radius-test

# Verbindung mit test-connection.ps1 prüfen
.\..\..\radius-cert-automation\windows\test-connection.ps1 `
  -TargetHost 192.168.2.30 `
  -User "nps-test\svc-certdeploy" `
  -CertDomain radius.test.local
```

---

## VM löschen

```bash
bash destroy.sh
```
