# -----------------------------------------------------------------------
# Nutanix connection
# -----------------------------------------------------------------------

variable "nutanix_endpoint" {
  type        = string
  description = "IP or hostname of Prism Central (preferred) or Prism Element. Do NOT include the port or path — the provider appends :9440 automatically. Example: 192.168.1.150"
}

variable "nutanix_username" {
  type        = string
  default     = "admin"
  description = "Nutanix Prism username. Create a dedicated service account in Prism Central → Administration → Users for production use."
}

variable "nutanix_password" {
  type        = string
  sensitive   = true
  description = "Password for the Nutanix Prism user."
}

variable "nutanix_insecure" {
  type        = bool
  default     = true
  description = "Skip TLS certificate verification. Set true for lab environments using the default self-signed Nutanix certificate; false in production."
}

# -----------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------

variable "nutanix_cluster_uuid" {
  type        = string
  description = "UUID of the AHV cluster to provision VMs on. Find it in Prism Element: Settings → Cluster Details, or from the browser URL when viewing the cluster dashboard."
}

# -----------------------------------------------------------------------
# Networking (subnets replace Proxmox bridges)
# -----------------------------------------------------------------------

variable "lab_subnet_uuid" {
  type        = string
  description = "UUID of the isolated lab subnet (equivalent to vmbr1 on Proxmox). This should be a VLAN-backed subnet with no default route to the internet. Find it in Prism → Network → Subnets → click the subnet → UUID in the Details pane or URL."
}

variable "wan_subnet_uuid" {
  type        = string
  default     = ""
  description = "UUID of the uplink / home-LAN subnet (equivalent to vmbr0 on Proxmox). Used only as the WAN interface on pfSense and OPNsense router VMs. Leave blank if not deploying a router VM."
}

# -----------------------------------------------------------------------
# Image UUIDs
# -----------------------------------------------------------------------
# Upload ISOs once via Prism → Settings → Image Configuration → Upload Image.
# After upload, click the image and copy the UUID from the URL or Details pane.
# AHV runs KVM and has built-in VirtIO support — no additional drivers ISO is needed.

variable "windows_server_image_uuid" {
  type        = string
  description = "UUID of the Windows Server 2022 Evaluation ISO uploaded to the Nutanix image service. Download ISO from https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022"
}

variable "windows_11_image_uuid" {
  type        = string
  description = "UUID of the Windows 11 Enterprise Evaluation ISO in the Nutanix image service. Download from https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise"
}

variable "pfsense_image_uuid" {
  type        = string
  default     = ""
  description = "UUID of the pfSense CE installer ISO in the Nutanix image service. Required only when enable_pfsense = true. Download from https://www.pfsense.org/download/"
}

variable "opnsense_image_uuid" {
  type        = string
  default     = ""
  description = "UUID of the OPNsense CE installer ISO in the Nutanix image service. Required only when enable_opnsense = true. Download from https://opnsense.org/download/"
}

variable "ubuntu_image_uuid" {
  type        = string
  default     = ""
  description = "UUID of the Ubuntu 22.04 LTS server ISO in the Nutanix image service. Required only when enable_linux_client = true. Download from https://ubuntu.com/download/server"
}

variable "rocky_image_uuid" {
  type        = string
  default     = ""
  description = "UUID of the Rocky Linux 9 DVD ISO in the Nutanix image service. Required only when enable_linux_client = true and linux_client_count = 2. Download from https://rockylinux.org/download"
}

# -----------------------------------------------------------------------
# Active Directory domain
# -----------------------------------------------------------------------

variable "domain_name" {
  type        = string
  default     = "lab.local"
  description = "Active Directory domain name (FQDN). Used as metadata only in Terraform — the actual domain is configured by Ansible/PowerShell after Windows installation."
}

variable "domain_netbios" {
  type        = string
  default     = "LAB"
  description = "NetBIOS name for the AD domain. 15 characters or fewer, uppercase recommended."
}

# -----------------------------------------------------------------------
# Credentials
# -----------------------------------------------------------------------

variable "safe_mode_password" {
  type        = string
  sensitive   = true
  description = "Directory Services Restore Mode (DSRM) password for the Domain Controller. Injected by Ansible into the DC promotion script."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local Administrator password for all Windows VMs. Must meet Windows complexity requirements (12+ chars, mixed case, number, symbol)."
}

# -----------------------------------------------------------------------
# Optional extension VMs (default OFF — opt-in per docs/extensions.md)
# -----------------------------------------------------------------------

variable "enable_pfsense" {
  type        = bool
  default     = false
  description = "Create VM lab-fw01, a pfSense CE router/firewall. Provides NAT internet for the lab subnet. Mutually exclusive with enable_opnsense."
}

variable "enable_dc02" {
  type        = bool
  default     = false
  description = "Create VM lab-dc02, a secondary replica Domain Controller for AD replication, DNS redundancy, and FSMO failover practice."
}

variable "enable_ca" {
  type        = bool
  default     = false
  description = "Create VM lab-ca01, a single-tier Enterprise Root CA (AD CS) for SCCM HTTPS, LDAPS, and client certificates. Do not enable together with enable_twotier_pki."
}

variable "enable_aadconnect" {
  type        = bool
  default     = false
  description = "Create VM lab-aadc01 running Microsoft Entra Connect Sync (Azure AD Connect) for hybrid identity and Intune co-management. Requires internet access."
}

variable "enable_opnsense" {
  type        = bool
  default     = false
  description = "Create VM lab-opnsense01, an OPNsense CE router/firewall with IDS/IPS. Mutually exclusive with enable_pfsense — only one router VM can own the 10.10.10.1 gateway."
}

variable "enable_client02" {
  type        = bool
  default     = false
  description = "Create a second Windows 11 Enterprise Evaluation client VM (lab-client02) for multi-client SCCM and Intune testing."
}

variable "enable_linux_client" {
  type        = bool
  default     = false
  description = "Create Linux client VM(s). With linux_client_count = 1: only lab-linux01 (Ubuntu 22.04). With linux_client_count = 2: also lab-linux02 (Rocky Linux 9)."
}

variable "linux_client_count" {
  type        = number
  default     = 1
  description = "Number of Linux client VMs when enable_linux_client = true. 1 = Ubuntu only. 2 = Ubuntu + Rocky Linux."

  validation {
    condition     = var.linux_client_count >= 1 && var.linux_client_count <= 2
    error_message = "linux_client_count must be 1 or 2."
  }
}

variable "enable_cloudsync" {
  type        = bool
  default     = false
  description = "Create VM lab-cloudsync01 running the Microsoft Entra Cloud Sync provisioning agent. A lightweight alternative to Entra Connect Sync (enable_aadconnect). Requires internet access."
}

variable "enable_twotier_pki" {
  type        = bool
  default     = false
  description = "Create a two-tier PKI: lab-rootca01 (offline standalone Root CA, workgroup) and lab-subca01 (Enterprise Subordinate/Issuing CA, domain-joined). Do not enable together with enable_ca."
}

# -----------------------------------------------------------------------
# Optional WSUS content disk on the SCCM VM
# -----------------------------------------------------------------------

variable "wsus_content_disk_size" {
  type        = number
  default     = 0
  description = "Size in GB of an extra data disk on lab-sccm01 for WSUS/Software Update Point content. Set 0 to omit. 150 GB is a reasonable lab value."
}
