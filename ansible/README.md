# Ansible – Windows and Linux Post-Configuration

This directory contains Ansible playbooks, roles and inventory for configuring all lab VMs after OS installation. Ansible connects to Windows VMs via **WinRM** (Windows Remote Management) and to Linux VMs via **SSH**.

---

## Prerequisites

### On the Control Machine (where you run Ansible)

```bash
# Install Ansible and WinRM dependencies
pip3 install ansible pywinrm requests requests-ntlm

# Install required Galaxy collections (see requirements.yml)
ansible-galaxy collection install -r requirements.yml

# Upgrade existing collections to the latest compatible version
ansible-galaxy collection install -r requirements.yml --upgrade

# Verify
ansible --version
ansible-galaxy collection list | grep -E "windows|general"
```

### On Each Windows VM (before running playbooks)

Enable WinRM from an **elevated PowerShell** on each VM:

```powershell
# Basic WinRM setup (allows HTTP + NTLM — appropriate for isolated lab)
winrm quickconfig -y

# Enable NTLM authentication (recommended over Basic for domain environments)
Set-Item WSMan:\localhost\Service\Auth\NTLM -Value $true

# Allow connections from the Ansible control machine (lab subnet)
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

### On Each Linux VM (before running playbooks)

Linux VMs need Python 3 and SSH access. For Ubuntu/Rocky cloud images, Python is pre-installed. Ensure SSH is enabled and the `ansible_user` is configured in `lab.yml`.

---

## Directory Structure

```
ansible/
├── ansible.cfg                          # Ansible configuration (see below)
├── requirements.yml                     # Galaxy collection requirements
├── inventory/
│   ├── lab.yml.example                  # Inventory template — copy to lab.yml
│   ├── lab.yml                          # Your inventory (gitignored)
│   └── group_vars/
│       ├── all/
│       │   ├── main.yml                 # Shared plain variables (non-secret)
│       │   ├── vault.yml.example        # Vault template — copy to vault.yml
│       │   └── vault.yml                # Encrypted secrets (gitignored)
│       ├── windows.yml                  # WinRM defaults for Windows hosts
│       └── linux.yml                    # SSH defaults for Linux hosts
├── playbooks/
│   ├── site.yml                         # Master playbook — runs everything
│   ├── dc.yml                           # Primary Domain Controller (lab-dc01)
│   ├── dc02.yml                         # Secondary DC (lab-dc02, optional)
│   ├── sccm.yml                         # SCCM prerequisites (lab-sccm01)
│   ├── ca.yml                           # Enterprise Root CA (lab-ca01, optional)
│   ├── pki-root.yml                     # Offline Standalone Root CA (lab-rootca01, optional)
│   ├── pki-sub.yml                      # Enterprise Subordinate/Issuing CA (lab-subca01, optional)
│   ├── aadconnect.yml                   # Entra Connect (lab-aadc01, optional)
│   ├── cloudsync.yml                    # Entra Cloud Sync (lab-cloudsync01, optional)
│   ├── client-windows.yml               # Windows 11 clients (clients_win)
│   └── client-linux.yml                 # Linux clients (clients_linux, optional)
└── roles/
    ├── windows_base/                    # Rename + static IP for Windows VMs
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── defaults/main.yml
    ├── domain_join/                     # Idempotent AD domain join for Windows
    │   ├── tasks/main.yml
    │   └── defaults/main.yml
    └── linux_base/                      # Base setup for Linux VMs
        ├── tasks/main.yml
        ├── handlers/main.yml
        └── defaults/main.yml
