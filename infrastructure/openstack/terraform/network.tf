data "openstack_networking_network_v2" "external" {
  count = local.native_gateway_enabled ? 1 : 0
  name  = trimspace(coalesce(var.external_network_name, "__missing_external_network__"))
}

resource "openstack_networking_network_v2" "lab" {
  name           = var.lab_network_name
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "lab" {
  name            = var.lab_subnet_name
  network_id      = openstack_networking_network_v2.lab.id
  cidr            = var.lab_cidr
  ip_version      = 4
  enable_dhcp     = var.enable_neutron_dhcp
  no_gateway      = var.gateway_mode == "isolated"
  gateway_ip      = var.gateway_mode == "native" ? var.lab_gateway_ip : null
  dns_nameservers = var.lab_dns_servers

  allocation_pool {
    start = "10.10.10.2"
    end   = "10.10.10.99"
  }

  allocation_pool {
    start = "10.10.10.201"
    end   = "10.10.10.254"
  }
}

resource "openstack_networking_router_v2" "lab" {
  count               = local.native_gateway_enabled ? 1 : 0
  name                = "lab-rtr01"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external[0].id
}

resource "openstack_networking_router_interface_v2" "lab" {
  count     = local.native_gateway_enabled ? 1 : 0
  router_id = openstack_networking_router_v2.lab[0].id
  subnet_id = openstack_networking_subnet_v2.lab.id
}
