# -----------------------------------------------------------------------
# Core VMs (always created)
# -----------------------------------------------------------------------

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

# -----------------------------------------------------------------------
# Extension VMs (only present when their enable_* toggle is true)
# -----------------------------------------------------------------------

output "pfsense_vmid" {
  description = "Proxmox VM ID of lab-fw01 (pfSense router). Null when enable_pfsense = false."
  value       = var.enable_pfsense ? proxmox_virtual_environment_vm.pfsense[0].vm_id : null
}

output "ca_vmid" {
  description = "Proxmox VM ID of lab-ca01 (Enterprise Root CA). Null when enable_ca = false."
  value       = var.enable_ca ? proxmox_virtual_environment_vm.ca[0].vm_id : null
}

output "dc02_vmid" {
  description = "Proxmox VM ID of lab-dc02 (Secondary Domain Controller). Null when enable_dc02 = false."
  value       = var.enable_dc02 ? proxmox_virtual_environment_vm.dc02[0].vm_id : null
}

output "aadconnect_vmid" {
  description = "Proxmox VM ID of lab-aadc01 (Azure AD Connect server). Null when enable_aadconnect = false."
  value       = var.enable_aadconnect ? proxmox_virtual_environment_vm.aadconnect[0].vm_id : null
}

output "opnsense_vmid" {
  description = "VM ID of lab-opnsense01 (OPNsense). Null when enable_opnsense = false."
  value       = var.enable_opnsense ? proxmox_virtual_environment_vm.opnsense[0].vm_id : null
}

output "client02_vmid" {
  description = "VM ID of lab-client02 (Windows 11 client 2). Null when enable_client02 = false."
  value       = var.enable_client02 ? proxmox_virtual_environment_vm.client02[0].vm_id : null
}

output "linux01_vmid" {
  description = "VM ID of lab-linux01 (Ubuntu 22.04). Null when enable_linux_client = false."
  value       = var.enable_linux_client ? proxmox_virtual_environment_vm.linux01[0].vm_id : null
}

output "linux02_vmid" {
  description = "VM ID of lab-linux02 (Rocky Linux 9). Null when linux_client_count < 2."
  value       = var.enable_linux_client && var.linux_client_count >= 2 ? proxmox_virtual_environment_vm.linux02[0].vm_id : null
}

output "nas_vmid" {
  description = "VM ID of lab-nas01. Null when enable_nas = false."
  value       = var.enable_nas ? proxmox_virtual_environment_vm.nas[0].vm_id : null
}

output "docusaurus_vmid" {
  description = "VM ID of lab-docusaurus01. Null when enable_docusaurus = false."
  value       = var.enable_docusaurus ? proxmox_virtual_environment_vm.docusaurus[0].vm_id : null
}