```

---

## ansible.cfg

The `ansible.cfg` file in this directory configures Ansible behaviour for the lab:

| Setting | Value | Notes |
|---|---|---|
| `inventory` | `inventory/lab.yml` | Default inventory; override with `-i` |
| `remote_user` | `Administrator` | Overridden per host in inventory |
| `host_key_checking` | `False` | Avoids SSH key prompts for new VMs |
| `timeout` | `60` | Connection timeout in seconds |
| `stdout_callback` | `yaml` | Human-friendly output format |
| `vault_password_file` | `~/.vault_pass` | Optional; see Vault section below |
| `retry_files_enabled` | `False` | No `.retry` files on failure |
| `pipelining` | `True` | Fewer SSH round-trips for Linux hosts |

---

## requirements.yml

Install all required collections before running any playbook:

```bash
ansible-galaxy collection install -r requirements.yml
```

Collections installed:

| Collection | Minimum Version | Purpose |
|---|---|---|
| `ansible.windows` | >=2.0.0 | Core Windows modules (win_shell, win_feature, etc.) |
| `community.windows` | >=2.0.0 | Extended Windows modules |
| `community.general` | >=8.0.0 | Cross-platform modules (timezone, etc.) |

---

## Inventory Structure

The `lab.yml` inventory file is in `.gitignore` because it contains credentials. Copy and configure it:

```bash
cp inventory/lab.yml.example inventory/lab.yml
nano inventory/lab.yml
```

### Host Groups

| Group | VMs | Connection |
|---|---|---|
| `windows` | All Windows VMs (parent group) | WinRM |
| `dc` | lab-dc01 (10.10.10.10) | WinRM |
| `dc02` | lab-dc02 (10.10.10.11) — optional | WinRM |
| `sccm` | lab-sccm01 (10.10.10.20) | WinRM |
| `ca` | lab-ca01 (10.10.10.30) — optional | WinRM |
| `rootca` | lab-rootca01 (10.10.10.31) — optional (workgroup) | WinRM |
| `subca` | lab-subca01 (10.10.10.32) — optional | WinRM |
| `aadconnect` | lab-aadc01 (10.10.10.40) — optional | WinRM |
| `cloudsync` | lab-cloudsync01 (10.10.10.41) — optional | WinRM |
| `clients_win` | lab-client01 (10.10.10.50), lab-client02 — optional | WinRM |
| `linux` | All Linux VMs (parent group) | SSH |
| `clients_linux` | lab-linux01 (10.10.10.60), lab-linux02 — optional | SSH |
| `opnsense` | lab-opnsense01 (10.10.10.1) — optional | SSH |

### group_vars Structure

```
group_vars/
├── all/
│   ├── main.yml    — Plain variables: lab_domain, lab_gateway, lab_dc_ip,
│   │                 sccm_site_code, and vault-backed aliases
│   ├── vault.yml   — Encrypted secrets (see Ansible Vault section)
│   └── vault.yml.example  — Template showing all required secret keys
├── windows.yml     — WinRM connection defaults (port 5985, ntlm, http)
└── linux.yml       — SSH connection defaults (port 22, StrictHostKeyChecking=no)
```

**Key variables in `group_vars/all/main.yml`:**

| Variable | Value | Description |
|---|---|---|
| `lab_domain` | `lab.local` | AD domain DNS name |
| `lab_netbios` | `LAB` | NetBIOS domain name |
| `lab_gateway` | `10.10.10.1` | Default gateway |
| `lab_dns_primary` | `10.10.10.10` | Primary DNS (DC01) |
| `lab_dns_secondary` | `10.10.10.11` | Secondary DNS (DC02) |
| `lab_ntp_server` | `10.10.10.10` | NTP source (DC acts as NTP) |
| `admin_password` | `{{ vault_admin_password }}` | Resolved from vault |
| `domain_join_password` | `{{ vault_domain_join_password }}` | Resolved from vault |
| `entra_upn_suffix` | `{{ vault_entra_upn_suffix }}` | Resolved from vault |

---

## Ansible Vault

Passwords and secrets are stored in `inventory/group_vars/all/vault.yml`, which is encrypted with `ansible-vault` and excluded from git.

### Initial Setup

```bash
# 1. Copy the template
cp inventory/group_vars/all/vault.yml.example \
   inventory/group_vars/all/vault.yml

