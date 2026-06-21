resource "openstack_networking_secgroup_v2" "lab" {
  name                 = "lab-sg-common"
  description          = "Intra-lab traffic plus explicitly approved management ingress"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "lab_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.lab_cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "lab_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.lab_cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "external_egress" {
  count = var.enable_external_egress ? 1 : 0

  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "management" {
  for_each = local.management_rules

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}
