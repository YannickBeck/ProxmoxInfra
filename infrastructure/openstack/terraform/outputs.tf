output "lab_network_id" {
  description = "Neutron network UUID for the lab."
  value       = openstack_networking_network_v2.lab.id
}

output "lab_subnet_id" {
  description = "Neutron subnet UUID for the lab."
  value       = openstack_networking_subnet_v2.lab.id
}

output "lab_router_id" {
  description = "Neutron router UUID, or null in isolated mode."
  value       = local.native_gateway_enabled ? openstack_networking_router_v2.lab[0].id : null
}

output "instance_ids" {
  description = "Nova instance UUIDs keyed by stable Terraform instance key."
  value       = { for key, instance in openstack_compute_instance_v2.vm : key => instance.id }
}

output "fixed_ipv4_addresses" {
  description = "Fixed IPv4 addresses keyed by stable Terraform instance key."
  value       = { for key, spec in local.enabled_vms : key => spec.ip_address }
}

output "root_volume_ids" {
  description = "Cinder boot-volume UUIDs keyed by stable Terraform instance key."
  value       = { for key, volume in openstack_blockstorage_volume_v3.root : key => volume.id }
}

output "data_volume_ids" {
  description = "Cinder data-volume UUIDs keyed by purpose."
  value       = { for key, volume in openstack_blockstorage_volume_v3.data : key => volume.id }
}

output "ansible_hosts" {
  description = "Non-sensitive host mapping for ansible/inventory/lab.yml."
  value = {
    for key, spec in local.enabled_vms : spec.name => {
      ansible_host  = spec.ip_address
      role          = spec.role
      terraform_key = key
    }
  }
}