# 2. Edit with your actual passwords (CHANGE ALL DEFAULTS before encrypting)
nano inventory/group_vars/all/vault.yml

# 3. Encrypt the file
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

### Editing an Encrypted Vault

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
```

### Vault Variables

| Variable | Description |
|---|---|
| `vault_admin_password` | Local Administrator password on all lab VMs |
| `vault_safe_mode_password` | AD DS Safe Mode (DSRM) recovery password |
| `vault_svc_sccm_password` | `svc-sccm` service account password |
| `vault_domain_join_user` | Account for domain join (e.g. `LAB\Administrator`) |
| `vault_domain_join_password` | Password for the domain join account |
| `vault_entra_upn_suffix` | Routable UPN suffix in Azure AD (e.g. `labdemo.onmicrosoft.com`) |

### Running Playbooks with the Vault

**Option A — password file (recommended, avoids prompts on every run):**

```bash
# Create the password file once
echo 'your_vault_password' > ~/.vault_pass
chmod 600 ~/.vault_pass

# Run playbooks normally — ansible.cfg already points to ~/.vault_pass
ansible-playbook -i inventory/lab.yml playbooks/dc.yml
```

**Option B — interactive prompt:**

```bash
ansible-playbook -i inventory/lab.yml playbooks/dc.yml --ask-vault-pass
```

---

## Running Playbooks

### Quick Start

```bash
cd /home/user/ProxmoxInfra/ansible

# Test connectivity to all active hosts
ansible all -i inventory/lab.yml -m win_ping --limit windows
ansible all -i inventory/lab.yml -m ping --limit linux

# Run the full lab in one command (skips groups with no hosts)
ansible-playbook -i inventory/lab.yml playbooks/site.yml

# Or run only what you need
ansible-playbook -i inventory/lab.yml playbooks/dc.yml
ansible-playbook -i inventory/lab.yml playbooks/sccm.yml
```

### Tag Reference

All playbooks share a consistent tag scheme:

| Tag | Action |
|---|---|
| `always` | Connectivity check — always runs |
| `info` | Display current state (hostname, domain, etc.) |
| `rename` | Rename the computer + reboot |
| `network` | Configure static IP / DNS |
| `features` | Install Windows features |
| `join` | Domain join + reboot |
| `promote` | DC promotion (dc.yml, dc02.yml) |
| `configure` | Post-join configuration |
| `validate` | Verify the configuration is correct |
| `packages` | Install/upgrade Linux packages (client-linux.yml) |
| `domain_join` | Optional AD join for Linux clients (client-linux.yml) |
| `monitoring` | Install node_exporter (client-linux.yml) |

```bash
# Run only the rename and network steps on all Windows VMs
ansible-playbook -i inventory/lab.yml playbooks/site.yml --tags rename,network

# Validate all hosts without making changes
ansible-playbook -i inventory/lab.yml playbooks/site.yml --tags validate

# Dry run — show what would change without making changes
ansible-playbook -i inventory/lab.yml playbooks/site.yml --check

