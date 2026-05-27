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

  # Template klonen (wird von Packer erstellt: windows-vms/packer/)
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  # q35 = bessere Windows-Kompatibilität (PCIe, TPM-fähig)
  machine = "q35"

  cpu {
    cores = var.vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  # Disk-Grösse auf gewünschten Wert setzen (Template hat 60G, kann vergrössert werden)
  disk {
    datastore_id = var.storage
    interface    = "ide0"
    size         = var.disk_size
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  boot_order = ["ide0"]

  # QEMU Guest Agent (VirtIO Gast-Tools sind im Template vorinstalliert)
  agent {
    enabled = true
  }

  operating_system {
    type = "win11"
  }

  vga {
    type   = "std"
    memory = 16
  }
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
