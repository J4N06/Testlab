terraform {
  required_version = ">= 1.3"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure  = true
}

locals {
  ssh_keys = concat(
    [trimspace(file("${path.module}/../k3s_key.pub"))],
    [
      for line in split("\n", file("${path.module}/../team_keys.pub"))
      : trimspace(line)
      if length(trimspace(line)) > 0 && !startswith(trimspace(line), "#")
    ]
  )
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-cloudimg.img"
  overwrite            = false
  overwrite_unmanaged  = true
}

resource "proxmox_virtual_environment_vm" "master" {
  name      = var.master_name
  node_name = var.proxmox_node
  vm_id     = 200

  agent {
    enabled = true
  }

  cpu {
    cores = var.master_cores
  }

  memory {
    dedicated = var.master_memory
  }

  disk {
    datastore_id = var.storage
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.master_ip}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = ["8.8.8.8"]
    }
    user_account {
      username = "ubuntu"
      keys     = local.ssh_keys
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  count = 2

  name      = var.worker_names[count.index]
  node_name = var.proxmox_node
  vm_id     = 201 + count.index

  agent {
    enabled = true
  }

  cpu {
    cores = var.worker_cores
  }

  memory {
    dedicated = var.worker_memory
  }

  disk {
    datastore_id = var.storage
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[count.index]}/24"
        gateway = var.gateway
      }
    }
    dns {
      servers = ["8.8.8.8"]
    }
    user_account {
      username = "ubuntu"
      keys     = local.ssh_keys
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../inventory/hosts.yml"
  content  = <<EOT
---
all:
  children:
    k3s_master:
      hosts:
        ${var.master_name}:
          ansible_host: ${var.master_ip}
          ansible_user: ubuntu

    k3s_workers:
      hosts:
        ${var.worker_names[0]}:
          ansible_host: ${var.worker_ips[0]}
          ansible_user: ubuntu
        ${var.worker_names[1]}:
          ansible_host: ${var.worker_ips[1]}
          ansible_user: ubuntu
EOT
}
