# CLAUDE.md — ProxmoxInfra

This file is a guide for Claude Code running **directly on the Proxmox machine** (or a connected workstation with network access to Proxmox). It explains what this repository does, how to set it up, and the exact commands to run in order.

---

## Overview

This repository automates the provisioning and configuration of a Windows lab environment on a Proxmox hypervisor. The lab consists of:

- **Domain Controller (DC)** — Windows Server 2022, Active Directory, DNS, DHCP
- **SCCM Server** — Windows Server 2022, SQL Server, System Center Configuration Manager Current Branch
- **Windows 11 Client** — Domain-joined test client for SCCM/Intune testing
- **Raspberry Pi** — Always-on gateway providing ZeroTier VPN access and Wake-on-LAN capability

Automation layers:
- **Terraform** (`bpg/proxmox` provider) — Creates Proxmox VMs
- **Ansible** (with WinRM) — Configures Windows VMs post-install
- **PowerShell scripts** — AD DS promotion, SCCM prerequisites, etc.
- **Bash scripts** — Raspberry Pi setup, WOL packet sender

---

## Prerequisites Checklist

Before running any automation, verify:

- [ ] **Proxmox VE 8.x** installed and accessible at `https://<proxmox-ip>:8006`
- [ ] **Windows Server 2022 Evaluation ISO** uploaded to Proxmox local storage
  - Filename example: `WinSrv2022_Eval.iso`
  - Upload via: Proxmox UI → pve → local → ISO Images → Upload
- [ ] **Windows 11 Enterprise Evaluation ISO** uploaded to Proxmox local storage
  - Filename example: `Win11_Ent_Eval.iso`
- [ ] **VirtIO drivers ISO** uploaded to Proxmox local storage
  - Download: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
  - Filename: `virtio-win.iso`
- [ ] **Proxmox API token** created (see section below)
- [ ] **Terraform >= 1.6** installed on this machine
- [ ] **Ansible** installed with `ansible.windows` and `community.windows` collections
- [ ] **Python 3** available (for helper scripts)
- [ ] **Network bridge `vmbr1`** configured on Proxmox host for internal lab network (10.10.10.0/24)
- [ ] **WOL enabled** in BIOS/UEFI on the Proxmox host
- [ ] **Raspberry Pi** on the same LAN as the Proxmox host
- [ ] **ZeroTier account** created at my.zerotier.com with a private network created

---

## Implementation Order

### Step 1 — Set Up Network Bridge (vmbr1)

On the Proxmox host, create the internal lab bridge if it does not exist:

1. Proxmox UI → pve → System → Network → Create → Linux Bridge
2. Name: `vmbr1`
3. No IP address (internal only, no gateway)
4. Comment: `Lab internal network 10.10.10.0/24`
5. Click Create, then Apply Configuration

Alternatively via shell on the Proxmox host:

```bash
# Edit /etc/network/interfaces and add:
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    comment Lab internal network
```

Then: `ifreload -a`

### Step 2 — Terraform Init and Apply

```bash
cd infrastructure/proxmox/terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox endpoint, API token, ISO filenames

export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

terraform init
terraform plan
terraform apply
```

This creates the three VMs (DC, SCCM, Client) as shells — no OS installed yet. VMs will be ready for OS installation from the attached ISOs.

### Step 3 — Install Windows on Each VM

1. Start each VM from the Proxmox console
2. Boot from the Windows ISO (IDE CD-ROM)
3. Install Windows Server 2022 (Desktop Experience) on DC and SCCM VMs
4. Install Windows 11 Enterprise on the Client VM
5. Install VirtIO drivers from the secondary CD-ROM during setup (load driver for SCSI disk)

### Step 4 — Run Ansible / PowerShell for Windows Configuration

Enable WinRM on each Windows VM first (run in PowerShell as Administrator):

```powershell
# On each Windows VM
winrm quickconfig -y
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
# Or use NTLM (preferred — see ansible/README.md)
```

Configure `ansible/inventory/lab.yml` from the example file, then:

```bash
cd ansible

# DC first — sets up AD domain
ansible-playbook -i inventory/lab.yml playbooks/dc.yml

# SCCM prereqs after DC is running
ansible-playbook -i inventory/lab.yml playbooks/sccm.yml
```

### Step 5 — Raspberry Pi Setup

