terraform {
  required_version = ">= 1.3"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure  = true
  ssh {
    username = "root"
    agent    = true
  }
}

resource "proxmox_virtual_environment_vm" "nps_test" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  # q35 = bessere Windows-Kompatibilität (PCIe, TPM-fähig)
  machine = "q35"

  cpu {
    cores = var.vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  # System-Disk via VirtIO SCSI (braucht VirtIO-Treiber bei Installation)
  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "qcow2"
    discard      = "on"
    iothread     = true
  }

  # Windows Server ISO (muss in Proxmox unter local:iso/ hochgeladen sein)
  cdrom {
    enabled   = true
    file_id   = "local:iso/${var.windows_iso}"
    interface = "ide2"
  }

  # VirtIO Treiber ISO (für Disk + Netzwerk Treiber während Installation)
  # Download: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
  cdrom {
    enabled   = true
    file_id   = "local:iso/${var.virtio_iso}"
    interface = "ide3"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # Boot: erst Disk, dann DVD (nach Installation Reihenfolge tauschen)
  boot_order = ["ide2", "scsi0"]

  # QEMU Guest Agent (nach Installation der VirtIO Gast-Tools aktiviert)
  agent {
    enabled = true
  }

  operating_system {
    type = "win11"  # win11 = Windows Server 2022 / Windows 11
  }

  # Standard-VGA für Proxmox-Konsole
  vga {
    type   = "std"
    memory = 16
  }

  # Tablet für präzise Maussteuerung in der Konsole
  usb {
    host = "spice"
    usb3 = true
  }

  # Feste IP via statische Konfiguration (kein cloud-init für Windows)
  # → IP wird nach Windows-Installation manuell oder per Ansible gesetzt
}

# Ansible Inventory automatisch schreiben
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory/hosts.yml"
  content  = <<-EOT
    ---
    all:
      children:
        windows:
          hosts:
            ${var.vm_name}:
              ansible_host: ${var.vm_ip}
    EOT
}
