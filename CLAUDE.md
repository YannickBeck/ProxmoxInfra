# CLAUDE.md – ProxmoxInfra Lab Environment

This file is the primary guide for Claude Code running **on the Proxmox machine itself** (or a workstation with direct access to the Proxmox API). It explains what this repository does, how to configure it, and the exact sequence of commands to run to stand up the full lab.

---

## Overview

ProxmoxInfra automates the provisioning of a Windows lab environment on a Proxmox VE 8.x hypervisor. The lab consists of:

- **lab-dc01** (VM 101) – Windows Server 2022, Active Directory Domain Controller for `lab.local`, DNS, DHCP
- **lab-sccm01** (VM 102) – Windows Server 2022, Microsoft SCCM Current Branch + SQL Server 2019/2022
- **lab-client01** (VM 103) – Windows 11 Enterprise Evaluation, domain-joined SCCM client

Remote access is provided by a Raspberry Pi that runs ZeroTier (always-on VPN overlay) and can send Wake-on-LAN magic packets to power the Proxmox host on demand.

The automation stack is:
- **Terraform** (`bpg/proxmox` provider) – creates and configures the VMs in Proxmox
- **Ansible** (`community.windows` / `ansible.windows`) – post-boot Windows configuration
- **PowerShell scripts** – AD DS promotion, SCCM prerequisites, domain join

---

## Prerequisites Checklist

Before running any automation, confirm each item is ready:

- [ ] **Proxmox VE 8.x** installed and accessible via HTTPS on port 8006
- [ ] **Proxmox API token** created (see section below)
- [ ] **Windows Server 2022 Evaluation ISO** uploaded to Proxmox local storage
  - Filename expected: `WinSrv2022_EN-US_eval.iso` (or update `terraform.tfvars`)
  - Download: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
  - Upload via: Proxmox UI → pve → local → ISO Images → Upload
- [ ] **Windows 11 Enterprise Evaluation ISO** uploaded to Proxmox local storage
  - Filename expected: `Win11_EN-US_eval.iso` (or update `terraform.tfvars`)
  - Download: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise
- [ ] **VirtIO drivers ISO** uploaded to Proxmox local storage
  - Filename expected: `virtio-win.iso`
  - Download: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
- [ ] **Terraform >= 1.6** installed on the machine running `terraform apply`
- [ ] **Ansible** installed with `ansible.windows` and `community.windows` collections
- [ ] **Python 3** available (for helper scripts and Ansible)
- [ ] **ZeroTier account** created and a private network configured (note the 16-character Network ID)
- [ ] **Raspberry Pi** running Raspberry Pi OS Lite 64-bit, connected to home LAN
- [ ] **Wake-on-LAN** enabled in Proxmox host BIOS/UEFI; NIC MAC address noted
- [ ] Network bridge **vmbr1** created on Proxmox host (internal lab bridge, no uplink)

---

## Implementation Order

Follow these steps in sequence. Each step depends on the previous.

### Step 1 – Create the Internal Network Bridge

On the Proxmox host, create `vmbr1` as an internal bridge with no uplink (isolated lab network):

1. In the Proxmox web UI: **Node → Network → Create → Linux Bridge**
2. Name: `vmbr1`
3. IPv4/CIDR: leave blank (VMs will have static IPs)
4. Bridge ports: leave blank (no uplink — isolated)
5. Comment: `Lab internal 10.10.10.0/24`
6. Apply configuration and reboot if prompted

Alternatively, edit `/etc/network/interfaces` on the Proxmox host:

```
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    comment Lab internal 10.10.10.0/24
```

Then: `ifreload -a`

### Step 2 – Terraform Init and Apply (VM Provisioning)

```bash
cd /home/user/ProxmoxInfra/infrastructure/proxmox/terraform

# Copy and fill in the example vars file
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # fill in your values

# Export credentials as environment variables (see section below)
export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TF_VAR_proxmox_api_token="${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}"

# Initialise providers
terraform init

# Preview what will be created
terraform plan

# Create the VMs (takes 2–5 minutes)
terraform apply
```

This creates three VMs (101, 102, 103) in Proxmox. They will be stopped after creation — boot them from the Proxmox UI or with `qm start <vmid>` to begin OS installation.

### Step 3 – Windows OS Installation (Manual)

Boot each VM from its ISO and perform a standard Windows Server 2022 / Windows 11 installation:

