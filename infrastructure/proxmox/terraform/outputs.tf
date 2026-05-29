output "dc_vmid" {
  description = "Proxmox VM ID of lab-dc01 (Domain Controller)"
  value       = proxmox_virtual_environment_vm.dc.vm_id
}

output "sccm_vmid" {
  description = "Proxmox VM ID of lab-sccm01 (SCCM + SQL Server)"
  value       = proxmox_virtual_environment_vm.sccm.vm_id
}

output "client_vmid" {
  description = "Proxmox VM ID of lab-client01 (Windows 11 Client)"
  value       = proxmox_virtual_environment_vm.client.vm_id
}

output "dc_name" {
  description = "Hostname of the Domain Controller VM"
  value       = proxmox_virtual_environment_vm.dc.name
}

output "sccm_name" {
  description = "Hostname of the SCCM VM"
  value       = proxmox_virtual_environment_vm.sccm.name
}

output "client_name" {
  description = "Hostname of the Windows 11 Client VM"
  value       = proxmox_virtual_environment_vm.client.name
}
