# ProxmoxInfra – Windows Lab Demo Environment

A fully automated Windows lab built on a Proxmox VE 8.x hypervisor, accessible from anywhere via a Raspberry Pi running ZeroTier. Designed for IT professionals testing Microsoft SCCM (Configuration Manager), Intune co-management, Active Directory, and related enterprise tooling — without needing cloud infrastructure.

> **OpenStack target:** A separate Terraform implementation and staged migration
> plan are available in
> [infrastructure/openstack](infrastructure/openstack/README.md). The existing
> Proxmox implementation remains the source environment.

---

## Architecture Overview

```
Internet
    |
    | (ZeroTier overlay 172.22.0.0/16)
    |
+---+-------------------+
|   Your Workstation    |  172.22.0.2 (ZeroTier)
+-----------------------+
            |
            | ZeroTier encrypted tunnel
            |
+---+-------------------+       +---------------------------+
|   Raspberry Pi        |       |   Home Router             |
|   192.168.1.200 (LAN) +-------+   192.168.1.1             |
|   172.22.0.1 (ZT)     |       +----------+----------------+
|   WOL sender          |                  |
|   ZeroTier node       |                  | LAN 192.168.1.0/24
+-----------+-----------+                  |
            |                   +----------+----------------+
            | WOL magic packet  |   Proxmox Host            |
            +-----------------> |   192.168.1.100 (vmbr0)   |
                                |   10.10.10.1    (vmbr1)   |
                                +----+------+------+--------+
                                     |      |      |
                       vmbr1 (10.10.10.0/24 - internal)
                                     |      |      |
                          +----------+  +---+--+  ++----------+
                          | lab-dc01 |  |sccm01|  | client01  |
                          | 10.10.10 |  |10.10.|  | 10.10.10  |
                          |    .10   |  | 10.20|  |    .50    |
                          | DC / DNS |  |SCCM+ |  | Win11     |
                          | DHCP     |  | SQL  |  | Client    |
                          +----------+  +------+  +-----------+
```

---

## Components

**Core (always deployed):**

| Component | Role | IP |
|---|---|---|
| Proxmox Host | Hypervisor | 192.168.1.100 (LAN) / 10.10.10.1 (lab, base setup) |
| lab-dc01 (VM 101) | Windows Server 2022, AD DS, DNS, DHCP | 10.10.10.10 |
| lab-sccm01 (VM 102) | Windows Server 2022, SCCM CB + SQL Server | 10.10.10.20 |
| lab-client01 (VM 103) | Windows 11 Enterprise Evaluation | 10.10.10.50 / DHCP |
| Raspberry Pi | Always-on gateway, ZeroTier node, WOL sender | 192.168.1.200 / 172.22.0.1 (ZT) |

**Extensions (opt-in via `terraform.tfvars` — see [docs/extensions.md](docs/extensions.md)):**

| Component | Role | IP | Toggle |
|---|---|---|---|
| lab-fw01 (VM 100) | pfSense CE router, NAT internet, firewall | 10.10.10.1 (LAN) | `enable_pfsense` |
| lab-opnsense01 (VM 107) | OPNsense CE router — NAT, IDS/IPS, VLANs (recommended alternative to pfSense) | 10.10.10.1 (LAN) | `enable_opnsense` |
| lab-ca01 (VM 104) | AD CS single-tier Enterprise Root CA — SCCM PKI, LDAPS | 10.10.10.30 | `enable_ca` |
| lab-rootca01 + lab-subca01 (VM 112/113) | Two-tier PKI — offline Root CA + Enterprise Issuing CA | 10.10.10.31 / .32 | `enable_twotier_pki` |
| lab-dc02 (VM 105) | Secondary DC — AD replication, DNS redundancy, FSMO drills | 10.10.10.11 | `enable_dc02` |
| lab-aadc01 (VM 106) | Entra Connect Sync — Hybrid AADJ + Intune co-mgmt | 10.10.10.40 | `enable_aadconnect` |
| lab-cloudsync01 (VM 109) | Entra Cloud Sync — lightweight hybrid identity agent | 10.10.10.41 | `enable_cloudsync` |
| lab-client02 (VM 108) | Second Windows 11 client | 10.10.10.51 / DHCP | `enable_client02` |
| lab-linux01 / lab-linux02 (VM 110/111) | Ubuntu 22.04 + Rocky Linux 9 clients | 10.10.10.60 / .61 | `enable_linux_client` |
| lab-nas01 (VM 120) | TrueNAS Scale — ZFS, SMB/NFS and backup target | 10.10.10.70 | `enable_nas` |
| lab-docusaurus01 (VM 127) | Dedicated Docusaurus documentation VM | 10.10.10.74 | `enable_docusaurus` |
| WSUS disk on SCCM | Extra data disk for Software Update Point (E:\\WSUS) | – | `wsus_content_disk_size` |
| Packer templates | Unattended Windows golden images (VMID 9000/9001) | – | Separate build step |