1. Boot **lab-dc01** (VM 101) → install Windows Server 2022 Desktop Experience
2. Boot **lab-sccm01** (VM 102) → install Windows Server 2022 Desktop Experience
3. Boot **lab-client01** (VM 103) → install Windows 11 Enterprise Evaluation

For each Server VM, install the VirtIO storage and network drivers from the second CDROM during installation (click "Load driver" and browse the `virtio-win` ISO).

### Step 4 – Windows Configuration via Ansible or PowerShell

**Option A – PowerShell scripts (direct on each VM):**

On lab-dc01, run:
```powershell
Set-ExecutionPolicy Bypass -Force
.\infrastructure\vms\dc\powershell\setup-dc.ps1
```

On lab-sccm01, run:
```powershell
.\infrastructure\vms\sccm\powershell\setup-sccm-prereqs.ps1 -DomainJoinCredential (Get-Credential)
```

**Option B – Ansible (from workstation/Proxmox host):**

Enable WinRM on each Windows VM first (run in PowerShell as Administrator on each VM):
```powershell
winrm quickconfig -y
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
```

Then from the control machine:
```bash
cd /home/user/ProxmoxInfra/ansible

# Copy inventory and fill in IPs and credentials
cp inventory/lab.yml.example inventory/lab.yml
nano inventory/lab.yml

# Run DC playbook first
ansible-playbook -i inventory/lab.yml playbooks/dc.yml

# Run SCCM prereqs after DC is ready
ansible-playbook -i inventory/lab.yml playbooks/sccm.yml
```

### Step 5 – Raspberry Pi Setup

Copy the setup script to the Raspberry Pi and run it:

```bash
scp raspberry-pi/setup.sh pi@192.168.1.200:~/
ssh pi@192.168.1.200 "chmod +x setup.sh && sudo ./setup.sh"
```

The script installs ZeroTier, prompts for the Network ID, saves the Proxmox MAC address, and starts the WOL API service.

---

## Configuring terraform.tfvars

Copy the example file and edit it:

```bash
cp infrastructure/proxmox/terraform/terraform.tfvars.example \
   infrastructure/proxmox/terraform/terraform.tfvars
```

**Required values to set:**

| Variable | Description |
|---|---|
| `proxmox_endpoint` | HTTPS URL of your Proxmox host, e.g. `https://192.168.1.100:8006/` |
| `proxmox_api_token` | API token string (see below) |
| `proxmox_node` | Proxmox node name, usually `pve` |
| `windows_server_iso` | Exact filename of WinSrv2022 ISO in Proxmox local storage |
| `windows_11_iso` | Exact filename of Win11 ISO in Proxmox local storage |
| `admin_password` | Local Administrator password for VMs |
| `safe_mode_password` | AD DS Safe Mode Administrator Password |

The `terraform.tfvars` file is in `.gitignore` to prevent accidental secret commits. Never commit it.

---

## How to Get the Proxmox API Token

1. Log in to the Proxmox web UI at `https://<proxmox-ip>:8006`
2. Navigate to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. User: `root@pam` (or create a dedicated `terraform@pam` user first under Datacenter → Users)
5. Token ID: `lab` (arbitrary name)
6. Uncheck "Privilege Separation" for simplicity in a lab (or configure proper ACLs)
7. Click **Add** — copy the secret immediately, it is only shown once

The full token string is: `terraform@pam!lab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

Grant the token sufficient permissions:
```bash
# On the Proxmox host shell
pveum acl modify / -token 'terraform@pam!lab' -role Administrator
```

---

## Environment Variables

Set these before running Terraform:

```bash
export PROXMOX_HOST="192.168.1.100"
export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Combined form used by the bpg/proxmox provider via TF_VAR
export TF_VAR_proxmox_api_token="${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}"
export TF_VAR_proxmox_endpoint="https://${PROXMOX_HOST}:8006/"
```

Or store them in a `.env` file (also in `.gitignore`) and source it:

```bash
# .env  — do not commit this file
PROXMOX_HOST=192.168.1.100
PM_API_TOKEN_ID=terraform@pam!lab
PM_API_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Then: `source .env`

---

## Commands to Run in Order

