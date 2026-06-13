# lab-linux01 / lab-linux02 – Linux Clients (VMs 110–111)

## Overview

| VM | Hostname | VMID | OS | IP | Toggle |
|---|---|---|---|---|---|
| lab-linux01 | `lab-linux01` | 110 | Ubuntu 22.04 LTS | 10.10.10.60 | `enable_linux_client = true` |
| lab-linux02 | `lab-linux02` | 111 | Rocky Linux 9 | 10.10.10.61 | `enable_linux_client = true` + `linux_client_count = 2` |

These VMs extend the lab with Linux-native workloads: Ansible SSH workflows, monitoring agents, optional Active Directory domain join, and Microsoft Intune Linux MDM enrollment.

Enable via `terraform.tfvars`:

```hcl
# Ubuntu only:
enable_linux_client = true
linux_client_count  = 1

# Ubuntu + Rocky Linux:
enable_linux_client = true
linux_client_count  = 2
ubuntu_iso          = "ubuntu-22.04.4-live-server-amd64.iso"
rocky_iso           = "Rocky-9.4-x86_64-dvd.iso"
```

---

## Purpose

These VMs cover scenarios that Windows-only labs cannot test:

- **Ansible SSH workflows** — Linux is the natural Ansible target; test idempotency, role development, and inventory management without WinRM complexity
- **Cross-platform monitoring** — deploy Prometheus `node_exporter` or Zabbix agents and observe metrics alongside Windows hosts
- **Active Directory join** — test SSSD/realm integration so domain users can authenticate on Linux with `LAB\username` or `username@lab.local`
- **Intune Linux MDM** — Microsoft Intune supports Ubuntu 22.04 and RHEL 9 natively; test compliance policies and configuration profiles
- **RHEL-compatible testing** — Rocky Linux 9 is binary-compatible with RHEL 9; test enterprise Linux package management, SELinux policies, and systemd unit authoring

---

## OS Choices

### Ubuntu 22.04 LTS (lab-linux01)

- Widest Ansible module support (`apt`, `snap`, `ufw`)
- First-class Intune Linux MDM support
- Long-Term Support until April 2027 (standard) / April 2032 (ESM)
- Download: https://ubuntu.com/download/server

### Rocky Linux 9 (lab-linux02)

- RHEL 9 binary-compatible rebuild maintained by the Rocky Enterprise Software Foundation
- Uses `dnf`, SELinux enforcing by default, `firewalld`
- Represents the enterprise Linux standard in most corporate environments
- Download: https://rockylinux.org/download

---

## ISO Downloads and Upload

Download the ISOs from the links above and upload them to Proxmox:

**Proxmox UI → Datacenter → pve → local → ISO Images → Upload**

Or from the Proxmox host shell:

```bash
cd /var/lib/vz/template/iso

# Ubuntu 22.04 LTS
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso

# Rocky Linux 9
wget https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.4-x86_64-dvd.iso
```

---

## Installation

### Ubuntu 22.04 LTS (lab-linux01)

1. Start VM 110: `qm start 110`
2. Open the console (Proxmox UI → VM 110 → Console)
3. Choose **Install Ubuntu Server**
4. Language / keyboard: your preference
5. Network: accept DHCP (static IP configured post-install)
6. Storage: use the entire 40 GB disk, LVM layout
7. Profile: hostname = `lab-linux01`, username = `labadmin`, set a password
8. Enable **Install OpenSSH server** — required for Ansible
9. No additional snaps needed — skip
10. Reboot when prompted; remove the ISO from Proxmox hardware before the VM restarts

**Add desktop environment (optional):**

```bash
sudo apt update && sudo apt install ubuntu-desktop -y
```

### Rocky Linux 9 (lab-linux02)

1. Start VM 111: `qm start 111`
2. Open the console
3. Choose **Install Rocky Linux 9**
4. Language / keyboard: your preference
5. Installation destination: select the 40 GB disk, automatic partitioning
6. Network & Hostname: set hostname to `lab-linux02`; configure network (DHCP initially)
7. Software selection: **Server with GUI** (recommended) or **Minimal Install** + add desktop later
8. Root password + create user: `labadmin`
9. Begin installation; reboot when complete

**Add GNOME desktop after minimal install (optional):**

```bash
sudo dnf groupinstall "Server with GUI" -y
sudo systemctl set-default graphical.target
sudo reboot
```

---

## Static IP Configuration

### Ubuntu 22.04 (Netplan)

Edit `/etc/netplan/00-installer-config.yaml`:

```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 10.10.10.60/24
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        addresses:
          - 10.10.10.10    # lab-dc01 DNS
          - 1.1.1.1
```

Apply: `sudo netplan apply`

### Rocky Linux 9 (NetworkManager / nmcli)

```bash
sudo nmcli con mod ens18 \
  ipv4.method manual \
  ipv4.addresses 10.10.10.61/24 \
  ipv4.gateway 10.10.10.1 \
  ipv4.dns "10.10.10.10,1.1.1.1"
sudo nmcli con up ens18
```

---

## SSH Setup for Ansible

Ensure `openssh-server` is installed and running on both VMs.

### Ubuntu

```bash
sudo systemctl enable --now ssh
```

### Rocky Linux

```bash
sudo dnf install -y openssh-server
sudo systemctl enable --now sshd
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

### Copy Ansible SSH Key

From the Ansible control machine (workstation or Proxmox host):

```bash
ssh-keygen -t ed25519 -C "ansible@lab" -f ~/.ssh/ansible_lab
ssh-copy-id -i ~/.ssh/ansible_lab.pub labadmin@10.10.10.60
ssh-copy-id -i ~/.ssh/ansible_lab.pub labadmin@10.10.10.61
```

### Ansible Inventory Entry

Add to `ansible/inventory/lab.yml`:

```yaml
clients_linux:
  hosts:
    lab-linux01:
      ansible_host: 10.10.10.60
      ansible_user: labadmin
      ansible_ssh_private_key_file: ~/.ssh/ansible_lab
      ansible_become: true
    lab-linux02:
      ansible_host: 10.10.10.61
      ansible_user: labadmin
      ansible_ssh_private_key_file: ~/.ssh/ansible_lab
      ansible_become: true
