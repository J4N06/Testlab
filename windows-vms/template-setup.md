# Windows Server 2025 Template

Einmalige manuelle Erstellung des Proxmox-Templates (VM-ID 9000).  
Danach läuft alles via Terraform + Ansible.

---

## VM in Proxmox erstellen

**Proxmox → Create VM:**

| Einstellung | Wert |
|---|---|
| VM ID | 9000 |
| Name | windows-server-2025 |
| ISO | Windows Server 2025 (local:iso/) |
| Machine | q35 |
| BIOS | SeaBIOS |
| Disk | 60 GB, SATA, local-lvm, Writeback, Discard |
| CPU | 4 Cores, x86-64-v2-AES |
| RAM | 4096 MB |
| Netzwerk | e1000, vmbr0 |

---

## Windows installieren

1. VM starten → "Windows Server 2025 Standard (Desktop Experience)" wählen (Index 2)
2. Vollständige Installation, nicht Upgrade
3. Administrator-Passwort: `Packer2025!`

---

## Nach erstem Login: PowerShell als Admin

```powershell
# WinRM aktivieren (für Ansible/Terraform)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted $true
Set-Item WSMan:\localhost\Service\Auth\Basic $true
New-NetFirewallRule -DisplayName 'WinRM HTTP' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any

# Windows Update deaktivieren
Set-Service wuauserv -StartupType Disabled
Stop-Service wuauserv -Force

# Sysprep + Shutdown
Start-Process 'C:\Windows\System32\Sysprep\sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /quiet' -Wait
```

---

## Template erstellen

Nachdem die VM sich ausgeschaltet hat:

1. ISO in Proxmox aushängen (Hardware → CD/DVD → "Do not use any media")
2. Rechtsklick auf VM 9000 → **Convert to Template**

Template ist bereit für `windows-vms/nps-test/`.
