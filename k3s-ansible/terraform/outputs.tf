output "master_ip" {
  description = "IP des k3s Master-Nodes"
  value       = proxmox_virtual_environment_vm.k3s_master.initialization[0].ip_config[0].ipv4[0].address
}

output "worker_ips" {
  description = "IPs der k3s Worker-Nodes"
  value = [
    for vm in proxmox_virtual_environment_vm.k3s_workers :
    vm.initialization[0].ip_config[0].ipv4[0].address
  ]
}

output "ansible_inventory_hint" {
  description = "IPs für das Ansible-Inventory (ohne CIDR-Suffix)"
  value = {
    master  = split("/", var.master_ip)[0]
    worker1 = split("/", var.worker_ips[0])[0]
    worker2 = split("/", var.worker_ips[1])[0]
  }
}
