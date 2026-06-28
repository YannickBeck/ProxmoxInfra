# =======================================================================
# ProxmoxInfra – Nutanix AHV Lab VM Provisioning
# =======================================================================
# Creates the same Windows lab VMs as the Proxmox module, but on a
# Nutanix AHV cluster via the nutanix/nutanix Terraform provider.
#
# AHV runs KVM with built-in VirtIO support — no separate VirtIO drivers
# ISO is required. Upload the OS installer ISOs to the Nutanix image
# service (Prism → Settings → Image Configuration) and provide their
# UUIDs in terraform.tfvars.
#
# VM layout:
#   lab-fw01        pfSense CE router/firewall          (enable_pfsense)
#   lab-dc01        Domain Controller                   (always)
#   lab-sccm01      SCCM + SQL Server                   (always)
#   lab-client01    Windows 11 Enterprise client        (always)
#   lab-ca01        AD CS Enterprise Root CA            (enable_ca)
#   lab-dc02        Secondary Domain Controller         (enable_dc02)
#   lab-aadc01      Entra Connect Sync server           (enable_aadconnect)
#   lab-opnsense01  OPNsense CE router/firewall         (enable_opnsense, mutex pfsense)
#   lab-client02    Second Windows 11 client            (enable_client02)
#   lab-cloudsync01 Entra Cloud Sync agent              (enable_cloudsync)
#   lab-linux01     Ubuntu 22.04 LTS client             (enable_linux_client)
#   lab-linux02     Rocky Linux 9 client                (enable_linux_client, count=2)
#   lab-rootca01    Offline standalone Root CA          (enable_twotier_pki)
#   lab-subca01     Enterprise Subordinate/Issuing CA   (enable_twotier_pki)
# =======================================================================

locals {
  # 1 GiB in bytes — used for disk_size_bytes calculations
  gib = 1073741824
}

