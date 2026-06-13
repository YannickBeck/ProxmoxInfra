# lab-dc02 – Secondary Domain Controller (VM 105)

## Overview

`lab-dc02` is an optional additional Domain Controller for `lab.local`. It replicates Active Directory, DNS zones, and SYSVOL from `lab-dc01`, providing:

- **DNS redundancy** — clients can still resolve names if `lab-dc01` is offline
- **AD replication practice** — observe intra-site replication with `repadmin`
- **FSMO failover drills** — practice transferring or seizing Operations Master roles
- **High-availability testing** — test SCCM and client behaviour when the primary DC is down

| Property | Value |
|---|---|
| VM ID | 105 |
| Hostname | `lab-dc02` / `LAB-DC02` |
| OS | Windows Server 2022 Desktop Experience |
| IP | `10.10.10.11/24` |
| Gateway | `10.10.10.1` |
| DNS (primary) | `10.10.10.10` (lab-dc01) |
| Domain | `lab.local` |

Enable via `terraform.tfvars`:

```hcl
enable_dc02 = true
```

---

## Prerequisites

Before promoting `lab-dc02`:

- `lab-dc01` is healthy, reachable at `10.10.10.10`, and holding all FSMO roles
- `lab.local` domain functional level is Windows Server 2016 or higher
- VM 105 has been created by Terraform, Windows Server 2022 has been installed, and the VM can reach `10.10.10.10` via `vmbr1`
- The VirtIO network and storage drivers are installed in the VM (from the `virtio-win.iso` attached during setup)

---

## Step 1 — Windows Server Installation

1. Start VM 105 from Proxmox UI or `qm start 105`
2. Boot from the Windows Server 2022 ISO (attached as `ide2`)
3. Install **Windows Server 2022 Standard (Desktop Experience)**
4. Load the VirtIO drivers when prompted (browse the `virtio-win` ISO for SCSI and network drivers)
5. Complete installation; set the local Administrator password
6. Remove the ISO from Proxmox hardware after the first reboot

---

## Step 2 — Promote to Domain Controller

### Option A — PowerShell Script (Recommended)

Copy `setup-dc02.ps1` to the VM and run it in two phases:

**Phase 1** — Rename and domain-join (run as local Administrator):

```powershell
Set-ExecutionPolicy Bypass -Force
.\setup-dc02.ps1 `
  -SafeIp "10.10.10.11" `
  -Gateway "10.10.10.1" `
  -PrimaryDns "10.10.10.10" `
  -DomainName "lab.local" `
  -SafeModePassword (ConvertTo-SecureString "YourDSRMPassword!" -AsPlainText -Force) `
  -DomainJoinCredential (Get-Credential)
```

The VM renames itself `LAB-DC02`, sets the static IP, joins the domain, and reboots.

**Phase 2** — Promote to DC (run after reboot, logged in as domain admin):

```powershell
.\setup-dc02.ps1 `
  -SafeIp "10.10.10.11" `
  -Gateway "10.10.10.1" `
  -PrimaryDns "10.10.10.10" `
  -DomainName "lab.local" `
  -SafeModePassword (ConvertTo-SecureString "YourDSRMPassword!" -AsPlainText -Force) `
  -DomainJoinCredential (Get-Credential)
```

The script detects that the machine is already domain-joined and proceeds directly to `Install-ADDSDomainController`. A second reboot completes the promotion.

### Option B — Ansible Playbook

```bash
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/dc02.yml
```

(Requires WinRM enabled on the VM and correct credentials in inventory.)

### Option C — Manual (Server Manager / GUI)

1. Open **Server Manager → Add Roles and Features**
2. Add: **Active Directory Domain Services**, **DNS Server**, **RSAT-AD-AdminCenter**, **RSAT-ADDS**
3. After installation, click **Promote this server to a domain controller**
4. Choose **Add a domain controller to an existing domain**
5. Domain: `lab.local` — provide credentials for a Domain Admin
6. Check **DNS server** and **Global Catalog**
7. Set the DSRM password
8. Accept defaults for replication source and paths
9. Review and install; VM will reboot automatically

---

## Step 3 — Post-Promotion Configuration

### Update DHCP Scope DNS