# Verbose output for debugging
ansible-playbook -i inventory/lab.yml playbooks/dc.yml -vv
```

---

## WinRM Connection Variables

Key variables in the inventory (defaults set in `group_vars/windows.yml`):

| Variable | Default | Description |
|---|---|---|
| `ansible_host` | — | IP address of the VM |
| `ansible_user` | `Administrator` | Username for WinRM authentication |
| `ansible_password` | `{{ admin_password }}` | Password from vault |
| `ansible_connection` | `winrm` | Connection type |
| `ansible_winrm_transport` | `ntlm` | `ntlm` pre-domain, `kerberos` post-domain-join |
| `ansible_winrm_scheme` | `http` | `http` (port 5985) or `https` (port 5986) |
| `ansible_winrm_port` | `5985` | WinRM port |
| `ansible_winrm_server_cert_validation` | `ignore` | For HTTP or self-signed HTTPS |

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

### dc02.yml

**Host group**: `dc02` — optional (Terraform toggle: `enable_dc02 = true`)

Configures lab-dc02 as an additional Domain Controller:
1. Renames to `LAB-DC02`
2. Sets static IP `10.10.10.11`, DNS pointing at DC01
3. Installs AD DS, DNS and RSAT tools
4. Promotes as additional DC (skips if already a DC)
5. Validates replication with `repadmin /replsummary` and `dcdiag`

### sccm.yml

**Host group**: `sccm`

Configures lab-sccm01 with SCCM prerequisites:
1. Renames to `LAB-SCCM01`
2. Sets static IP `10.10.10.20`
3. Joins the `lab.local` domain
4. Installs required Windows features (IIS, BITS, .NET, etc.)
5. Creates `C:\SCCM_Sources` directory structure
6. Configures Windows Firewall rules for SCCM ports

**Note**: SQL Server and SCCM CB installation must be done manually. See `infrastructure/vms/sccm/README.md`.

### ca.yml

**Host group**: `ca` — optional (Terraform toggle: `enable_ca = true`)

Configures lab-ca01 as an Enterprise Root CA for lab.local:
1. Renames to `LAB-CA01`
2. Sets static IP `10.10.10.30`
3. Joins the domain
4. Installs and configures AD CS (Enterprise Root CA, 4096-bit, SHA256, 10 years)
5. Configures AD CS Web Enrollment (`/certsrv`)

### pki-root.yml

**Host group**: `rootca` — optional (Terraform toggle: `enable_twotier_pki = true`, VM 112)

Configures lab-rootca01 as the **offline standalone Root CA** of a two-tier PKI. This host is a **workgroup** machine — it is **not** domain-joined and is reached via the local Administrator account.

1. Renames to `LAB-ROOTCA01` (stays in WORKGROUP)
2. Sets a temporary static IP `10.10.10.31` (only for the setup / cert-transfer window — an offline root normally has no network)
3. Installs `AD-Certificate` + `RSAT-ADCS` + `RSAT-ADCS-Mgmt`
4. Runs `setup-rootca.ps1` (`-RootCaName {{ pki_root_ca_name }}` `-ValidityYears {{ pki_root_validity_years }}`) to install a `StandaloneRootCA` and export the root cert + CRL to `C:\PKI_Export\`
5. Fetches the exported root `.crt`/`.crl` back to the control node under `/tmp/pki_export/`
6. Validates with `certutil -getreg CA\CommonName` / `certutil -CAInfo`

**Special note**: The root CA exists only to sign the sub-CA's certificate request. After it has issued the sub-CA certificate, **power the VM off and keep it offline** — its private key never leaves the VM. Tags: `always`, `info`, `rename`, `network`, `features`, `install`, `fetch`, `validate`.

### pki-sub.yml

**Host group**: `subca` — optional (Terraform toggle: `enable_twotier_pki = true`, VM 113)

Configures lab-subca01 as the domain-joined **Enterprise Subordinate / Issuing CA** of the two-tier PKI.

1. Renames to `LAB-SUBCA01`
2. Sets static IP `10.10.10.32`
3. Joins the `lab.local` domain (OU=Servers)
4. Installs `Adcs-Cert-Authority` + `Adcs-Web-Enrollment` + `RSAT-ADCS-Mgmt`
5. Runs `setup-subca.ps1` (`-SubCaName {{ pki_sub_ca_name }}`) to install an `EnterpriseSubordinateCA`
6. Validates with `certutil -CAInfo`

**Special note — offline-root cert exchange**: Because the parent root is offline, `Install-AdcsCertificationAuthority` produces a certificate **request** (`*.req`) at `C:\` and CertSvc will not start until it is signed. The playbook prints the full manual workflow:
1. Copy `C:\*.req` from the sub-CA to the offline root.
2. On the root: `certreq -submit <file>.req`, then `certutil -resubmit <RequestId>`, and retrieve the issued cert.
3. Copy the issued `.cer` + the root `.crt`/`.crl` back to the sub-CA.
4. On the sub-CA: `certutil -installCert <issued>.cer`, then `Start-Service certsvc`.
5. Publish the root into AD: `certutil -dspublish -f root.crt RootCA` and `certutil -dspublish -f root.crl`.

Re-run with `--tags validate` once CertSvc is running. Tags: `always`, `info`, `rename`, `network`, `join`, `features`, `install`, `validate`.

### aadconnect.yml

**Host group**: `aadconnect` — optional (Terraform toggle: `enable_aadconnect = true`)

Configures lab-aadc01 for hybrid Azure AD Join:

**Phase 1 (automated)**:
1. Renames to `LAB-AADC01`
2. Sets static IP `10.10.10.40`
3. Installs RSAT-AD-PowerShell
4. Domain-joins to lab.local
5. Adds routable UPN suffix to the AD forest
6. Downloads `AzureADConnect.msi` to `C:\Install\`
7. Launches the installer

**Phase 2 (interactive)**:
- Complete the wizard with Custom install, Password Hash Sync, Seamless SSO, Hybrid AADJ
- Requires a Global Administrator account with MFA

### cloudsync.yml

**Host group**: `cloudsync` — optional (Terraform toggle: `enable_cloudsync = true`, VM 109)

Configures lab-cloudsync01 as a domain-joined member running the Microsoft **Entra Cloud Sync** provisioning agent (the lightweight, cloud-managed alternative to the full Entra Connect sync engine). Internet access is required.

**Phase 1 (automated)**:
1. Renames to `LAB-CLOUDSYNC01`
2. Sets static IP `10.10.10.41`
3. Installs RSAT-AD-PowerShell
4. Domain-joins to lab.local (OU=Servers)
5. Verifies internet connectivity to `login.microsoftonline.com:443` (fails fast with pfSense/OPNsense NAT guidance)
6. Downloads the provisioning agent (`https://aka.ms/EntraProvisioningAgent`) to `C:\Install\AADConnectProvisioningAgentSetup.exe`
7. Silently installs the agent (`/quiet`, guarded by service/install-path check)

