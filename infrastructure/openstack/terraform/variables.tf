variable "cloud_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional cloud entry from clouds.yaml. Null lets the provider use OS_CLOUD or other OS_* variables."

  validation {
    condition     = var.cloud_name == null ? true : trimspace(var.cloud_name) != ""
    error_message = "cloud_name must be null or a non-empty clouds.yaml entry."
  }
}

variable "region" {
  type        = string
  default     = null
  nullable    = true
  description = "OpenStack region. Null uses the value from clouds.yaml."
}

variable "compute_availability_zone" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Nova availability zone."
}

variable "volume_availability_zone" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Cinder availability zone. Keep null unless cross-service AZ mapping is known."
}

variable "gateway_mode" {
  type        = string
  default     = "isolated"
  description = "Lab gateway mode: isolated creates no router; native uses a Neutron router and SNAT."

  validation {
    condition     = contains(["isolated", "native"], var.gateway_mode)
    error_message = "gateway_mode must be either isolated or native."
  }
}

variable "external_network_name" {
  type        = string
  default     = null
  nullable    = true
  description = "External Neutron network name. Required when gateway_mode is native."
}

variable "lab_network_name" {
  type        = string
  default     = "lab-net-internal"
  description = "Name of the isolated Neutron network."
}

variable "lab_subnet_name" {
  type        = string
  default     = "lab-subnet-internal-v4"
  description = "Name of the IPv4 Neutron subnet."
}

variable "lab_cidr" {
  type        = string
  default     = "10.10.10.0/24"
  description = "CIDR preserved from the Proxmox lab."

  validation {
    condition     = var.lab_cidr == "10.10.10.0/24"
    error_message = "This lab mapping currently requires lab_cidr to remain 10.10.10.0/24."
  }
}

variable "lab_gateway_ip" {
  type        = string
  default     = "10.10.10.1"
  description = "Gateway address used by the native Neutron router."

  validation {
    condition     = var.lab_gateway_ip == "10.10.10.1"
    error_message = "This lab mapping currently requires lab_gateway_ip to remain 10.10.10.1."
  }
}

variable "lab_dns_servers" {
  type        = list(string)
  default     = ["10.10.10.10"]
  description = "DNS servers recorded on the subnet. The primary DC remains authoritative for lab.local."
}

variable "enable_neutron_dhcp" {
  type        = bool
  default     = false
  description = "Enable Neutron DHCP. Keep false when testing the Windows DHCP role on lab-dc01."
}

variable "enable_external_egress" {
  type        = bool
  default     = false
  description = "Allow workload IPv4 egress beyond lab_cidr. Requires a routed gateway to reach external networks."
}

variable "deployment_stage" {
  type        = string
  default     = "all"
  description = "Staged rollout: foundation, identity (DC), servers (DC+SCCM), or all (clients/extensions)."

  validation {
    condition     = contains(["foundation", "identity", "servers", "all"], var.deployment_stage)
    error_message = "deployment_stage must be foundation, identity, servers, or all."
  }
}

variable "management_cidrs" {
  type        = list(string)
  default     = []
  description = "Approved IPv4 CIDRs allowed to reach RDP, WinRM, and SSH. Empty means no external management ingress."

  validation {
    condition = (
      length(distinct(var.management_cidrs)) == length(var.management_cidrs) &&
      alltrue([for cidr in var.management_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "management_cidrs must contain unique valid IPv4 CIDRs."
  }
}

variable "key_pair_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional existing Nova key pair, primarily for Linux instances."
}

variable "image_names" {
  type = object({
    windows_server = string
    windows_client = string
    ubuntu         = string
    rocky          = string
  })
  description = "Unique Glance image names. Windows images must include VirtIO and Cloudbase-Init."
}

variable "flavor_names" {
  type = object({
    windows_small = string
    windows_large = string
    linux_small   = string
  })
  description = "Existing OpenStack flavors matching 2 vCPU/4 GB, 4 vCPU/8 GB, and 2 vCPU/2 GB."
}

variable "volume_type" {
  type        = string
  description = "Required Cinder volume type verified by the operator to provide encryption at rest."

  validation {
    condition = (
      trimspace(var.volume_type) != "" &&
      var.volume_type != "REPLACE_WITH_ENCRYPTED_VOLUME_TYPE"
    )
    error_message = "volume_type must name a real, verified encrypted Cinder volume type."
  }
}

variable "enable_dc02" {
  type        = bool
  default     = false
  description = "Create lab-dc02 at 10.10.10.11."
}

variable "enable_ca" {
  type        = bool
  default     = false
  description = "Create lab-ca01 at 10.10.10.30."
}

variable "enable_aadconnect" {
  type        = bool
  default     = false
  description = "Create lab-aadc01 at 10.10.10.40."
}

variable "enable_client02" {
  type        = bool
  default     = false
  description = "Create lab-client02 at 10.10.10.51."
}

variable "enable_linux_client" {
  type        = bool
  default     = false
  description = "Create one or two Linux clients."
}

variable "linux_client_count" {
  type        = number
  default     = 1
  description = "Number of Linux clients when enabled: 1 creates Ubuntu; 2 also creates Rocky Linux."

  validation {
    condition     = contains([1, 2], var.linux_client_count)
    error_message = "linux_client_count must be 1 or 2."
  }
}

variable "wsus_content_disk_size" {
  type        = number
  default     = 0
  description = "Optional WSUS content volume size in GB. Zero omits the volume."

  validation {
    condition     = var.wsus_content_disk_size == 0 || var.wsus_content_disk_size >= 100
    error_message = "wsus_content_disk_size must be 0 or at least 100 GB."
  }
}

variable "environment" {
  type        = string
  default     = "lab"
  description = "Environment label stored in resource metadata."
}

variable "owner" {
  type        = string
  default     = "lab-admin"
  description = "Non-sensitive owner/team label stored in resource metadata."
}

variable "non_sensitive_metadata" {
  type        = map(string)
  default     = {}
  description = "Additional non-sensitive metadata for instances and data volumes."

  validation {
    condition = alltrue([
      for key in keys(var.non_sensitive_metadata) :
      length(regexall("(password|secret|token|credential|private.?key)", lower(key))) == 0
    ])
    error_message = "Metadata keys must not imply secret material; use a secret store instead."
  }
}
