output "vm_name" {
  value = proxmox_virtual_environment_vm.nps_test.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.nps_test.vm_id
}

output "next_steps" {
  value = <<-EOT

    ╔══════════════════════════════════════════════════════════╗
    ║  VM erstellt — nächste Schritte:                        ║
    ╠══════════════════════════════════════════════════════════╣
    ║  1. Proxmox Web-UI → VM ${proxmox_virtual_environment_vm.nps_test.vm_id} → Console                ║
    ║  2. Windows Server installieren (~20 Min)               ║
    ║  3. VirtIO Treiber von Laufwerk D: installieren         ║
    ║  4. IP ${var.vm_ip} statisch setzen               ║
    ║  5. setup-winrm.ps1 in der Konsole ausführen            ║
    ║  6. cd ../ansible && ansible-playbook playbook.yml      ║
    ╚══════════════════════════════════════════════════════════╝

  EOT
}