**Phase 2 (interactive — CLOUD-SIDE)**:
- Cloud Sync configuration lives in the cloud, not on this server. After the agent is installed:
  - Register the agent (it prompts for a Global Admin during install, or register unattended with the `AADCloudSyncTools` PowerShell module: `Install-Module AADCloudSyncTools`; `Connect-AADCloudSyncTools`; `Add-AADCloudSyncToolsServiceAccount`)
  - In the Microsoft Entra admin center (Identity → Hybrid management → Microsoft Entra Connect → Cloud sync), verify the agent is healthy, create a configuration mapping the AD OU(s) to Entra, then enable and start provisioning.

See `infrastructure/entra-cloudsync/README.md` for the full guide. Tags: `always`, `info`, `rename`, `network`, `features`, `join`, `configure`.

### client-windows.yml

**Host group**: `clients_win`

Configures Windows 11 Enterprise client VMs:
1. Renames each client to its expected name (LAB-CLIENT01, etc.)
2. Configures DHCP with DNS pointing at the DC
3. Domain-joins to lab.local (placed in `OU=Clients`)
4. Enables Remote Desktop

**SCCM client push**: Initiated from the SCCM console — see the `always`-tagged debug task in the playbook.

### client-linux.yml

**Host group**: `clients_linux` — optional (Terraform toggle: `enable_linux_client = true`)

Configures Ubuntu 22.04 and Rocky Linux 9 client VMs:
1. Updates all packages
2. Installs common utilities (git, curl, wget, vim, chrony, etc.)
3. Sets hostname from inventory name
4. Configures chrony NTP pointing at the lab DC
5. Sets timezone to Europe/Berlin
6. Hardens SSH (PermitRootLogin no, MaxAuthTries 3; PasswordAuthentication yes for lab convenience)
7. **Optional**: Joins lab.local via realm/SSSD (tag: `domain_join`, skipped by default)
8. **Optional**: Installs node_exporter for Prometheus scraping (tag: `monitoring`)