Further extension ideas (monitoring, SIEM, backup, jump host, and more) are catalogued in [docs/suggestions.md](docs/suggestions.md).

---

## Logical Resource Pools

Terraform creates stable Proxmox resource pools and assigns every existing VM to its project boundary. Pools remain present when optional workloads are disabled, making permissions, ownership and later automation predictable.

| Pool | Purpose | Preferred shape |
|---|---|---|
| `pool-core-access` | Physical host/Raspberry Pi inventory and Packer templates | Infrastructure boundary; physical devices are not pool members |
| `pool-sccm-lab` | AD, SCCM and Windows endpoints | Dedicated Windows VMs |
| `pool-network-firewall` | Gateway, VLAN, IDS/IPS and DNS filtering | OPNsense recommended; pfSense alternative; optional AdGuard Home |
| `pool-nas-storage` | Shared storage, backup target and dedicated docs VM | TrueNAS SCALE recommended; OpenMediaVault lightweight alternative; Docusaurus on VM 127 |
| `pool-platform-services` | Reverse proxy, DMS and Git | A few Docker Compose/LXC hosts; Forgejo preferred, GitLab CE optional/heavy |
| `pool-ai-mcp-data` | Local LLM UI, RAG, model runtime and MCP | One `lab-ai-stack01`; Qdrant/LiteLLM only when needed |
| `pool-observability-security` | Availability, metrics, logs and SIEM | Beszel + Uptime Kuma first; Grafana/Prometheus/Loki/Wazuh optional |
| `pool-backup-dr` | Protected backups and restore drills | Proxmox Backup Server preferred |
| `pool-devops-automation` | Configuration, IaC and runners | Shared Ansible/Semaphore/Terraform/OpenTofu/PowerShell host |
| `pool-linux-clients` | Cross-platform test endpoints | Ubuntu, Enterprise Linux and optional Kali |

OPNsense and pfSense are strictly mutually exclusive: both would own `10.10.10.1`. Terraform rejects a configuration that enables both. The complete tree, rollout priority, status and conflict-free VMID registry are in [docs/logical-pools.md](docs/logical-pools.md); implementation status and toggles are in [docs/extensions.md](docs/extensions.md).

Docusaurus runs independently on `lab-docusaurus01` (VMID 127, `10.10.10.74`) in `pool-nas-storage`. The root `docusaurus-site/` directory is retained as its application source; GitLab Pages is no longer part of the deployment path.

---

## Quick Start

```bash
# 1. Clone the repository
git clone <this-repo> ~/ProxmoxInfra
cd ~/ProxmoxInfra

# 2. Complete the prerequisites checklist in docs/prerequisites.md

# 3. Create internal network bridge on Proxmox (vmbr1)
# See CLAUDE.md Step 1 for instructions

# 4. Configure Terraform variables
cp infrastructure/proxmox/terraform/terraform.tfvars.example \
   infrastructure/proxmox/terraform/terraform.tfvars
# Edit terraform.tfvars with your Proxmox details

# 5. Create VMs with Terraform
cd infrastructure/proxmox/terraform
terraform init && terraform apply

# 6. Install Windows on each VM (manual — boot from ISO)
# See docs in infrastructure/vms/*/README.md

# 7. Configure Windows VMs
# Either run PowerShell scripts directly on each VM,
# or use Ansible from this machine (see ansible/README.md)

# 8. Set up Raspberry Pi
scp raspberry-pi/setup.sh pi@192.168.1.200:~/
ssh pi@192.168.1.200 "chmod +x setup.sh && sudo ./setup.sh"
```

For the full implementation guide, see **CLAUDE.md**.

---

## Repository Structure

