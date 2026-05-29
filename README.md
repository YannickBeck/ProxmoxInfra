# ProxmoxInfra – Windows Lab Demo Environment

A fully automated Windows lab built on a Proxmox VE 8.x hypervisor, accessible from anywhere via a Raspberry Pi running ZeroTier. Designed for IT professionals testing Microsoft SCCM (Configuration Manager), Intune co-management, Active Directory, and related enterprise tooling — without needing cloud infrastructure.

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

| Component | Role | IP Address |
|---|---|---|
| Proxmox Host | Hypervisor | 192.168.1.100 (home LAN) / 10.10.10.1 (lab) |
| lab-dc01 (VM 101) | Windows Server 2022, AD DS, DNS, DHCP | 10.10.10.10 |
| lab-sccm01 (VM 102) | Windows Server 2022, SCCM CB + SQL Server | 10.10.10.20 |
| lab-client01 (VM 103) | Windows 11 Enterprise Evaluation | 10.10.10.50 (static) or DHCP |
| Raspberry Pi | Always-on gateway, ZeroTier node, WOL sender | 192.168.1.200 / 172.22.0.1 (ZT) |

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
│   ├── network-design.md              # IP addressing, firewall rules, port list
│   └── prerequisites.md              # Manual steps before automation
│
├── infrastructure/
│   ├── proxmox/
│   │   ├── README.md                  # Terraform setup overview
│   │   └── terraform/
│   │       ├── versions.tf            # Provider version constraints
│   │       ├── provider.tf            # bpg/proxmox provider config
│   │       ├── variables.tf           # All input variables
│   │       ├── main.tf                # VM resource definitions
│   │       ├── outputs.tf             # VM IDs and info outputs
│   │       └── terraform.tfvars.example
│   │
│   └── vms/
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
    ├── README.md                      # Ansible overview
    ├── inventory/
    │   └── lab.yml.example            # Inventory template
    └── playbooks/
        ├── dc.yml                     # DC configuration playbook
        └── sccm.yml                   # SCCM prerequisites playbook
```

---

## Network Overview

### Lab Subnet: 10.10.10.0/24

All VMs communicate on an isolated internal bridge (`vmbr1`) with no direct internet access. The Proxmox host acts as the default gateway at `10.10.10.1`.

| Host | IP | Role |
|---|---|---|
| Proxmox (vmbr1) | 10.10.10.1 | Default gateway for lab |
| lab-dc01 | 10.10.10.10 | DNS server, DHCP server, AD DS |
| lab-sccm01 | 10.10.10.20 | SCCM site server, SQL Server |
| lab-client01 | 10.10.10.50 | Test endpoint |
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