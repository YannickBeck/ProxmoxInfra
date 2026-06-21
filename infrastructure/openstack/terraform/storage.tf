resource "openstack_blockstorage_volume_v3" "data" {
  for_each = local.data_volumes

  name              = each.value.name
  description       = each.value.description
  size              = each.value.size_gb
  volume_type       = var.volume_type
  availability_zone = var.volume_availability_zone
  metadata = merge(local.common_metadata, {
    instance = local.enabled_vms[each.value.instance_key].name
    purpose  = each.key
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_compute_volume_attach_v2" "data" {
  for_each = local.data_volumes

  instance_id = openstack_compute_instance_v2.vm[each.value.instance_key].id
  volume_id   = openstack_blockstorage_volume_v3.data[each.key].id
}
