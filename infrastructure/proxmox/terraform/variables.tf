# -----------------------------------------------------------------------
# Proxmox connection
# -----------------------------------------------------------------------

variable "proxmox_endpoint" {
  type        = string
  description = "Full HTTPS URL of the Proxmox API endpoint, e.g. https://192.168.1.100:8006/"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in format user@realm!tokenid=secret, e.g. terraform@pam!lab=xxxxxxxx-..."
}

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Name of the Proxmox node to create VMs on. Check the node name in the Proxmox UI sidebar."
}

# -----------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------

variable "lab_network_bridge" {
  type        = string
  default     = "vmbr1"
  description = "Name of the internal lab network bridge (isolated, no uplink). Must exist on the Proxmox node."
}

variable "wan_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Name of the WAN/home LAN bridge. Used for reference only; VMs do not attach to this by default."
}

# -----------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------

variable "iso_storage" {
  type        = string
  default     = "local"
  description = "Proxmox storage ID where ISO images are uploaded. Typically 'local' (uses /var/lib/vz/template/iso/)."
}

variable "vm_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage ID for VM disk images. Typically 'local-lvm' for LVM thin provisioning."
}

# -----------------------------------------------------------------------
# ISO filenames
# -----------------------------------------------------------------------

variable "windows_server_iso" {
  type        = string
  description = "Filename of the Windows Server 2022 Evaluation ISO as it appears in Proxmox local storage."
}

variable "windows_11_iso" {
  type        = string
  description = "Filename of the Windows 11 Enterprise Evaluation ISO as it appears in Proxmox local storage."
}

variable "virtio_iso" {
  type        = string
  default     = "virtio-win.iso"
  description = "Filename of the VirtIO drivers ISO. Provides paravirtualized storage and network drivers for Windows."
}

# -----------------------------------------------------------------------
# Active Directory domain
# -----------------------------------------------------------------------

variable "domain_name" {
  type        = string
  default     = "lab.local"
  description = "Active Directory domain name (FQDN), e.g. lab.local."
}

variable "domain_netbios" {
  type        = string
  default     = "LAB"
  description = "NetBIOS name for the AD domain. Must be 15 characters or fewer, uppercase recommended."
}

# -----------------------------------------------------------------------
# Credentials
# -----------------------------------------------------------------------

variable "safe_mode_password" {
  type        = string
  sensitive   = true
  description = "Directory Services Restore Mode (DSRM / Safe Mode) password for the Domain Controller. Used for AD recovery."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local Administrator password set on each VM. Must meet Windows complexity requirements (12+ chars, mixed case, number, symbol)."
}

# -----------------------------------------------------------------------
# Optional extension VMs (default OFF — opt-in per docs/extensions.md)
# -----------------------------------------------------------------------
# These toggles let you grow the base 3-VM lab into a fuller enterprise
# environment. Each defaults to false so the base lab is unchanged unless
# you explicitly enable an extension in terraform.tfvars.

variable "enable_pfsense" {
  type        = bool
  default     = false
  description = "Create VM 100 (lab-fw01), a pfSense CE router/firewall providing NAT internet + segmentation for the lab. When enabled, pfSense becomes the 10.10.10.1 gateway — remove the IP from the Proxmox host's vmbr1 (see infrastructure/vms/pfsense/README.md)."
}

variable "enable_dc02" {
  type        = bool
  default     = false
  description = "Create VM 105 (lab-dc02), a secondary/replica Domain Controller at 10.10.10.11 for AD replication, DNS redundancy, and FSMO failover practice."
}

variable "enable_ca" {
  type        = bool
  default     = false
  description = "Create VM 104 (lab-ca01), an Enterprise Root CA (AD CS) at 10.10.10.30 issuing PKI certificates for SCCM HTTPS, IIS, and LDAPS."
}

variable "enable_aadconnect" {
  type        = bool
  default     = false
  description = "Create VM 106 (lab-aadc01), a member server at 10.10.10.40 running Microsoft Entra Connect Sync (Azure AD Connect) for hybrid identity / Intune co-management."
}

# -----------------------------------------------------------------------
# Optional WSUS content disk for the SCCM VM (Software Update Point)
# -----------------------------------------------------------------------

variable "wsus_content_disk_size" {
  type        = number
  default     = 0
  description = "Size in GB of an extra data disk on lab-sccm01 for WSUS/Software Update Point content. Set 0 to omit the disk; 150 is a reasonable value for a lab. Initialize it as E:\\WSUS in Windows (see setup-wsus-sup.ps1)."
}

# -----------------------------------------------------------------------
# pfSense ISO (only needed when enable_pfsense = true)
# -----------------------------------------------------------------------

variable "pfsense_iso" {
  type        = string
  default     = "pfSense-CE-2.7.2-RELEASE-amd64.iso"
  description = "Filename of the pfSense CE installer ISO in Proxmox local storage. Download from https://www.pfsense.org/download/."
}
