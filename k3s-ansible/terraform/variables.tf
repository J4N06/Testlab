variable "proxmox_url" {
  description = "Proxmox API URL (z.B. https://192.168.2.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API-Token (Format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Name des Proxmox-Nodes (im Web-UI oben links sichtbar)"
  type        = string
  default     = "pve"
}

variable "storage" {
  description = "Storage für VM-Disks"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Netzwerk-Bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Standard-Gateway"
  type        = string
  default     = "192.168.2.1"
}

variable "master_name" {
  description = "Name der Master-VM (= Hostname im Cluster)"
  type        = string
  default     = "master"
}

variable "master_ip" {
  description = "IP-Adresse des Masters"
  type        = string
  default     = "192.168.2.21"
}

variable "master_cores" {
  description = "CPU-Kerne für den Master"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "RAM für den Master in MB"
  type        = number
  default     = 4096
}

variable "worker_names" {
  description = "Namen der Worker-VMs (= Hostnamen im Cluster)"
  type        = list(string)
  default     = ["worker1", "worker2"]
}

variable "worker_ips" {
  description = "IP-Adressen der Worker"
  type        = list(string)
  default     = ["192.168.2.22", "192.168.2.23"]
}

variable "worker_cores" {
  description = "CPU-Kerne pro Worker"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "RAM pro Worker in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk-Grösse pro VM in GB"
  type        = number
  default     = 30
}
