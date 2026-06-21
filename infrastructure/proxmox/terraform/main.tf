# =======================================================================
# ProxmoxInfra – Lab VM Provisioning
# =======================================================================
# Creates three Windows lab VMs on Proxmox VE using the bpg/proxmox
# provider. VMs are created in a stopped state; boot them manually to
# begin OS installation from the attached ISO images.
#
# VM layout:
#   100 – lab-fw01      : pfSense router/firewall       (optional, enable_pfsense)
#   101 – lab-dc01      : Domain Controller (Windows Server 2022)
#   102 – lab-sccm01    : SCCM + SQL Server (Windows Server 2022)
#   103 – lab-client01  : Windows 11 Enterprise client
#   104 – lab-ca01      : AD CS Enterprise Root CA       (optional, enable_ca)
#   105 – lab-dc02      : Secondary Domain Controller    (optional, enable_dc02)
#   106 – lab-aadc01    : Azure AD Connect server        (optional, enable_aadconnect)
#   107 – lab-opnsense01: OPNsense CE router/firewall    (optional, enable_opnsense; mutually exclusive with 100)
#   108 – lab-client02  : Second Windows 11 client       (optional, enable_client02)
#   110 – lab-linux01   : Ubuntu 22.04 LTS client        (optional, enable_linux_client)
#   111 – lab-linux02   : Rocky Linux 9 client           (optional, enable_linux_client + linux_client_count=2)
#   120 – lab-nas01     : TrueNAS SCALE NAS              (optional, enable_nas)
#   127 – lab-docusaurus01: Dedicated docs VM            (optional, enable_docusaurus)
#
# VMs 100/104/105/106/107/108/110/111/120/127 are opt-in extensions (see docs/extensions.md).
# Each is guarded by a `count` based on its enable_* toggle and defaults to OFF.
# =======================================================================

locals {
  win_server_iso = "${var.iso_storage}:iso/${var.windows_server_iso}"
  win11_iso      = "${var.iso_storage}:iso/${var.windows_11_iso}"
  pfsense_iso    = "${var.iso_storage}:iso/${var.pfsense_iso}"
}

# The provider currently manages one CD-ROM per VM. During Windows setup,
# attach var.virtio_iso temporarily as ide3 in the Proxmox UI and detach it
# after the storage and network drivers are installed.

# -----------------------------------------------------------------------
# VM 101 – lab-dc01 (Domain Controller)
# -----------------------------------------------------------------------
# Hosts Active Directory Domain Services (AD DS), DNS, and DHCP for the
# lab.local domain. Must be started and fully provisioned before SCCM or
# the client VM can be domain-joined.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "dc" {
  vm_id     = 101
  name      = "lab-dc01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Domain Controller – Windows Server 2022, AD DS, DNS, DHCP for lab.local"

  # Use Windows-optimised settings (enables Hyper-V enlightenments)
  operating_system {
    type = "win11"
  }

  bios = "seabios"

  # ---------- CPU & Memory ----------
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  # ---------- Disks ----------
  # Primary OS disk – 60 GB, VirtIO SCSI
  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # CD-ROM 1: Windows Server 2022 ISO (used for OS installation)
  cdrom {
    file_id   = local.win_server_iso
    interface = "ide2"
  }

  # ---------- Network ----------
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  # ---------- Display ----------
  vga {
    type = "std"
  }

  # ---------- Boot Order ----------
  # Boot from IDE2 (Windows ISO) first, then fall through to SCSI0 (disk)
  boot_order = ["ide2", "scsi0"]

  # ---------- SCSI Controller ----------
  scsi_hardware = "virtio-scsi-pci"

  # VMs are created stopped — start manually after Terraform apply
  started = false

  # Keep VMs when Terraform state is destroyed (prevents accidental data loss)
  # Remove or set to false if you want `terraform destroy` to delete VMs
  lifecycle {
    ignore_changes = [
      # Ignore changes to started state so Terraform doesn't stop running VMs
      started,
    ]
  }
}

