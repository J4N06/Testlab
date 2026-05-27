variable "proxmox_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.2.12:8006"
}

variable "proxmox_api_token" {
  description = "Proxmox API Token (root@pam!terraform=uuid)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox Node-Name"
  type        = string
  default     = "TESTLAB-PROX01"
}

variable "storage" {
  description = "Storage für VM-Disk"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Netzwerk-Bridge"
  type        = string
  default     = "vmbr0"
}

variable "vm_name" {
  description = "Name der Windows Test-VM"
  type        = string
  default     = "nps-test"
}

variable "vm_id" {
  description = "Proxmox VM-ID (muss eindeutig sein)"
  type        = number
  default     = 300
}

variable "vm_ip" {
  description = "IP-Adresse der VM (für Ansible Inventory)"
  type        = string
  default     = "192.168.2.30"
}

variable "vm_cores" {
  description = "Anzahl CPU-Kerne"
  type        = number
  default     = 4
}

variable "vm_memory" {
  description = "RAM in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk-Grösse in GB"
  type        = number
  default     = 60
}

variable "template_vm_id" {
  description = "VM-ID des Packer-Templates (windows-server-2025, erstellt von windows-vms/packer/)"
  type        = number
  default     = 9000
}
