# Nutanix AHV – ProxmoxInfra Lab

Terraform module that provisions the same Windows lab VMs as the Proxmox module, but on a **Nutanix AHV cluster** via the `nutanix/nutanix` Terraform provider. The Ansible playbooks and PowerShell scripts in this repo are **platform-agnostic** — they run unchanged against VMs on either hypervisor.

---

## Proxmox vs Nutanix — key differences

| Concept | Proxmox | Nutanix AHV |
|---|---|---|
| Hypervisor | KVM (via QEMU) | KVM (AHV, built-in) |
| Management UI | Proxmox Web UI (port 8006) | Prism Element / Prism Central (port 9440) |
| Terraform provider | `bpg/proxmox` | `nutanix/nutanix` |
| Network isolation | Linux bridge `vmbr1` (no uplink) | VLAN-backed subnet (no default route) |
| Driver ISO | VirtIO drivers ISO required | Not needed — AHV includes VirtIO natively |
| ISO storage | Proxmox local storage (`local:iso/...`) | Nutanix image service (upload via Prism) |
| VM disk storage | Storage pool (`local-lvm`) | Storage container (auto-managed by AOS) |
| VM start state | `started = false` | `power_state = "OFF"` |
| VM identification | Integer VMID (101, 102 ...) | UUID (long hex string) |
| WOL / remote power | Raspberry Pi WOL API | Prism API (`POST /vms/{uuid}/power_on`) |

---

## Prerequisites

Before running `terraform apply`:

1. **Nutanix cluster running AHV** with Prism Element or Prism Central accessible on port 9440.
2. **Nutanix API user** — the default `admin` account works for a lab. In production, create a dedicated user in Prism Central → Administration → Users with `User Admin` and `VM Admin` roles.
3. **Upload installer ISOs** to the Nutanix image service:
   - Prism → Settings → Image Configuration → Upload Image
   - Add the ISO URL directly or upload from a local file
   - Required: Windows Server 2022 Eval, Windows 11 Eval
   - Optional (for extension VMs): pfSense/OPNsense ISO, Ubuntu ISO, Rocky Linux ISO
   - AHV has built-in VirtIO support — no separate VirtIO drivers ISO needed
4. **Create the lab subnet** in Prism:
   - Prism → Network → Create Subnet
   - Type: VLAN
   - VLAN ID: choose an unused VLAN (e.g. 100) on your physical switches
   - No IP pool needed (static IPs assigned inside the VMs)
   - This subnet is equivalent to Proxmox's `vmbr1` (isolated internal network)
5. **Find UUIDs** for the cluster, subnets, and uploaded images:
   - Cluster UUID: Prism Element → Settings → Cluster Details, or from the Prism URL
   - Subnet UUID: Prism → Network → click the subnet → UUID in the Details pane
   - Image UUID: Prism → Settings → Image Configuration → click the image → UUID in the URL

---

## Quick Start

```bash
cd infrastructure/nutanix/terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# Export sensitive credentials as env vars (preferred over tfvars)
export TF_VAR_nutanix_password="your-prism-password"
export TF_VAR_admin_password="LabAdmin!P@ssw0rd1"
export TF_VAR_safe_mode_password="SafeMode!P@ssw0rd1"

# Initialise
terraform init

# Preview
terraform plan

# Create VMs (all created in OFF state)
terraform apply
```

After apply, start VMs via Prism UI or the Nutanix API:

```bash
# Using Nutanix CLI (nCLI on the CVM)
acli vm.on lab-dc01

# Or via Prism API (from any machine with network access to Prism):
VM_UUID=$(terraform output -raw dc01_uuid)
curl -sk -u admin:${PRISM_PASS} \
  -X POST "https://${PRISM_IP}:9440/api/nutanix/v3/vms/${VM_UUID}/power_on"
```

---

## Lab Network Setup on Nutanix

### Isolated Lab Subnet (replaces Proxmox vmbr1)

Create a VLAN-backed subnet in Prism with a VLAN ID that maps to an isolated VLAN on your physical switch (or an unused VLAN that you trunk to the AHV host's uplink). No IPAM/DHCP pool is needed — Windows DHCP on the DC serves the lab range.

If you do not have a managed switch with VLAN support, create an **unmanaged subnet** in Prism — this creates an isolated Layer 2 segment local to the AHV cluster without tagging, equivalent to a bridge-only port group.

### WAN / Uplink Subnet (for pfSense / OPNsense only)

If deploying a router VM, also create a second subnet mapped to the VLAN that connects to your home router. pfSense and OPNsense will get their WAN IP from the home router's DHCP on this subnet.

### Static IP assignment

After Windows installation, set static IPs on each VM exactly as documented in `docs/network-design.md` — the addresses are the same regardless of hypervisor:

| VM | Static IP |
|---|---|
| lab-dc01 | 10.10.10.10 |
| lab-sccm01 | 10.10.10.20 |
| lab-client01 | 10.10.10.50 (or DHCP) |

---

## Windows Installation

VMs are created with the installer ISO attached as a CDROM. Boot each VM from Prism:

1. Prism → VMs → select VM → Power On
2. Click Launch Console (VNC/HTML5)
3. Follow the Windows installer
4. AHV already provides VirtIO SCSI and network drivers — no driver loading step needed

After OS installation, proceed with Ansible (same playbooks as for Proxmox):

```bash
cd ansible
cp inventory/lab.yml.example inventory/lab.yml
nano inventory/lab.yml   # fill in IPs

ansible-playbook -i inventory/lab.yml playbooks/site.yml
```

---

## Nutanix Calm (optional)

If your cluster has **Nutanix Calm** (requires Prism Central), you can use Calm Blueprints for cloud-init-based OS deployment instead of the manual ISO install step. Calm can inject cloud-init user-data directly into the VM at creation time, automating:

- Hostname, IP, timezone
- WinRM activation (for Windows)
- SSH key deployment (for Linux)

This is equivalent to the Packer golden-image workflow on Proxmox. Calm Blueprints for Windows require a pre-built cloud image (Sysprep template) or a Nutanix Image with cloud-init agent (Cloudbase-Init for Windows).

See `infrastructure/packer/README.md` for the Packer approach, which works on both Proxmox and Nutanix AHV.

---

## Terraform State Notes

Nutanix VMs are identified by UUIDs, not integer VMIDs. Terraform outputs each UUID via `terraform output`. Store your Terraform state remotely (Terraform Cloud, S3, or a Nutanix Objects bucket) to safely share state across team members:

```hcl
terraform {
  backend "s3" {
    bucket   = "lab-tfstate"
    key      = "nutanix/lab.tfstate"
    region   = "us-east-1"
    endpoint = "https://<nutanix-objects-ip>"   # Nutanix Objects is S3-compatible
  }
}
```

---

## Ansible Playbooks

All Ansible playbooks in `../../ansible/playbooks/` work unchanged — they connect over WinRM (Windows) and SSH (Linux), not through the hypervisor API. The only change needed in `inventory/lab.yml` is the IP addresses, which are the same on both hypervisors.

```bash
# Run the full lab setup (after Windows OS is installed on each VM)
ansible-playbook -i inventory/lab.yml playbooks/site.yml \
  --ask-vault-pass
```

See `ansible/README.md` for the full Ansible documentation.
