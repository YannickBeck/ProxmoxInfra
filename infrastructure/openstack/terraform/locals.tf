locals {
  native_gateway_enabled = var.gateway_mode == "native" ? try(
    trimspace(var.external_network_name) != "",
    false
  ) : false

  deploy_identity   = contains(["identity", "servers", "all"], var.deployment_stage)
  deploy_servers    = contains(["servers", "all"], var.deployment_stage)
  deploy_clients    = var.deployment_stage == "all"
  deploy_extensions = var.deployment_stage == "all"

  common_metadata = merge(var.non_sensitive_metadata, {
    environment = var.environment
    managed_by  = "terraform"
    owner       = var.owner
    project     = "proxmoxinfra"
  })

  vm_catalog = {
    dc01 = {
      name         = "lab-dc01"
      role         = "domain-controller"
      image_key    = "windows_server"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 10)
      root_size_gb = 60
      enabled      = local.deploy_identity
    }
    dc02 = {
      name         = "lab-dc02"
      role         = "domain-controller-secondary"
      image_key    = "windows_server"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 11)
      root_size_gb = 60
      enabled      = local.deploy_extensions && var.enable_dc02
    }
    sccm01 = {
      name         = "lab-sccm01"
      role         = "sccm-sql"
      image_key    = "windows_server"
      flavor_name  = var.flavor_names.windows_large
      ip_address   = cidrhost(var.lab_cidr, 20)
      root_size_gb = 100
      enabled      = local.deploy_servers
    }
    ca01 = {
      name         = "lab-ca01"
      role         = "certificate-authority"
      image_key    = "windows_server"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 30)
      root_size_gb = 60
      enabled      = local.deploy_extensions && var.enable_ca
    }
    aadc01 = {
      name         = "lab-aadc01"
      role         = "entra-connect"
      image_key    = "windows_server"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 40)
      root_size_gb = 60
      enabled      = local.deploy_extensions && var.enable_aadconnect
    }
    client01 = {
      name         = "lab-client01"
      role         = "windows-client"
      image_key    = "windows_client"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 50)
      root_size_gb = 60
      enabled      = local.deploy_clients
    }
    client02 = {
      name         = "lab-client02"
      role         = "windows-client"
      image_key    = "windows_client"
      flavor_name  = var.flavor_names.windows_small
      ip_address   = cidrhost(var.lab_cidr, 51)
      root_size_gb = 60
      enabled      = local.deploy_extensions && var.enable_client02
    }
    linux01 = {
      name         = "lab-linux01"
      role         = "linux-client-ubuntu"
      image_key    = "ubuntu"
      flavor_name  = var.flavor_names.linux_small
      ip_address   = cidrhost(var.lab_cidr, 60)
      root_size_gb = 40
      enabled      = local.deploy_extensions && var.enable_linux_client
    }
    linux02 = {
      name         = "lab-linux02"
      role         = "linux-client-rocky"
      image_key    = "rocky"
      flavor_name  = var.flavor_names.linux_small
      ip_address   = cidrhost(var.lab_cidr, 61)
      root_size_gb = 40
      enabled      = local.deploy_extensions && var.enable_linux_client && var.linux_client_count == 2
    }
  }

  enabled_vms = {
    for key, spec in local.vm_catalog : key => spec if spec.enabled
  }

  data_volume_catalog = {
    sccm_sql = {
      instance_key = "sccm01"
      name         = "lab-sccm01-sql-data"
      description  = "SQL Server data, logs, and backups for lab-sccm01"
      size_gb      = 100
      enabled      = true
    }
    sccm_wsus = {
      instance_key = "sccm01"
      name         = "lab-sccm01-wsus-content"
      description  = "WSUS and SCCM Software Update Point content"
      size_gb      = var.wsus_content_disk_size
      enabled      = var.wsus_content_disk_size > 0
    }
  }

  data_volumes = {
    for key, spec in local.data_volume_catalog : key => spec if local.deploy_servers && spec.enabled
  }

  management_rules = {
    for rule in flatten([
      for cidr in var.management_cidrs : [
        { key = "${replace(cidr, "/", "-")}-rdp", cidr = cidr, port = 3389, service = "RDP" },
        { key = "${replace(cidr, "/", "-")}-winrm-https", cidr = cidr, port = 5986, service = "WinRM HTTPS" },
        { key = "${replace(cidr, "/", "-")}-ssh", cidr = cidr, port = 22, service = "SSH" }
      ]
    ]) : rule.key => rule
  }
}
