output "master_ip" {
  value = var.master_ip
}

output "worker_ips" {
  value = var.worker_ips
}

output "next_steps" {
  value = "Warte ~60s, dann: cd .. && ansible all -m ping && ansible-playbook site.yml"
}