# -----------------------------------------------------------------------
# VM 102 – lab-sccm01 (SCCM + SQL Server)
# -----------------------------------------------------------------------
# Hosts Microsoft System Center Configuration Manager (SCCM) Current
# Branch and SQL Server 2019/2022. SCCM is the primary tool for software
# deployment, OS deployment, and co-management with Intune.
#
# Two disks:
#   scsi0 – 100 GB OS and SCCM binaries
#   scsi1 – 100 GB SQL Server data and logs
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "sccm" {
  vm_id     = 102
  name      = "lab-sccm01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab SCCM Server – Windows Server 2022, SCCM Current Branch, SQL Server 2019/2022"

  operating_system {
    type = "win11"
  }

  bios = "seabios"

  # ---------- CPU & Memory ----------
  # SCCM + SQL requires more resources than the DC
  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  # ---------- Disks ----------
  # Primary OS disk – 100 GB (OS + SCCM binaries + content library)
  disk {
    datastore_id = var.vm_storage
    size         = 100
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Secondary disk – 100 GB (SQL Server data files, logs, backups)
  disk {
    datastore_id = var.vm_storage
    size         = 100
    interface    = "scsi1"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # Optional third disk for WSUS / Software Update Point content.
  # Created only when wsus_content_disk_size > 0. Initialize it as E:\WSUS
  # in Windows (see infrastructure/vms/sccm/powershell/setup-wsus-sup.ps1).
  dynamic "disk" {
    for_each = var.wsus_content_disk_size > 0 ? [1] : []
    content {
      datastore_id = var.vm_storage
      size         = var.wsus_content_disk_size
      interface    = "scsi2"
      file_format  = "raw"
      ssd          = true
      discard      = "on"
    }
  }

  # CD-ROM 1: Windows Server 2022 ISO
  cdrom {
    file_id   = local.win_server_iso
    interface = "ide2"
  }

  # ---------- Network ----------
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  # ---------- Display ----------
  vga {
    type = "std"
  }

  # ---------- Boot Order ----------
  boot_order = ["ide2", "scsi0"]

  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]
  }
}

# -----------------------------------------------------------------------
# VM 103 – lab-client01 (Windows 11 Enterprise Client)
# -----------------------------------------------------------------------
# Windows 11 Enterprise Evaluation client VM. Domain-joined to lab.local,
# managed by SCCM, and optionally enrolled in Microsoft Intune for
# co-management testing.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "client" {
  vm_id     = 103
  name      = "lab-client01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Windows 11 Client – Enterprise Eval, domain-joined, SCCM + Intune managed"

  operating_system {
    type = "win11"
  }

  bios = "seabios"

  # ---------- CPU & Memory ----------
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  # ---------- Disk ----------
  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # CD-ROM 1: Windows 11 Enterprise Evaluation ISO
  cdrom {
    file_id   = local.win11_iso
    interface = "ide2"
  }

  # ---------- Network ----------
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  # ---------- Display ----------
  vga {
    type = "std"
  }

  # ---------- Boot Order ----------
  boot_order = ["ide2", "scsi0"]

  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]
  }
}

# =======================================================================
# OPTIONAL EXTENSION VMs
# =======================================================================
# The resources below are created only when their enable_* toggle is true
# (all default to false). See docs/extensions.md for the full guide.
# =======================================================================

# -----------------------------------------------------------------------
# VM 100 – lab-fw01 (pfSense CE router / firewall)   [enable_pfsense]
# -----------------------------------------------------------------------
# Dual-homed router between the home LAN (vmbr0, WAN) and the isolated lab
# network (vmbr1, LAN). Provides NAT internet access and segmentation for
# the lab. When deployed, pfSense owns the 10.10.10.1 gateway address, so
# remove the IP from the Proxmox host's vmbr1 interface to avoid a clash
# (see infrastructure/vms/pfsense/README.md).
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "pfsense" {
  count     = var.enable_pfsense ? 1 : 0
  vm_id     = 100
  name      = "lab-fw01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.network_firewall.pool_id

  description = "Lab pfSense CE router/firewall – NAT + segmentation (WAN vmbr0 / LAN vmbr1 10.10.10.1)"

  # pfSense is FreeBSD-based — use the generic 'other' OS type
  operating_system {
    type = "other"
  }

  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Small system disk — pfSense needs little storage
  disk {
    datastore_id = var.vm_storage
    size         = 16
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  # pfSense installer ISO
  cdrom {
    file_id   = local.pfsense_iso
    interface = "ide2"
  }

  # NIC 1 = WAN (home LAN bridge, DHCP from the home router) -> vtnet0
  network_device {
    bridge  = var.wan_bridge
    model   = "virtio"
    enabled = true
  }

  # NIC 2 = LAN (internal lab bridge, static 10.10.10.1) -> vtnet1
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga {
    type = "std"
  }

  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = !var.enable_opnsense
      error_message = "enable_pfsense and enable_opnsense are mutually exclusive because both use 10.10.10.1."
    }
  }
}

