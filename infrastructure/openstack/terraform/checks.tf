resource "terraform_data" "configuration_guard" {
  input = {
    gateway_mode          = var.gateway_mode
    external_network_name = var.external_network_name
    lab_gateway_ip        = var.lab_gateway_ip
  }

  lifecycle {
    precondition {
      condition = var.gateway_mode != "native" ? true : try(
        trimspace(var.external_network_name) != "",
        false
      )
      error_message = "external_network_name is required when gateway_mode is native."
    }

    precondition {
      condition     = var.enable_external_egress ? var.gateway_mode == "native" : true
      error_message = "enable_external_egress requires gateway_mode to be native."
    }

  }
}
