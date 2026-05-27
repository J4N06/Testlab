# Windows Server 2025 Packer Template

Erstellt vollautomatisch ein Windows Server 2025 Standard (Desktop Experience) Template auf Proxmox.  
Das Template wird von `windows-vms/nps-test/` (und anderen VMs) als Basis-Image geklont.

```
windows-vms/packer/
├── windows-2025.pkr.hcl          # Packer Konfiguration
├── autounattend.xml               # Windows Setup Antwortdatei (unattended install)
├── variables.pkrvars.hcl.example  # Variablen-Vorlage (nie ins Git!)
└── scripts/
    └── setup.ps1                  # Post-Install: VirtIO Tools, WinRM HTTPS, Cleanup
```

---

## Was passiert beim Build

1. **Packer startet eine neue VM** auf Proxmox (VM-ID 9000) mit Windows Server ISO + VirtIO ISO
2. **autounattend.xml** übernimmt die vollständige Windows-Installation:
   - VirtIO Treiber laden (Disk + Netzwerk)
   - GPT Partitioning (EFI + Windows)
   - Edition: Standard (Desktop Experience)
   - Administrator-Passwort setzen
   - WinRM HTTP (Port 5985) aktivieren
3. **Packer verbindet sich via WinRM** (Port 5985) sobald Windows gestartet ist
4. **setup.ps1** läuft auf der VM:
   - VirtIO Guest Tools installieren (`virtio-win-gt-x64.msi`)
   - WinRM HTTPS (Port 5986, self-signed Zertifikat) konfigurieren
   - Temporäre Dateien bereinigen
5. **Sysprep** generalisiert Windows (`/generalize /oobe /shutdown`)
6. **Packer erstellt das Proxmox-Template** `windows-server-2025`

---

## Voraussetzungen

### ISOs in Proxmox hochladen

**Datacenter → local → ISO Images → Upload:**

| ISO | Quelle |
|---|---|
| Windows Server 2025 | [Microsoft Evaluation Center](https://www.microsoft.com/evalcenter/evaluate-windows-server-2025) oder MSDN/Volumen |
| VirtIO Treiber | [Fedora People](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) |

### Packer installieren

```bash
# Linux / WSL
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer

# macOS
brew install packer
```

### Proxmox API Token

In Proxmox unter **Datacenter → Permissions → API Tokens** erstellen:
- User: `root@pam` (oder dedizierter User)
- Token-ID: `packer`
- Privilege Separation: **deaktivieren** (braucht volle Rechte)

---

## Build ausführen

```bash
cd windows-vms/packer

# Variablen-Datei erstellen
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
# variables.pkrvars.hcl anpassen (Proxmox-Token, Passwort)

# Packer Plugin installieren (einmalig)
packer init windows-2025.pkr.hcl

# Template bauen (~30-45 Minuten)
packer build -var-file="variables.pkrvars.hcl" windows-2025.pkr.hcl
```

Nach erfolgreichem Build erscheint in Proxmox unter **Templates** der Eintrag `windows-server-2025` (VM-ID 9000).

---

## Template neu bauen

Falls das Template bereits existiert, muss es zuerst gelöscht werden:

```bash
# In Proxmox: Rechtsklick auf VM 9000 → Remove
# Oder via API:
curl -s -k -X DELETE "https://192.168.2.12:8006/api2/json/nodes/pve/qemu/9000" \
  -H "Authorization: PVEAPIToken=root@pam!packer=<token>"
```

---

## Variablen

| Variable | Beschreibung | Standard |
|---|---|---|
| `proxmox_url` | Proxmox API URL | `https://192.168.2.12:8006` |
| `proxmox_token_id` | API Token ID | — |
| `proxmox_token_secret` | API Token Secret | — |
| `proxmox_node` | Proxmox Node-Name | `pve` |
| `storage` | Storage für VM-Disk | `local-lvm` |
| `windows_iso` | Dateiname Windows ISO | — |
| `virtio_iso` | Dateiname VirtIO ISO | `virtio-win.iso` |
| `vm_password` | Administrator-Passwort | — |