```bash
# On the Raspberry Pi
git clone <this-repo> ~/ProxmoxInfra
cd ~/ProxmoxInfra/raspberry-pi
chmod +x setup.sh
sudo ./setup.sh
```

---

## Configuring terraform.tfvars

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in:

```hcl
proxmox_endpoint     = "https://192.168.1.100:8006/"   # Your Proxmox IP
proxmox_api_token    = "terraform@pam!lab=xxxxxxxx-..."  # See below
proxmox_node         = "pve"                            # Your node name
windows_server_iso   = "WinSrv2022_Eval.iso"            # Exact ISO filename in local storage
windows_11_iso       = "Win11_Ent_Eval.iso"
virtio_iso           = "virtio-win.iso"
admin_password       = "YourSecureP@ssword1"            # Local admin
safe_mode_password   = "YourSafeModePwd1!"              # AD DSRM password
```

Never commit `terraform.tfvars` — it is in `.gitignore`.

---

## How to Get the Proxmox API Token

1. Log into Proxmox UI as `root`
2. Navigate to: Datacenter → Permissions → API Tokens
3. Click **Add**
   - User: `terraform@pam` (create this user first under Users if needed)
   - Token ID: `lab`
   - Privilege Separation: uncheck (for simplicity in lab)
4. Copy the displayed secret — it is shown only once
5. Grant permissions: Datacenter → Permissions → Add → API Token Permission
   - Path: `/`
   - Token: `terraform@pam!lab`
   - Role: `PVEVMAdmin` (or `Administrator` for full access)

The full token string format is: `terraform@pam!lab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

---

## Environment Variables

Set these before running Terraform:

```bash
export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_HOST="192.168.1.100"
```

Or store them in a `.env` file (which is gitignored):

```bash
# .env
PM_API_TOKEN_ID=terraform@pam!lab
PM_API_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
PROXMOX_HOST=192.168.1.100
```

Source with: `source .env`

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
cp ansible/inventory/lab.yml.example ansible/inventory/lab.yml
# Edit lab.yml with correct IPs and credentials

# 5. Run DC playbook
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/dc.yml

# 6. Run SCCM prereqs playbook
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/sccm.yml

# 7. Set up Raspberry Pi
# SSH into Raspi and run setup.sh
```

---

## Windows Licensing Notes

- This lab uses **evaluation ISOs** which are free for 180 days (extendable with `slmgr /rearm`)
- Download Windows Server 2022 Evaluation: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- Download Windows 11 Enterprise Evaluation: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise
- No product key is required for evaluation installs — press "I don't have a product key" during setup
- For production use, valid licenses are required

---

## ZeroTier Network ID

1. Create an account at https://my.zerotier.com
2. Create a new private network
3. Note the **16-character Network ID** (e.g., `a09acf0233abcdef`)
4. During Raspberry Pi setup, you will be prompted to enter this ID
5. After the Raspi joins, authorize it in ZeroTier Central under the Members tab
6. Assign a managed IP to the Raspi (e.g., `172.22.0.1`)
7. Install ZeroTier on your workstation and join the same network for remote access

---

## Wake-on-LAN Setup Instructions

1. **In BIOS/UEFI** on the Proxmox host:
   - Enable "Wake on LAN" or "Power On by PCI-E" in the power management section
   - Save and reboot

2. **Find the MAC address** of the Proxmox host's NIC:
   ```bash
   # On Proxmox host
   ip link show
   # Note the MAC of the interface connected to your LAN (e.g., enp3s0)
   ```

3. **On the Raspberry Pi**, the `setup.sh` script will ask for this MAC and save it to `/etc/wol/proxmox.conf`

4. **Test WOL**:
   ```bash
   # On Raspberry Pi
   /home/pi/ProxmoxInfra/raspberry-pi/wake-on-lan/wol.sh
   ```

---

## SCCM Prerequisites Notes

SCCM requires several components that must be downloaded at install time:

- **Windows ADK** (Assessment and Deployment Kit) — must be downloaded from Microsoft during SCCM setup or pre-staged
- **WinPE add-on for ADK** — required for OSD (OS Deployment)
- **SQL Server** — must be installed before SCCM; SQL Server 2019 or 2022 evaluation is recommended
- **SCCM Current Branch Evaluation** — download from https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager
- An **internet connection** from the SCCM VM is needed during initial setup for downloading prerequisite files
- Estimated download during SCCM setup: 1–3 GB

See `infrastructure/vms/sccm/README.md` for the full step-by-step guide.
