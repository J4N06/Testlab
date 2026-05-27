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
  default = "windows-server-2025-autounattend.iso"
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

  # autounattend.xml ist direkt im ISO eingebettet — kein extra CD nötig
  iso_file         = "local:iso/${var.windows_iso}"
  iso_storage_pool = "local"
  unmount_iso      = true

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

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.vm_password
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "90m"

  boot_wait    = "3s"
  boot_command = ["<enter>"]

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
