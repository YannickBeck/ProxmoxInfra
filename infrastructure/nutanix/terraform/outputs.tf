# -----------------------------------------------------------------------
# VM UUIDs — useful for referencing VMs in Nutanix Calm, Ansible inventory,
# or API calls after Terraform provisioning.
# -----------------------------------------------------------------------

output "dc01_uuid" {
  description = "Nutanix VM UUID of lab-dc01 (Domain Controller)"
  value       = nutanix_virtual_machine.dc01.id
}

output "sccm01_uuid" {
  description = "Nutanix VM UUID of lab-sccm01 (SCCM + SQL Server)"
  value       = nutanix_virtual_machine.sccm01.id
}

output "client01_uuid" {
  description = "Nutanix VM UUID of lab-client01 (Windows 11 client)"
  value       = nutanix_virtual_machine.client01.id
}

output "pfsense_uuid" {
  description = "Nutanix VM UUID of lab-fw01 (pfSense). Empty when enable_pfsense = false."
  value       = var.enable_pfsense ? nutanix_virtual_machine.pfsense[0].id : null
}

output "ca01_uuid" {
  description = "Nutanix VM UUID of lab-ca01 (Enterprise Root CA). Empty when enable_ca = false."
  value       = var.enable_ca ? nutanix_virtual_machine.ca01[0].id : null
}

output "dc02_uuid" {
  description = "Nutanix VM UUID of lab-dc02 (Secondary DC). Empty when enable_dc02 = false."
  value       = var.enable_dc02 ? nutanix_virtual_machine.dc02[0].id : null
}

output "aadc01_uuid" {
  description = "Nutanix VM UUID of lab-aadc01 (Entra Connect Sync). Empty when enable_aadconnect = false."
  value       = var.enable_aadconnect ? nutanix_virtual_machine.aadc01[0].id : null
}

output "opnsense_uuid" {
  description = "Nutanix VM UUID of lab-opnsense01 (OPNsense). Empty when enable_opnsense = false."
  value       = var.enable_opnsense && !var.enable_pfsense ? nutanix_virtual_machine.opnsense01[0].id : null
}

output "client02_uuid" {
  description = "Nutanix VM UUID of lab-client02 (second Windows 11 client). Empty when enable_client02 = false."
  value       = var.enable_client02 ? nutanix_virtual_machine.client02[0].id : null
}

output "cloudsync01_uuid" {
  description = "Nutanix VM UUID of lab-cloudsync01 (Entra Cloud Sync). Empty when enable_cloudsync = false."
  value       = var.enable_cloudsync ? nutanix_virtual_machine.cloudsync01[0].id : null
}

output "linux01_uuid" {
  description = "Nutanix VM UUID of lab-linux01 (Ubuntu 22.04). Empty when enable_linux_client = false."
  value       = var.enable_linux_client ? nutanix_virtual_machine.linux01[0].id : null
}

output "linux02_uuid" {
  description = "Nutanix VM UUID of lab-linux02 (Rocky Linux 9). Empty unless enable_linux_client = true and linux_client_count = 2."
  value       = var.enable_linux_client && var.linux_client_count >= 2 ? nutanix_virtual_machine.linux02[0].id : null
}

output "rootca01_uuid" {
  description = "Nutanix VM UUID of lab-rootca01 (offline Root CA). Empty when enable_twotier_pki = false."
  value       = var.enable_twotier_pki ? nutanix_virtual_machine.rootca01[0].id : null
}

output "subca01_uuid" {
  description = "Nutanix VM UUID of lab-subca01 (Enterprise Issuing CA). Empty when enable_twotier_pki = false."
  value       = var.enable_twotier_pki ? nutanix_virtual_machine.subca01[0].id : null
}