```
ProxmoxInfra/
├── CLAUDE.md                          # Guide for Claude Code / automation runner
├── README.md                          # This file
├── .gitignore
│
├── docs/
│   ├── architecture.md                # Detailed architecture document
│   ├── logical-pools.md               # Pool tree, priorities and VMID registry
│   ├── network-design.md              # IP addressing, firewall rules, port list
│   └── prerequisites.md              # Manual steps before automation
│
├── docusaurus-site/                   # Application source for VM 127
│
├── infrastructure/
│   ├── openstack/
│   │   ├── README.md                  # OpenStack target and usage
│   │   ├── MIGRATION_PLAN.md          # Staged Proxmox-to-OpenStack migration
│   │   └── terraform/                 # Neutron, Nova, Cinder, security groups
│   │
│   ├── proxmox/
│   │   ├── README.md                  # Terraform setup overview
│   │   └── terraform/
│   │       ├── versions.tf            # Provider version constraints
│   │       ├── provider.tf            # bpg/proxmox provider config
│   │       ├── variables.tf           # All input variables
│   │       ├── pools.tf               # Stable Proxmox resource pools
│   │       ├── main.tf                # VM resource definitions
│   │       ├── outputs.tf             # VM IDs and info outputs
│   │       └── terraform.tfvars.example
│   │
│   └── vms/
│       ├── nas/                         # TrueNAS VM installation and ZFS setup
│       ├── docusaurus/                  # Dedicated docs-VM Docker deployment
│       ├── dc/
│       │   ├── README.md              # DC setup guide
│       │   └── powershell/
│       │       └── setup-dc.ps1       # AD DS, DNS, DHCP setup script
│       ├── sccm/
│       │   ├── README.md              # SCCM setup guide
│       │   └── powershell/
│       │       └── setup-sccm-prereqs.ps1
│       └── client/
│           └── README.md              # Windows 11 client setup guide
│
├── raspberry-pi/
│   ├── README.md                      # Raspberry Pi overview
│   ├── setup.sh                       # Automated Raspi setup script
│   ├── zerotier/
│   │   └── README.md                  # ZeroTier installation and config guide
│   └── wake-on-lan/
│       ├── README.md                  # WOL guide
│       ├── wol.sh                     # CLI script to send WOL magic packet
│       ├── wol-api.py                 # Flask REST API for remote WOL
│       └── wol-api.service            # systemd unit for WOL API
│
└── ansible/
│   ├── README.md
│   ├── inventory/
│   │   └── lab.yml.example
│   └── playbooks/
│       ├── dc.yml / dc02.yml / sccm.yml / ca.yml / wsus.yml
│       └── cloudsync.yml / pki-root.yml / pki-sub.yml
```

---

## Network Overview

### Lab Subnet: 10.10.10.0/24

All VMs communicate on the internal bridge `vmbr1`. OPNsense, pfSense or—when neither firewall is enabled—the Proxmox host owns the default gateway `10.10.10.1`.

| Host | IP | Role |
|---|---|---|
| OPNsense, pfSense or Proxmox (vmbr1) | 10.10.10.1 | Exactly one default gateway for the lab |
| lab-dc01 | 10.10.10.10 | DNS server, DHCP server, AD DS |
| lab-sccm01 | 10.10.10.20 | SCCM site server, SQL Server |
| lab-client01 | 10.10.10.50 | Test endpoint |
| lab-nas01 | 10.10.10.70 | TrueNAS Scale storage |
| lab-docusaurus01 | 10.10.10.74 | Independent documentation portal |
| DHCP range | 10.10.10.100–200 | Dynamic range (from DC's DHCP) |

DNS for the lab domain `lab.local` is handled by the DC at 10.10.10.10.

### Home LAN: 192.168.1.0/24

The Proxmox host and Raspberry Pi both connect here. The Proxmox host's home LAN NIC is bridged on `vmbr0`.

---

## Remote Access via ZeroTier

[ZeroTier](https://www.zerotier.com) creates an encrypted peer-to-peer overlay network between your devices. Once set up:

- The Raspberry Pi is always on and connected to ZeroTier (IP: `172.22.0.1`)
- Your workstation connects to ZeroTier and can reach the Raspi
- The Raspi can then reach the Proxmox host on the home LAN and wake it up
- After the Proxmox host is running, you can access the VMs via RDP or the Proxmox web console through an SSH tunnel or by adding the Proxmox host to ZeroTier as well

See `raspberry-pi/zerotier/README.md` for setup instructions.

---

## Wake-on-LAN via Raspberry Pi

The Raspberry Pi acts as a permanent WOL proxy:

1. Your workstation sends an HTTP request to the Raspi WOL API over ZeroTier
2. The Raspi sends a WOL magic packet to the Proxmox host's MAC address on the LAN
3. The Proxmox host powers on
4. VMs can be started via Proxmox's API or `qm start` command

```bash
# Wake Proxmox host from anywhere (via ZeroTier to Raspi)
curl -X POST http://172.22.0.1:8080/wake \
     -H "X-API-Key: your_api_key" \
     -H "Content-Type: application/json"
```

See `raspberry-pi/wake-on-lan/README.md` for full documentation.