# -----------------------------------------------------------------------
# lab-dc01 – Domain Controller (Windows Server 2022)
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "dc01" {
  name                 = "lab-dc01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-sccm01 – SCCM + SQL Server (Windows Server 2022)
# -----------------------------------------------------------------------
# Three disks: OS (scsi0, 100 GB), SQL data (scsi1, 100 GB),
# optional WSUS content disk (scsi2, wsus_content_disk_size GB).
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "sccm01" {
  name                 = "lab-sccm01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 4
  num_sockets          = 1
  memory_size_mib      = 8192

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  # OS disk — 100 GB for Windows, SCCM binaries, content library
  disk_list {
    disk_size_bytes = 100 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  # SQL Server data disk — 100 GB for database files and logs
  disk_list {
    disk_size_bytes = 100 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 1
        adapter_type = "SCSI"
      }
    }
  }

  # Optional WSUS / Software Update Point content disk
  dynamic "disk_list" {
    for_each = var.wsus_content_disk_size > 0 ? [var.wsus_content_disk_size] : []
    content {
      disk_size_bytes = disk_list.value * local.gib
      device_properties {
        device_type = "DISK"
        disk_address {
          device_index = 2
          adapter_type = "SCSI"
        }
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-client01 – Windows 11 Enterprise Evaluation client
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "client01" {
  name                 = "lab-client01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_11_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# =======================================================================
# OPTIONAL EXTENSION VMs
# =======================================================================

# -----------------------------------------------------------------------
# lab-fw01 – pfSense CE router/firewall              [enable_pfsense]
# -----------------------------------------------------------------------
# Dual-homed: NIC 1 = WAN (wan_subnet_uuid, gets DHCP from home router),
# NIC 2 = LAN (lab_subnet_uuid, static 10.10.10.1).
# When deployed, pfSense owns 10.10.10.1 — reconfigure the lab subnet
# gateway accordingly. Mutually exclusive with OPNsense.
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "pfsense" {
  count = var.enable_pfsense ? 1 : 0

  name                 = "lab-fw01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 2048

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.pfsense_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 16 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  # NIC 1 — WAN (uplink / home-LAN subnet) → em0 in pfSense
  nic_list {
    subnet_uuid = var.wan_subnet_uuid
  }

  # NIC 2 — LAN (isolated lab subnet) → em1 in pfSense
  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-ca01 – AD CS Enterprise Root CA               [enable_ca]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "ca01" {
  count = var.enable_ca ? 1 : 0

  name                 = "lab-ca01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-dc02 – Secondary Domain Controller            [enable_dc02]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "dc02" {
  count = var.enable_dc02 ? 1 : 0

  name                 = "lab-dc02"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-aadc01 – Entra Connect Sync server            [enable_aadconnect]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "aadc01" {
  count = var.enable_aadconnect ? 1 : 0

  name                 = "lab-aadc01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-opnsense01 – OPNsense CE router/firewall      [enable_opnsense]
# -----------------------------------------------------------------------
# Mutually exclusive with pfSense: not created if enable_pfsense is true.
# Dual-homed: NIC 1 = WAN, NIC 2 = LAN (10.10.10.1).
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "opnsense01" {
  count = var.enable_opnsense && !var.enable_pfsense ? 1 : 0

  name                 = "lab-opnsense01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 2048

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.opnsense_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 16 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  # NIC 1 — WAN
  nic_list {
    subnet_uuid = var.wan_subnet_uuid
  }

  # NIC 2 — LAN (lab subnet, 10.10.10.1)
  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-client02 – Second Windows 11 client           [enable_client02]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "client02" {
  count = var.enable_client02 ? 1 : 0

  name                 = "lab-client02"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_11_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-linux01 – Ubuntu 22.04 LTS client             [enable_linux_client]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "linux01" {
  count = var.enable_linux_client ? 1 : 0

  name                 = "lab-linux01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 2048

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.ubuntu_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 40 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-linux02 – Rocky Linux 9 client       [enable_linux_client + count=2]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "linux02" {
  count = var.enable_linux_client && var.linux_client_count >= 2 ? 1 : 0

  name                 = "lab-linux02"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 2048

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.rocky_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 40 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-cloudsync01 – Entra Cloud Sync agent          [enable_cloudsync]
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "cloudsync01" {
  count = var.enable_cloudsync ? 1 : 0

  name                 = "lab-cloudsync01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-rootca01 – Offline standalone Root CA         [enable_twotier_pki]
# -----------------------------------------------------------------------
# Workgroup machine (NOT domain-joined). Powers on only to sign the issuing
# CA certificate, then is shut down and kept offline to protect the root key.
# Created together with lab-subca01 by the single enable_twotier_pki toggle.
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "rootca01" {
  count = var.enable_twotier_pki ? 1 : 0

  name                 = "lab-rootca01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 2048

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  # Connected to the lab subnet for initial cert exchange only.
  # Disconnect / power off after the subordinate CA certificate is installed.
  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}

# -----------------------------------------------------------------------
# lab-subca01 – Enterprise Subordinate/Issuing CA   [enable_twotier_pki]
# -----------------------------------------------------------------------
# Domain-joined. This CA stays online and issues day-to-day certificates for
# SCCM HTTPS, LDAPS on the DCs, and client auto-enrollment via GPO.
# Created together with lab-rootca01 by the single enable_twotier_pki toggle.
# -----------------------------------------------------------------------
resource "nutanix_virtual_machine" "subca01" {
  count = var.enable_twotier_pki ? 1 : 0

  name                 = "lab-subca01"
  cluster_uuid         = var.nutanix_cluster_uuid
  num_vcpus_per_socket = 2
  num_sockets          = 1
  memory_size_mib      = 4096

  disk_list {
    data_source_reference {
      kind = "image"
      uuid = var.windows_server_image_uuid
    }
    device_properties {
      device_type = "CDROM"
      disk_address {
        device_index = 0
        adapter_type = "IDE"
      }
    }
  }

  disk_list {
    disk_size_bytes = 60 * local.gib
    device_properties {
      device_type = "DISK"
      disk_address {
        device_index = 0
        adapter_type = "SCSI"
      }
    }
  }

  nic_list {
    subnet_uuid = var.lab_subnet_uuid
  }

  power_state = "OFF"

  lifecycle {
    ignore_changes = [power_state]
  }
}
