terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    node {
      name    = var.proxmox_node
      address = var.proxmox_ssh_host
    }
  }
}

# ─── Ubuntu 24.04 Cloud-Image herunterladen ───────────────────────────────────
resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = var.ubuntu_image_url
  file_name    = "ubuntu-24.04-server-cloudimg-amd64.img"
  overwrite    = false
}

# ─── Cloud-Init: User + SSH-Key ───────────────────────────────────────────────
resource "proxmox_virtual_environment_file" "cloud_init_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    file_name = "k3s-cloud-init.yml"
    data = <<-EOT
      #cloud-config
      users:
        - name: ubuntu
          groups: sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
          sudo: ALL=(ALL) NOPASSWD:ALL
      package_update: true
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOT
  }
}

# ─── Master-Node ──────────────────────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "k3s_master" {
  name      = "k3s-master"
  node_name = var.proxmox_node
  vm_id     = var.vm_master_id
  started   = true

  agent {
    enabled = true
  }

  cpu {
    cores = var.master_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.master_memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    size         = var.master_disk_gb
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.master_ip
        gateway = var.network_gateway
      }
    }
    dns {
      servers = ["8.8.8.8", "8.8.4.4"]
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_config.id
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}

# ─── Worker-Nodes (2 Stück) ───────────────────────────────────────────────────
resource "proxmox_virtual_environment_vm" "k3s_workers" {
  count     = 2
  name      = "k3s-worker${count.index + 1}"
  node_name = var.proxmox_node
  vm_id     = var.vm_worker_id_start + count.index
  started   = true

  agent {
    enabled = true
  }

  cpu {
    cores = var.worker_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    size         = var.worker_disk_gb
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.worker_ips[count.index]
        gateway = var.network_gateway
      }
    }
    dns {
      servers = ["8.8.8.8", "8.8.4.4"]
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_config.id
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}