# -----------------------------------------------------------------------
# VM 104 – lab-ca01 (AD CS Enterprise Root CA)         [enable_ca]
# -----------------------------------------------------------------------
# Domain-joined Windows Server 2022 that hosts the lab's internal PKI.
# Issues certificates for SCCM HTTPS (PKI / Enhanced HTTP), IIS, LDAPS on
# the Domain Controllers, client authentication, and code signing.
# Configure with infrastructure/vms/ca/powershell/setup-ca.ps1.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "ca" {
  count     = var.enable_ca ? 1 : 0
  vm_id     = 104
  name      = "lab-ca01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Enterprise Root CA – Windows Server 2022, AD CS PKI for SCCM/IIS/LDAPS (10.10.10.30)"

  operating_system {
    type = "win11"
  }

  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = local.win_server_iso
    interface = "ide2"
  }

  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga {
    type = "std"
  }

  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]
  }
}

# -----------------------------------------------------------------------
# VM 105 – lab-dc02 (Secondary / replica Domain Controller) [enable_dc02]
# -----------------------------------------------------------------------
# Additional Domain Controller for lab.local. Adds AD replication, DNS
# redundancy, and FSMO failover practice. Promote with
# infrastructure/vms/dc02/powershell/setup-dc02.ps1.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "dc02" {
  count     = var.enable_dc02 ? 1 : 0
  vm_id     = 105
  name      = "lab-dc02"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Secondary Domain Controller – Windows Server 2022, AD DS + DNS replica (10.10.10.11)"

  operating_system {
    type = "win11"
  }

  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = local.win_server_iso
    interface = "ide2"
  }

  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga {
    type = "std"
  }

  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]
  }
}

# -----------------------------------------------------------------------
# VM 106 – lab-aadc01 (Azure AD Connect / Entra Connect)  [enable_aadconnect]
# -----------------------------------------------------------------------
# Domain-joined member server running Microsoft Entra Connect Sync to
# synchronise lab.local into Microsoft Entra ID (Azure AD), enabling
# Hybrid Azure AD Join, Intune enrollment, and SCCM↔Intune co-management.
# Requires internet access (via pfSense NAT or a temporary uplink).
# Configure with infrastructure/azuread-connect/powershell/install-aadconnect.ps1.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "aadconnect" {
  count     = var.enable_aadconnect ? 1 : 0
  vm_id     = 106
  name      = "lab-aadc01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Azure AD Connect server – Windows Server 2022, Entra Connect Sync for hybrid identity (10.10.10.40)"

  operating_system {
    type = "win11"
  }

  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = local.win_server_iso
    interface = "ide2"
  }

  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga {
    type = "std"
  }

  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  started = false

  lifecycle {
    ignore_changes = [started]
  }
}

# -----------------------------------------------------------------------
# VM 107 – lab-opnsense01 (OPNsense CE router/firewall)   [enable_opnsense]
# -----------------------------------------------------------------------
# Alternative to pfSense (VM 100). OPNsense CE provides NAT, IDS/IPS via
# Suricata, traffic shaping, and a modern REST API for automation.
# MUTUALLY EXCLUSIVE with pfSense: only one VM can own 10.10.10.1 (LAN).
# Guard: this VM is NOT created if enable_pfsense is also true.
# When deployed: remove 10.10.10.1/24 from Proxmox host vmbr1.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "opnsense" {
  count     = var.enable_opnsense ? 1 : 0
  vm_id     = 107
  name      = "lab-opnsense01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.network_firewall.pool_id

  description = "Lab OPNsense CE router/firewall – NAT + IDS/IPS + REST API (WAN vmbr0 / LAN vmbr1 10.10.10.1)"

  operating_system { type = "other" }
  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }
  memory { dedicated = 2048 }

  disk {
    datastore_id = var.vm_storage
    size         = 16
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.opnsense_iso}"
    interface = "ide2"
  }

  # NIC 1 = WAN (home LAN bridge, DHCP from home router) → vtnet0
  network_device {
    bridge  = var.wan_bridge
    model   = "virtio"
    enabled = true
  }
  # NIC 2 = LAN (isolated lab bridge, static 10.10.10.1/24) → vtnet1
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false
  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = !var.enable_pfsense
      error_message = "enable_opnsense and enable_pfsense are mutually exclusive because both use 10.10.10.1."
    }
  }
}

