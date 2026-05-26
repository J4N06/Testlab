# NPS Test-VM

Windows Server 2022 VM auf Proxmox für RADIUS Zertifikat-Tests.

```
windows-vms/nps-test/
├── main.tf / variables.tf / outputs.tf   # Proxmox VM
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

ISOs in Proxmox unter `local:iso/` hochladen (**Datacenter → local → ISO Images → Upload**):

| ISO | Download |
|---|---|
| Windows Server 2022 Evaluation | https://www.microsoft.com/evalcenter/evaluate-windows-server-2022 |
| VirtIO Treiber | https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso |

---

## Schritt 1 — VM erstellen

```bash
cd windows-vms/nps-test

cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars anpassen (Proxmox-Token, ISO-Namen, IP)

terraform init
bash apply.sh
```

---

## Schritt 2 — Windows installieren

1. **Proxmox Web-UI → VM 300 → Console** öffnen
2. Windows Server 2022 installieren (~20 Min)
   - Edition: **Standard (Desktop Experience)**
   - Disk nicht sichtbar? → **Treiber laden** → Laufwerk D: → `viostor\2k22\amd64`
3. Administrator-Passwort setzen — notieren!
4. IP statisch setzen: `192.168.2.30 / 255.255.255.0 / GW: 192.168.2.1`
5. VirtIO Gast-Tools installieren: Laufwerk D: → `virtio-win-gt-x64.msi`

---

## Schritt 3 — WinRM Bootstrap (einmalig in Proxmox-Konsole)

In der VM-Konsole als Administrator:

```powershell
winrm quickconfig -force
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
```

---

## Schritt 4 — Ansible: NPS + WinRM HTTPS einrichten

```bash
# Ansible Collections installieren (einmalig)
ansible-galaxy collection install ansible.windows community.windows

# Passwort als Umgebungsvariable
export WINDOWS_ADMIN_PASS="DAS-ADMINISTRATOR-PASSWORT"

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

## Schritt 5 — RADIUS Cert Automation testen

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