```bash
# 1. Initialize Terraform
cd /home/user/ProxmoxInfra/infrastructure/proxmox/terraform
terraform init

# 2. Review the plan
terraform plan

# 3. Create VMs
terraform apply

# 4. (After manual Windows install on each VM)
# Configure Ansible inventory
cp /home/user/ProxmoxInfra/ansible/inventory/lab.yml.example \
   /home/user/ProxmoxInfra/ansible/inventory/lab.yml
# Edit lab.yml with correct IPs and credentials

# 5. Run DC playbook
ansible-playbook -i /home/user/ProxmoxInfra/ansible/inventory/lab.yml \
                    /home/user/ProxmoxInfra/ansible/playbooks/dc.yml

# 6. Run SCCM prereqs playbook (after DC is promoted and domain is up)
ansible-playbook -i /home/user/ProxmoxInfra/ansible/inventory/lab.yml \
                    /home/user/ProxmoxInfra/ansible/playbooks/sccm.yml

# 7. Set up Raspberry Pi — SSH in and run setup.sh
```

Proxmox VM control shortcuts:
```bash
qm start 101    # Start lab-dc01
qm start 102    # Start lab-sccm01
qm start 103    # Start lab-client01
qm stop  101    # Stop lab-dc01 (graceful via guest agent if installed)
qm status 101   # Check status
```

---

## Windows Licensing Notes

This lab uses **Evaluation ISOs** which do not require product keys:

- Windows Server 2022 Evaluation: 180-day trial, renewable once with `slmgr /rearm`
- Windows 11 Enterprise Evaluation: 90-day trial
- SQL Server Evaluation: 180 days
- SCCM Current Branch Evaluation: available from Microsoft Eval Center

These are for **testing and development only**. Do not use in production.

Evaluation ISO download links:
- Windows Server 2022: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- Windows 11 Enterprise: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise
- SCCM: https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager
- SQL Server 2022: https://www.microsoft.com/en-us/evalcenter/evaluate-sql-server-2022

---

## ZeroTier Network ID

The ZeroTier Network ID is a 16-character hex string (e.g. `a1b2c3d4e5f6a7b8`). Obtain it when you create a network at https://my.zerotier.com.

Key points:
- Store the Network ID securely — you need it during the Raspberry Pi setup script
- Each device that joins the network must be **authorized** in ZeroTier Central before it can communicate
- Assign static managed IPs in ZeroTier Central: Raspi at `172.22.0.1`, workstation at `172.22.0.2`
- See `raspberry-pi/zerotier/README.md` for full setup steps

---

## Wake-on-LAN Setup Instructions

1. **In BIOS/UEFI** on the Proxmox host:
   - Enable "Wake on LAN", "Power On by PCI-E/LAN", or similar setting in the power management section
   - Disable "ErP" or "EuP" energy-saving modes (they disable WOL)
   - Save and exit BIOS

2. **Find the MAC address** of the Proxmox host's NIC:
   ```bash
   # On Proxmox host shell
   ip link show
   # Note the MAC of the LAN interface (e.g. enp3s0: aa:bb:cc:dd:ee:ff)
   ```

3. **Save to Raspberry Pi** — the `setup.sh` script prompts for the MAC and saves it to `/etc/wol/proxmox.conf`

4. **Send WOL packet**:
   ```bash
   # On Raspberry Pi
   /home/pi/ProxmoxInfra/raspberry-pi/wake-on-lan/wol.sh
   ```

5. **Via ZeroTier** (remote WOL): use the WOL REST API on port 8080:
   ```bash
   curl -X POST http://172.22.0.1:8080/wake \
        -H "X-API-Key: your_api_key" \
        -H "Content-Type: application/json"
   ```

---

## SCCM Prerequisites Notes

SCCM (Configuration Manager Current Branch) requires several components that must be downloaded from Microsoft during installation:

- **Windows ADK** (Assessment and Deployment Kit): https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
- **ADK WinPE Add-on**: downloaded alongside ADK — required for OS deployment tasks
- **SQL Server 2019 or 2022**: Evaluation edition is acceptable; install before running SCCM Setup
- **.NET Framework 4.5+**: normally pre-installed on Server 2022
- **WSUS role** (optional, for software update point)
- **Internet access from SCCM VM** during initial setup — SCCM Setup downloads ~1–3 GB of prerequisite files

For **Intune co-management**, you additionally need:
- An Azure AD (Entra ID) tenant
- Microsoft Intune licenses (or Microsoft 365 E3/E5)
- Hybrid Azure AD join configured on the domain
- Co-management enabled in the SCCM console

See `infrastructure/vms/sccm/README.md` for the full step-by-step SCCM guide.
