# Ansible – Windows Post-Configuration

This directory contains Ansible playbooks and inventory for configuring the Windows lab VMs after OS installation. Ansible connects to Windows VMs via **WinRM** (Windows Remote Management).

---

## Prerequisites

### On the Control Machine (where you run Ansible)

```bash
# Install Ansible and WinRM dependencies
pip3 install ansible pywinrm requests requests-ntlm

# Install Windows collections
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.windows

# Verify
ansible --version
ansible-galaxy collection list | grep windows
```

### On Each Windows VM (before running playbooks)

Enable WinRM from an **elevated PowerShell** on each VM:

```powershell
# Basic WinRM setup (allows HTTP + NTLM — appropriate for isolated lab)
winrm quickconfig -y

# Enable NTLM authentication (recommended over Basic for domain environments)
Set-Item WSMan:\localhost\Service\Auth\NTLM -Value $true

# Allow connections from the Ansible control machine (lab subnet)
# This sets the WinRM listener to accept from 10.10.10.0/24
Set-Item WSMan:\localhost\Service\IPv4Filter -Value "10.10.10.*"

# Verify WinRM is listening
winrm enumerate winrm/config/listener
```

For **HTTPS/Kerberos** (more secure, for domain-joined machines after DC is up):
```powershell
# After domain join, Kerberos is the recommended transport
# The Ansible inventory uses ansible_winrm_transport: kerberos
# Kerberos requires the control machine to have a kerberos ticket or
# the ansible_user to be in the domain
```

For a quick lab setup, NTLM over HTTP (port 5985) is sufficient.

---

## Inventory Structure

```
ansible/
├── inventory/
│   └── lab.yml.example   # Template — copy to lab.yml and fill in
└── playbooks/
    ├── dc.yml             # Domain Controller setup
    └── sccm.yml           # SCCM prerequisites
```

The `lab.yml` inventory file is in `.gitignore` because it contains credentials.

Copy and configure:
```bash
cp inventory/lab.yml.example inventory/lab.yml
nano inventory/lab.yml
```

---

## Running Playbooks

Always run the DC playbook first — SCCM depends on the AD domain being available.

```bash
cd /home/user/ProxmoxInfra/ansible

# Test connectivity to all hosts
ansible all -i inventory/lab.yml -m win_ping

# 1. Configure Domain Controller (promotes to AD DC, sets up DNS/DHCP)
ansible-playbook -i inventory/lab.yml playbooks/dc.yml

# 2. Configure SCCM prerequisites (after DC is up and domain exists)
ansible-playbook -i inventory/lab.yml playbooks/sccm.yml

# Run with verbose output for debugging
ansible-playbook -i inventory/lab.yml playbooks/dc.yml -vv

# Run only specific tags
ansible-playbook -i inventory/lab.yml playbooks/dc.yml --tags "rename,network"

# Dry run (check mode)
ansible-playbook -i inventory/lab.yml playbooks/dc.yml --check
```

---

## WinRM Connection Variables

Key variables used in the inventory:

| Variable | Description |
|---|---|
| `ansible_host` | IP address of the VM |
| `ansible_user` | Username for WinRM authentication |
| `ansible_password` | Password (use vault in production) |
| `ansible_connection` | Must be `winrm` |
| `ansible_winrm_transport` | `ntlm` (pre-domain) or `kerberos` (post-domain-join) |
| `ansible_winrm_scheme` | `http` (port 5985) or `https` (port 5986) |
| `ansible_winrm_port` | 5985 for HTTP, 5986 for HTTPS |
| `ansible_winrm_server_cert_validation` | Set to `ignore` for HTTP (irrelevant) or self-signed HTTPS |

---

## Available Playbooks

### dc.yml

**Host group**: `dc`

Configures lab-dc01 as an Active Directory Domain Controller:
1. Renames the computer to `LAB-DC01`
2. Sets static IP `10.10.10.10`
3. Installs Windows features: `AD-Domain-Services`, `DNS`, `DHCP`
4. Promotes to DC for `lab.local`
5. Reboots and waits for AD to come online
6. Configures DHCP scope
7. Creates OUs: Servers, Clients, ServiceAccounts
8. Creates service account `svc-sccm`

### sccm.yml

**Host group**: `sccm`

Configures lab-sccm01 with SCCM prerequisites:
1. Renames to `LAB-SCCM01`
2. Sets static IP `10.10.10.20`
3. Joins the `lab.local` domain
4. Installs required Windows features (IIS, BITS, .NET, etc.)
5. Creates `C:\SCCM_Sources` directory structure
6. Configures Windows Firewall rules for SCCM ports

**Note**: SQL Server and SCCM CB installation must be done manually after this playbook runs. See `infrastructure/vms/sccm/README.md` for instructions.

---

## Using Ansible Vault (Recommended)

For storing passwords securely instead of plaintext in the inventory:

```bash
# Encrypt a string
ansible-vault encrypt_string 'YourPassword123!' --name 'ansible_password'

# Or create an encrypted vars file
ansible-vault create group_vars/all/vault.yml

# Run playbooks with vault password
ansible-playbook -i inventory/lab.yml playbooks/dc.yml --ask-vault-pass
# or: --vault-password-file ~/.vault_pass
```

For a lab environment, plaintext in a gitignored `lab.yml` is acceptable. Never commit credentials to git.
