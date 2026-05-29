# Proxmox Terraform – VM Provisioning

This directory contains the Terraform configuration that creates the three lab VMs on Proxmox VE using the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) provider.

---

## What Gets Created

| Resource | VMID | Hostname | Specs |
|---|---|---|---|
| `proxmox_virtual_environment_vm.dc` | 101 | lab-dc01 | 2 vCPU, 4 GB RAM, 60 GB disk |
| `proxmox_virtual_environment_vm.sccm` | 102 | lab-sccm01 | 4 vCPU, 8 GB RAM, 100 GB OS + 100 GB SQL data |
| `proxmox_virtual_environment_vm.client` | 103 | lab-client01 | 2 vCPU, 4 GB RAM, 60 GB disk |

All VMs are created on the `vmbr1` internal lab bridge (10.10.10.0/24) and attached to a VirtIO NIC. Two CD-ROM drives are attached to each server VM: one for the Windows ISO and one for the VirtIO drivers ISO.

---

## Prerequisites

Before running Terraform:

1. Proxmox VE 8.x is running and the API is accessible
2. All ISOs are uploaded to Proxmox local storage (`local:iso/...`)
3. `vmbr1` internal bridge exists on the Proxmox node
4. API token is created with Administrator role
5. `terraform.tfvars` is filled in from the example file

See `docs/prerequisites.md` for the complete checklist.

---

## Steps to Run

```bash
cd infrastructure/proxmox/terraform

# 1. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in proxmox_endpoint, proxmox_api_token, ISO names, passwords

# 2. Set environment variables
export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 3. Initialise providers (downloads bpg/proxmox provider)
terraform init

# 4. Preview the plan
terraform plan

# 5. Apply (creates VMs)
terraform apply

# 6. To destroy all VMs
terraform destroy
```

After `terraform apply`, the VMs will appear in the Proxmox UI in a **stopped** state. Start them manually from the UI or with:
```bash
qm start 101   # lab-dc01
qm start 102   # lab-sccm01
qm start 103   # lab-client01
```

---

## Variable Descriptions

| Variable | Type | Default | Description |
|---|---|---|---|
| `proxmox_endpoint` | string | – | Full URL of Proxmox API, e.g. `https://192.168.1.100:8006/` |
| `proxmox_api_token` | string (sensitive) | – | API token in format `user@pam!tokenid=secret` |
| `proxmox_node` | string | `pve` | Proxmox node name |
| `lab_network_bridge` | string | `vmbr1` | Internal lab network bridge |
| `wan_bridge` | string | `vmbr0` | Home LAN bridge (for reference only) |
| `iso_storage` | string | `local` | Proxmox storage containing ISOs |
| `vm_storage` | string | `local-lvm` | Storage for VM disks |
| `windows_server_iso` | string | – | Filename of WinSrv2022 ISO in `local:iso/` |
| `windows_11_iso` | string | – | Filename of Win11 ISO in `local:iso/` |
| `virtio_iso` | string | `virtio-win.iso` | Filename of VirtIO drivers ISO |
| `domain_name` | string | `lab.local` | AD domain name |
| `domain_netbios` | string | `LAB` | NetBIOS domain name |
| `safe_mode_password` | string (sensitive) | – | AD DSRM password |
| `admin_password` | string (sensitive) | – | Local Administrator password for VMs |

---

## File Structure

```
terraform/
├── versions.tf              # Terraform and provider version constraints
├── provider.tf              # bpg/proxmox provider configuration
├── variables.tf             # Input variable declarations
├── main.tf                  # VM resource definitions
├── outputs.tf               # Output values (VMID, names)
└── terraform.tfvars.example # Example variables file (safe to commit)
```

The actual `terraform.tfvars` file is excluded by `.gitignore` because it contains sensitive values (API token, passwords).

---

## Notes on the bpg/proxmox Provider

The `bpg/proxmox` provider is a well-maintained community provider for Proxmox VE. Key behaviour:

- `insecure = true` in `provider.tf` disables TLS certificate verification (Proxmox uses a self-signed cert by default)
- VM disks use `virtio-scsi-pci` controller for best performance
- Windows VMs benefit from `os_type = "win11"` which enables Hyper-V enlightenments
- The provider creates VMs but does **not** install the OS — that is still a manual step (boot from ISO)