```bash
# Run without AD join (default)
ansible-playbook -i inventory/lab.yml playbooks/client-linux.yml

# Run only the AD domain join
ansible-playbook -i inventory/lab.yml playbooks/client-linux.yml --tags domain_join
```

### site.yml

**Master playbook** — imports all playbooks in dependency order. Host groups with no active hosts are silently skipped.

```bash
ansible-playbook -i inventory/lab.yml playbooks/site.yml
```

---

## Reusable Roles

### windows_base

Covers the first two setup steps for any Windows Server VM: rename and static IP configuration.

```yaml
# In your playbook:
- name: Base setup for a new Windows VM
  hosts: mygroup
  gather_facts: false
  vars:
    target_hostname: LAB-MYVM01
    target_ip: 10.10.10.99
    target_dns: 10.10.10.10      # optional, defaults to lab_dns_primary
    target_prefix: 24            # optional, defaults to 24
  roles:
    - windows_base
```

The role:
1. Reads the current computer name via `win_shell`
2. Calls `win_hostname` only if the name differs (idempotent)
3. Triggers the `reboot windows host` handler if a rename happened
4. Waits for WinRM to return after reboot
5. Configures a static IP (only if `target_ip` is non-empty and the IP differs)

**defaults/main.yml variables**:

| Variable | Default | Description |
|---|---|---|
| `target_hostname` | `CHANGEME` | Must be overridden |
| `target_ip` | `""` | Empty = skip IP config |
| `target_dns` | `{{ lab_dns_primary }}` | DNS server |
| `target_prefix` | `24` | Subnet prefix length |

### domain_join

Idempotent domain join for any Windows VM. Skips the join if the host is already a member of `lab.local`.

```yaml
# In your playbook:
- name: Join lab.local
  hosts: mygroup
  gather_facts: false
  vars:
    domain_ou_path: "OU=Servers,DC=lab,DC=local"  # optional
  roles:
    - domain_join
```

The role uses `domain_join_user` and `domain_join_password` from `group_vars/all` (vault-backed). The `domain_ou_path` variable is optional — if omitted, the computer lands in the default `CN=Computers` container.

### linux_base

Base setup for any Linux VM. Detects OS family automatically.

```yaml
# In your playbook:
- name: Linux base setup
  hosts: clients_linux
  gather_facts: true
  become: true
  vars:
    ntp_server: 10.10.10.10   # optional, defaults to lab_ntp_server
    timezone: Europe/Berlin    # optional
  roles:
    - linux_base
```

The role handles package installs and updates, chrony NTP configuration, timezone, and SSH hardening for both Debian/Ubuntu and RedHat/Rocky families.

---

## Playbook Execution Order

Run in this sequence for a fresh lab deployment:

```bash
cd /home/user/ProxmoxInfra/ansible

# 1. Configure Primary DC (creates AD domain, DNS, DHCP)
ansible-playbook -i inventory/lab.yml playbooks/dc.yml

# 2. Configure Enterprise Root CA (optional — after domain is up)
ansible-playbook -i inventory/lab.yml playbooks/ca.yml

# 3. Configure Secondary DC (optional — after domain is up)
ansible-playbook -i inventory/lab.yml playbooks/dc02.yml

# 4. Configure SCCM prerequisites (after domain is up)
ansible-playbook -i inventory/lab.yml playbooks/sccm.yml

# 5. Configure Entra Connect (optional — after domain join, internet required)
ansible-playbook -i inventory/lab.yml playbooks/aadconnect.yml

# 6. Configure Windows clients (after DC and SCCM are ready)
ansible-playbook -i inventory/lab.yml playbooks/client-windows.yml

# 7. Configure Linux clients (optional)
ansible-playbook -i inventory/lab.yml playbooks/client-linux.yml

# Or run everything at once:
ansible-playbook -i inventory/lab.yml playbooks/site.yml
```
