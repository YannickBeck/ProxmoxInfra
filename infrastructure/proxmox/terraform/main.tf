# =======================================================================
# ProxmoxInfra – Lab VM Provisioning
# =======================================================================
# Creates three Windows lab VMs on Proxmox VE using the bpg/proxmox
# provider. VMs are created in a stopped state; boot them manually to
# begin OS installation from the attached ISO images.
#
# VM layout:
#   101 – lab-dc01     : Domain Controller (Windows Server 2022)
#   102 – lab-sccm01   : SCCM + SQL Server (Windows Server 2022)
#   103 – lab-client01 : Windows 11 Enterprise client
# =======================================================================

locals {
  win_server_iso = "${var.iso_storage}:iso/${var.windows_server_iso}"
  win11_iso      = "${var.iso_storage}:iso/${var.windows_11_iso}"
  virtio_iso     = "${var.iso_storage}:iso/${var.virtio_iso}"
}

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
    file_id  = local.win_server_iso
    interface = "ide2"
  }

  # CD-ROM 2: VirtIO drivers ISO (load during Windows setup)
  cdrom {
    file_id  = local.virtio_iso
    interface = "ide3"
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

  # CD-ROM 1: Windows Server 2022 ISO
  cdrom {
    file_id  = local.win_server_iso
    interface = "ide2"
  }

  # CD-ROM 2: VirtIO drivers ISO
  cdrom {
    file_id  = local.virtio_iso
    interface = "ide3"
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
    file_id  = local.win11_iso
    interface = "ide2"
  }

  # CD-ROM 2: VirtIO drivers ISO (for network driver during/after install)
  cdrom {
    file_id  = local.virtio_iso
    interface = "ide3"
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
