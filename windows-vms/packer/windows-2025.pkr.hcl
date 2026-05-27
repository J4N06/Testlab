packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = "https://192.168.2.12:8006/api2/json"
}

variable "proxmox_token_id" {
  type        = string
  description = "Format: root@pam!packer"
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "windows_iso" {
  type    = string
  default = "SW_DVD9_Win_Server_STD_CORE_2025_24H2_64Bit_English_DC_STD_MLF_X23-81891.ISO"
}

variable "vm_password" {
  type        = string
  sensitive   = true
  description = "Administrator Passwort für das Template"
}

source "proxmox-iso" "windows-2025" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id   = 9000
  vm_name = "windows-server-2025"

  # Original Windows ISO — unverändert, bootet zuverlässig
  iso_file         = "local:iso/${var.windows_iso}"
  iso_storage_pool = "local"
  unmount_iso      = true

  # autounattend.xml auf separater kleiner ISO (sata1)
  additional_iso_files {
    iso_file         = "local:iso/autounattend.iso"
    iso_storage_pool = "local"
    unmount          = true
    type             = "sata"
    index            = 1
  }

  machine  = "q35"

  cpu_type = "x86-64-v2-AES"
  cores    = 4
  memory   = 4096
  os       = "win11"

  disks {
    disk_size    = "60G"
    storage_pool = var.storage
    type         = "sata"
    cache_mode   = "writeback"
    discard      = true
  }

  # e1000: eingebaute Windows-Treiber → WinRM funktioniert ohne extra Treiber-ISO
  network_adapters {
    bridge = "vmbr0"
    model  = "e1000"
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.vm_password
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "90m"

  # SeaBIOS: etfsboot.com im Windows-ISO startet zuverlässig
  boot_wait    = "5s"
  boot_command = ["<spacebar>"]

  template_name        = "windows-server-2025"
  template_description = "Windows Server 2025 Standard (Desktop Experience) | Packer Build"
}

build {
  sources = ["source.proxmox-iso.windows-2025"]

  provisioner "powershell" {
    script = "scripts/setup.ps1"
  }

  provisioner "powershell" {
    inline = [
      "Start-Process 'C:\\Windows\\System32\\Sysprep\\sysprep.exe' -ArgumentList '/generalize /oobe /shutdown /quiet' -Wait"
    ]
    timeout = "30m"
  }
}