```

### Test Connectivity

```bash
ansible -i ansible/inventory/lab.yml clients_linux -m ping
```

Expected output:

```
lab-linux01 | SUCCESS => { "ping": "pong" }
lab-linux02 | SUCCESS => { "ping": "pong" }
```

---

## Optional: Active Directory Domain Join (SSSD / realm)

Joining Linux VMs to `lab.local` allows domain users to authenticate with their AD credentials.

### Install Prerequisites

**Ubuntu:**

```bash
sudo apt update
sudo apt install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli \
                    samba-common-bin packagekit
```

**Rocky Linux:**

```bash
sudo dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli \
                    samba-common-tools krb5-workstation
```

### Discover and Join the Domain

```bash
# Discover lab.local (requires DNS pointing to 10.10.10.10)
realm discover lab.local

# Join the domain (prompts for Administrator password)
sudo realm join -U Administrator lab.local
```

### Verify Join

```bash
realm list
id Administrator@lab.local
```

### Enable Home Directory Creation

```bash
sudo pam-auth-update --enable mkhomedir      # Ubuntu
sudo authselect select sssd with-mkhomedir   # Rocky Linux
```

### Login with Domain Account

```bash
# SSH in as a domain user
ssh 'LAB\jsmith'@10.10.10.60
# or
ssh jsmith@lab.local@10.10.10.60
```

### Grant sudo to Domain Group

```bash
sudo nano /etc/sudoers.d/lab-admins
# Add:
%LAB\\Domain\ Admins ALL=(ALL) ALL
```

---

## Monitoring Agent: Prometheus node_exporter

Installing `node_exporter` on Linux VMs enables hardware and OS metrics collection if a Prometheus server is deployed in the lab.

### Install on Ubuntu

```bash
# Download latest node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
tar xzf node_exporter-1.8.1.linux-amd64.tar.gz
sudo cp node_exporter-1.8.1.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -r -s /sbin/nologin node_exporter
```

Create `/etc/systemd/system/node_exporter.service`:

```ini
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

Metrics available at: `http://10.10.10.60:9100/metrics`

### Install on Rocky Linux

Same binary steps above, plus open the firewall:

```bash
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --reload
```

---

## Microsoft Intune Linux Enrollment

Microsoft Intune supports enrollment of Ubuntu 22.04 LTS and RHEL 9 (and thus Rocky Linux 9) devices.

### Requirements

- Microsoft Intune subscription (or Microsoft 365 E3/E5)
- Azure AD tenant connected to Entra (Hybrid or cloud-only)
- The Intune Company Portal app installed on the Linux VM

### Enroll Ubuntu 22.04

```bash
# Add Microsoft package repository
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/ubuntu/22.04/prod jammy main"
sudo apt update
sudo apt install intune-portal -y

# Launch from the application menu, or:
intune-portal
```

Follow the wizard: sign in with the user's Azure AD / Entra ID credentials, then authorize the device in the Intune admin center at https://intune.microsoft.com.

### Enroll Rocky Linux 9

```bash
# Add Microsoft package repository for RHEL 9
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/microsoft-rhel9.0-prod
sudo dnf install intune-portal -y
intune-portal
```

Once enrolled, compliance policies and configuration profiles assigned to Linux in the Intune portal will apply to the VM.

---

## Configuration Manager (SCCM) — Linux Note

Microsoft removed native Linux client support from Configuration Manager (Current Branch) in version 2107 (released 2021). SCCM **cannot** manage these Linux VMs directly.

For Linux management use:

- **Ansible** (SSH-based, this lab's primary Linux automation tool)
- **Microsoft Intune** (MDM for Ubuntu 22.04 / RHEL 9)
- **Puppet / Chef / Salt** (if extending the lab to configuration management tools)

---

## Testing Scenarios

| Scenario | Description | VMs Involved |
|---|---|---|
| AD join verification | Test SSSD realm join; log in with domain credentials | lab-linux01/02 + lab-dc01 |
| DNS failover | Point Linux VMs to lab-dc02 as secondary DNS; shut down dc01 | linux + dc01/dc02 |
| Cross-platform monitoring | Deploy node_exporter; scrape with Prometheus | linux01/02 + optional monitoring VM |
| Ansible idempotency | Run playbooks twice; verify no changes on second run | linux01/02 |
| Intune Linux MDM | Enroll both VMs; apply compliance policy; check status | linux01/02 + AAD/Intune |
| Package management | Test apt vs dnf automation via Ansible | linux01 (apt) vs linux02 (dnf) |
| SELinux policy testing | Test SELinux enforcing scenarios | lab-linux02 (Rocky) |
| SSH key rotation | Rotate Ansible SSH keys via playbook | linux01/02 |

---

## Relevant Files

| Path | Purpose |
|---|---|
| `infrastructure/proxmox/terraform/main.tf` | VM 110 (`linux01`) and VM 111 (`linux02`) resources |
| `infrastructure/proxmox/terraform/variables.tf` | `enable_linux_client`, `linux_client_count`, `ubuntu_iso`, `rocky_iso` |
| `infrastructure/proxmox/terraform/terraform.tfvars.example` | Example values |
| `ansible/inventory/lab.yml.example` | Add `clients_linux` group here |