After `lab-dc02` is promoted, add `10.10.10.11` as the secondary DNS server in the DHCP scope on `lab-dc01`:

```powershell
# Run on lab-dc01
Set-DhcpServerv4OptionValue -ScopeId 10.10.10.0 `
  -OptionId 6 `
  -Value "10.10.10.10", "10.10.10.11"
```

### Update Static DNS on Other VMs

Update the static DNS configuration on `lab-sccm01` and `lab-ca01` to include `10.10.10.11` as the secondary DNS resolver.

### Verify Replication

```powershell
# Run on either DC
repadmin /replsummary
repadmin /showrepl
dcdiag /v
```

All tests should pass (or show benign informational messages). Replication errors should be investigated before proceeding.

---

## FSMO Roles

Active Directory has five Flexible Single Master Operations (FSMO) roles. By default, all five are held by the first DC (`lab-dc01`).

| Role | Scope | Holder (default) | Description |
|---|---|---|---|
| Schema Master | Forest-wide | lab-dc01 | Controls schema changes (`adprep /forestprep`) |
| Domain Naming Master | Forest-wide | lab-dc01 | Controls adding/removing domains in the forest |
| RID Master | Domain-wide | lab-dc01 | Allocates pools of Relative IDs to DCs |
| PDC Emulator | Domain-wide | lab-dc01 | Handles password changes, time sync, legacy clients |
| Infrastructure Master | Domain-wide | lab-dc01 | Maintains cross-domain object references |

### View Current FSMO Role Holders

```powershell
netdom query fsmo
# or
Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster
Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster
```

### Transfer FSMO Roles (Graceful — both DCs online)

Transfer roles to `lab-dc02` for practice:

```powershell
# Run on lab-dc02 or any DC, as Domain/Schema Admin
Move-ADDirectoryServerOperationMasterRole -Identity "LAB-DC02" `
  -OperationMasterRole PDCEmulator, RIDMaster, InfrastructureMaster

# Forest-wide roles require Schema Admin / Enterprise Admin
Move-ADDirectoryServerOperationMasterRole -Identity "LAB-DC02" `
  -OperationMasterRole SchemaMaster, DomainNamingMaster
```

Transfer roles back to `lab-dc01`:

```powershell
Move-ADDirectoryServerOperationMasterRole -Identity "LAB-DC01" `
  -OperationMasterRole PDCEmulator, RIDMaster, InfrastructureMaster, SchemaMaster, DomainNamingMaster
```

### Seize FSMO Roles (DR Drill — role holder offline)

Use seizing only if the role holder is permanently lost. Seizing is destructive — the old holder must never come back online after seizing.

```powershell
# Run on the surviving DC
Move-ADDirectoryServerOperationMasterRole -Identity "LAB-DC02" `
  -OperationMasterRole PDCEmulator, RIDMaster, InfrastructureMaster `
  -Force

# Or use ntdsutil (classic method):
ntdsutil
> roles
> connections
> connect to server LAB-DC02
> quit
> seize pdc
> seize rid master
> seize infrastructure master
> quit
> quit
```

---

## Verification

```powershell
# AD replication summary — check LastSuccess times and failure counts
repadmin /replsummary

# Detailed replication topology and status per naming context
repadmin /showrepl

# Comprehensive DC health check — runs all built-in diagnostic tests
dcdiag /v

# Confirm DNS zones replicated correctly
Get-DnsServerZone -ComputerName LAB-DC02

# Check SYSVOL replication (DFSR)
dfsrdiag ReplicationState

# Confirm both DCs registered in DNS
nslookup lab.local 10.10.10.11
nslookup lab-dc01.lab.local 10.10.10.11
```

---

## Relevant Files

| Path | Purpose |
|---|---|
| `infrastructure/proxmox/terraform/main.tf` | VM 105 resource (`proxmox_virtual_environment_vm.dc02`) |
| `infrastructure/proxmox/terraform/variables.tf` | `enable_dc02` variable |
| `infrastructure/vms/dc02/powershell/setup-dc02.ps1` | Two-phase promotion script |
| `infrastructure/vms/dc/README.md` | lab-dc01 (primary DC) guide |
| `infrastructure/vms/dc/powershell/setup-dc.ps1` | Primary DC setup script |
