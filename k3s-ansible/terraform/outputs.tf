output "ansible_inventory_hint" {
  description = "IPs für das Ansible-Inventory (ohne CIDR-Suffix)"
  value = {
    master  = split("/", var.master_ip)[0]
    worker1 = split("/", var.worker_ips[0])[0]
    worker2 = split("/", var.worker_ips[1])[0]
  }
}
