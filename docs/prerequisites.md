# Prerequisites – ProxmoxInfra Windows Lab

Everything in this list must be completed **manually** before running any automation in this repository. The Terraform and Ansible automation assumes these preconditions are met.

---

## 1. Proxmox VE 8.x Installed

- Install Proxmox VE 8.x on your target machine
- Download ISO: https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso
- The Proxmox web UI should be accessible at `https://<host-ip>:8006`
- Confirm the host is reachable from the machine you will run Terraform on

**Verify**: Open `https://<proxmox-ip>:8006` in a browser and log in as `root`.

---

## 2. Download and Upload Windows Server 2022 Evaluation ISO

1. Download from: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
   - Select "ISO" as download type
   - No product key or license required for evaluation
2. Upload to Proxmox:
   - Proxmox UI → **pve** → **local** → **ISO Images** → **Upload**
   - Or via command line on Proxmox host:
     ```bash
     # From the Proxmox host, or use scp to copy the ISO first
     ls /var/lib/vz/template/iso/
     ```
3. Note the exact filename — you will need it for `terraform.tfvars`

**Expected filename example**: `WinSrv2022_EN-US_eval.iso`

---

## 3. Download and Upload Windows 11 Enterprise Evaluation ISO

1. Download from: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise
   - Select 64-bit ISO
2. Upload to Proxmox local storage (same steps as above)
3. Note the exact filename for `terraform.tfvars`

**Expected filename example**: `Win11_Ent_eval_x64.iso`

---

## 4. Download and Upload VirtIO Drivers ISO

The VirtIO drivers ISO provides paravirtualized storage (SCSI) and network (Ethernet) drivers for Windows VMs on Proxmox/KVM. Without these, Windows will not detect the virtual disk during installation.

1. Download the stable VirtIO ISO:
   ```
   https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
   ```
2. Upload to Proxmox local storage

**Expected filename**: `virtio-win.iso`

---

## 5. Create Proxmox API Token

The `bpg/proxmox` Terraform provider authenticates via an API token, not a username/password.

**Steps in the Proxmox UI:**

1. Log in to Proxmox UI as `root`
2. Go to **Datacenter → Permissions → Users**
3. Click **Add** and create a user: `terraform@pam`, realm `pam`, any password
4. Go to **Datacenter → Permissions → API Tokens**
5. Click **Add**:
   - User: `terraform@pam`
   - Token ID: `lab`
   - Privilege Separation: **uncheck** (for lab simplicity)
6. Click **Add** — a dialog shows the full token value:
   ```
   terraform@pam!lab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
   **Copy this now** — the secret is shown only once.
7. Grant the token permissions:
   - Go to **Datacenter → Permissions → Add → API Token Permission**
   - Path: `/`
   - Token: `terraform@pam!lab`
   - Role: `Administrator`

Store the token in your `.env` file or export as environment variables:
```bash
export PM_API_TOKEN_ID="terraform@pam!lab"
export PM_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## 6. Enable Wake-on-LAN and Note MAC Address

Wake-on-LAN allows the Proxmox host to be powered on remotely by the Raspberry Pi.

1. Enter BIOS/UEFI on the Proxmox host machine
2. Locate the WOL setting — typically under:
   - Power Management → Wake on LAN
   - Advanced → Onboard Devices → Wake on LAN
   - Disable "ErP" / "EuP" mode (these disable WOL)
3. Enable WOL and save settings
4. Boot into Proxmox and note the MAC address of the LAN NIC:
   ```bash
   ip link show
   # Example output:
   # 2: enp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
   #     link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
   ```
5. Record the MAC address — needed for the Raspberry Pi setup

---

## 7. Install Terraform >= 1.6

Install Terraform on the machine where you will run `terraform apply` (your workstation, the Proxmox host, or a CI runner).

```bash
# On Debian/Ubuntu
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Verify
terraform version
# Should show >= 1.6.0
```

Alternatively, download directly from: https://www.terraform.io/downloads

---

## 8. Install Ansible with Windows Collections

Ansible is used for post-boot Windows configuration via WinRM.

```bash
# Install Ansible (Python pip — recommended for latest version)
pip3 install --user ansible pywinrm requests

# Install Windows collections
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.windows

# Verify
ansible --version
ansible-galaxy collection list | grep windows
```

---

## 9. Create ZeroTier Network

1. Create an account at https://my.zerotier.com
2. Click **Create A Network** — a private network is created with a 16-character hex ID
3. Note the **Network ID** (e.g., `a09acf0233abcdef`)
4. Keep the network **private** (requires manual authorization of each joining node)
5. Optionally set the managed route and IP assignment pool (default: 172.22.0.0/16 range)

The Network ID is needed during the Raspberry Pi `setup.sh` script.

See `raspberry-pi/zerotier/README.md` for detailed ZeroTier setup instructions.

---

## 10. Prepare Raspberry Pi

1. **Hardware**: Raspberry Pi 4 (2 GB RAM minimum recommended) with a microSD card (8 GB+) and Ethernet connection to your home LAN
2. **OS**: Flash Raspberry Pi OS Lite 64-bit using Raspberry Pi Imager
   - Enable SSH in the imager advanced settings
   - Set hostname, username/password, WiFi (if needed), and locale
3. **Network**: Connect via Ethernet to your home LAN. Assign a static IP or reserve an IP in your router DHCP (recommended: `192.168.1.200`)
4. **SSH access**: Confirm you can SSH to the Raspi from your workstation:
   ```bash
   ssh pi@192.168.1.200
   ```

The `raspberry-pi/setup.sh` script handles ZeroTier installation, WOL tools, and the WOL API service automatically.

---

## 11. Python 3

Python 3 is required for Ansible (on the control machine) and for the WOL Flask API (on the Raspberry Pi).

```bash
# Check
python3 --version   # Should be 3.8+

# Install if needed (Debian/Ubuntu)
sudo apt install -y python3 python3-pip
```

---

## Checklist Summary

- [ ] Proxmox VE 8.x installed and accessible
- [ ] Windows Server 2022 Evaluation ISO uploaded to Proxmox local storage
- [ ] Windows 11 Enterprise Evaluation ISO uploaded to Proxmox local storage
- [ ] VirtIO drivers ISO uploaded to Proxmox local storage
- [ ] Proxmox API token created and secret saved
- [ ] WOL enabled in BIOS and Proxmox NIC MAC address noted
- [ ] Terraform >= 1.6 installed
- [ ] Ansible installed with `ansible.windows` and `community.windows` collections
- [ ] ZeroTier account created and Network ID noted
- [ ] Raspberry Pi hardware prepared, OS flashed, SSH enabled, static IP set
- [ ] Python 3.8+ available on control machine
