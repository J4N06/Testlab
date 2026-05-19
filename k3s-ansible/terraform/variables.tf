variable "proxmox_endpoint" {
  description = "URL der Proxmox API, z.B. https://192.168.1.100:8006/"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API-User, z.B. terraform@pve"
  type        = string
  default     = "terraform@pve"
}

variable "proxmox_password" {
  description = "Passwort des Proxmox API-Users"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Name des Proxmox-Hosts (pve, proxmox, ...)"
  type        = string
  default     = "pve"
}

variable "proxmox_storage" {
  description = "Storage-Pool für VM-Disks (local-lvm, local-zfs, ...)"
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key" {
  description = "SSH Public Key für cloud-init (Inhalt, nicht Pfad)"
  type        = string
}

variable "ubuntu_image_url" {
  description = "URL des Ubuntu 24.04 Cloud-Images"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "network_bridge" {
  description = "Proxmox-Netzwerkbrücke"
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Standard-Gateway im VM-Netz"
  type        = string
  default     = "192.168.1.1"
}

variable "master_ip" {
  description = "IP des Master-Nodes (CIDR), z.B. 192.168.2.21/24"
  type        = string
  default     = "192.168.2.21/24"
}

variable "worker_ips" {
  description = "IPs der Worker-Nodes (CIDR)"
  type        = list(string)
  default     = ["192.168.2.22/24", "192.168.2.23/24"]
}

variable "vm_master_id" {
  description = "Proxmox VM-ID für den Master"
  type        = number
  default     = 200
}

variable "vm_worker_id_start" {
  description = "Erste Proxmox VM-ID für Worker (wird hochgezählt)"
  type        = number
  default     = 201
}

variable "master_cores" {
  type    = number
  default = 2
}

variable "master_memory_mb" {
  type    = number
  default = 4096
}

variable "master_disk_gb" {
  type    = number
  default = 30
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  type    = number
  default = 4096
}

variable "worker_disk_gb" {
  type    = number
  default = 30
}
