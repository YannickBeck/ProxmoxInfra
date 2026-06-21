data "openstack_images_image_v2" "vm" {
  for_each = local.enabled_vms

  name = var.image_names[each.value.image_key]
}

resource "openstack_networking_port_v2" "vm" {
  for_each = local.enabled_vms

  name               = "${each.value.name}-port"
  network_id         = openstack_networking_network_v2.lab.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.lab.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.lab.id
    ip_address = each.value.ip_address
  }
}

resource "openstack_blockstorage_volume_v3" "root" {
  for_each = local.enabled_vms

  name              = "${each.value.name}-root"
  description       = "Boot volume for ${each.value.name}"
  size              = each.value.root_size_gb
  image_id          = data.openstack_images_image_v2.vm[each.key].id
  volume_type       = var.volume_type
  availability_zone = var.volume_availability_zone
  metadata = merge(local.common_metadata, {
    instance = each.value.name
    role     = each.value.role
    purpose  = "root"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_compute_instance_v2" "vm" {
  for_each = local.enabled_vms

  name              = each.value.name
  flavor_name       = each.value.flavor_name
  key_pair          = var.key_pair_name
  availability_zone = var.compute_availability_zone
  config_drive      = true

  metadata = merge(local.common_metadata, {
    role = each.value.role
  })

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.root[each.key].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  network {
    port = openstack_networking_port_v2.vm[each.key].id
  }

  depends_on = [
    openstack_networking_secgroup_rule_v2.external_egress,
    openstack_networking_secgroup_rule_v2.lab_egress,
    openstack_networking_secgroup_rule_v2.lab_ingress,
    openstack_networking_secgroup_rule_v2.management
  ]
}