# -----------------------------------------------------------------------
# VM 108 – lab-client02 (Second Windows 11 Client)         [enable_client02]
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "client02" {
  count     = var.enable_client02 ? 1 : 0
  vm_id     = 108
  name      = "lab-client02"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.sccm_lab.pool_id

  description = "Lab Windows 11 Client 2 – second managed endpoint for SCCM/Intune multi-client testing"

  operating_system { type = "win11" }
  bios = "seabios"
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }
  memory { dedicated = 4096 }

  disk {
    datastore_id = var.vm_storage
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }
  cdrom {
    file_id   = local.win11_iso
    interface = "ide2"
  }
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }
  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false
  lifecycle { ignore_changes = [started] }
}

# -----------------------------------------------------------------------
# VM 110 – lab-linux01 (Ubuntu 22.04 LTS)          [enable_linux_client]
# -----------------------------------------------------------------------
# Linux client for testing cross-platform management, monitoring agents,
# Ansible SSH workflows, and optionally AD domain join via SSSD/realm.
# Managed by Ansible over SSH — no WinRM needed.
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "linux01" {
  count     = var.enable_linux_client ? 1 : 0
  vm_id     = 110
  name      = "lab-linux01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.linux_clients.pool_id

  description = "Lab Ubuntu 22.04 LTS – Linux client, SSH-managed by Ansible, optional AD join via SSSD"

  operating_system { type = "l26" }
  bios = "seabios"
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }
  memory { dedicated = 2048 }

  disk {
    datastore_id = var.vm_storage
    size         = 40
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }
  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.ubuntu_iso}"
    interface = "ide2"
  }
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }
  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false
  lifecycle { ignore_changes = [started] }
}

# -----------------------------------------------------------------------
# VM 111 – lab-linux02 (Rocky Linux 9)    [enable_linux_client, count=2]
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "linux02" {
  count     = var.enable_linux_client && var.linux_client_count >= 2 ? 1 : 0
  vm_id     = 111
  name      = "lab-linux02"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.linux_clients.pool_id

  description = "Lab Rocky Linux 9 – RHEL-compatible Linux client for enterprise Linux testing alongside Windows"

  operating_system { type = "l26" }
  bios = "seabios"
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }
  memory { dedicated = 2048 }

  disk {
    datastore_id = var.vm_storage
    size         = 40
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }
  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.rocky_iso}"
    interface = "ide2"
  }
  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }
  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false
  lifecycle { ignore_changes = [started] }
}

# =======================================================================
# NEW NAS / DOCUMENTATION INFRASTRUCTURE
# =======================================================================

# -----------------------------------------------------------------------
# VM 120 – lab-nas01 (TrueNAS SCALE) [enable_nas]
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "nas" {
  count     = var.enable_nas ? 1 : 0
  vm_id     = 120
  name      = "lab-nas01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.nas_storage.pool_id

  description = "TrueNAS SCALE storage VM with ZFS, SMB/NFS/iSCSI and snapshot support (10.10.10.70)"

  operating_system { type = "l26" }
  bios = "seabios"

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory { dedicated = 8192 }

  disk {
    datastore_id = var.vm_storage
    size         = 32
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  disk {
    datastore_id = var.vm_storage
    size         = var.nas_data_disk_size
    interface    = "scsi1"
    file_format  = "raw"
    ssd          = false
    discard      = "on"
  }

  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.truenas_iso}"
    interface = "ide2"
  }

  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false

  lifecycle { ignore_changes = [started] }
}

# -----------------------------------------------------------------------
# VM 127 – lab-docusaurus01 (dedicated documentation VM)
# -----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "docusaurus" {
  count     = var.enable_docusaurus ? 1 : 0
  vm_id     = 127
  name      = "lab-docusaurus01"
  node_name = var.proxmox_node
  pool_id   = proxmox_virtual_environment_pool.nas_storage.pool_id

  description = "Dedicated Docusaurus documentation VM in the NAS/storage environment (10.10.10.74)"

  operating_system { type = "l26" }
  bios = "seabios"

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory { dedicated = 4096 }

  disk {
    datastore_id = var.vm_storage
    size         = 40
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.ubuntu_iso}"
    interface = "ide2"
  }

  network_device {
    bridge  = var.lab_network_bridge
    model   = "virtio"
    enabled = true
  }

  vga { type = "std" }
  boot_order    = ["ide2", "scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  started       = false

  lifecycle { ignore_changes = [started] }
}
