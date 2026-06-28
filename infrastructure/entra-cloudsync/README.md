# lab-cloudsync01 – Microsoft Entra Cloud Sync Guide

This document covers standing up **hybrid identity the lightweight way** for the
lab on `lab-cloudsync01` (VMID **109**, `10.10.10.41` on the internal `vmbr1`
bridge), using the **Microsoft Entra Cloud Sync** provisioning agent.

The goal is the same as the full Entra Connect Sync server (`lab-aadc01`, VM 106):
synchronize the on-prem Active Directory (`lab.local`) into **Microsoft Entra ID**
(formerly Azure AD). The difference is *how*: Cloud Sync runs a thin agent on this
member server and keeps **all of the sync configuration in the cloud**.

> This is the **lighter ALTERNATIVE** to Entra Connect Sync (VM 106). You can run
> **either** one — or **both** to compare approaches — but do **not** sync the
> **same objects** with both at once.

This VM is provisioned by Terraform only when the boolean variable
`enable_cloudsync` is set to `true` (default **false**). Internet access from this
VM is **required** — the agent talks to Entra ID over TCP 443 and must reach
`login.microsoftonline.com`. Use the pfSense / OPNsense / Proxmox NAT gateway
(`10.10.10.1`) or temporarily attach an internet-capable NIC.

---

## VM Facts

| Property | Value |
|---|---|
| Name | `lab-cloudsync01` |
| VMID | `109` |
| Role | Hybrid identity sync (Entra **Cloud Sync** provisioning agent) |
| IP | `10.10.10.41/24` (static) |
| Gateway | `10.10.10.1` (pfSense / OPNsense / Proxmox NAT — internet) |
| DNS | `10.10.10.10` (lab-dc01) |
| OS | Windows Server 2022 (Desktop Experience), domain-joined member |
| Domain | `lab.local` (NetBIOS `LAB`) |
| Local admin pw | `LabAdm1n!2024` (placeholder — change for real use) |
| Terraform gate | `enable_cloudsync = true` |

---

## Cloud Sync vs Connect Sync

Both technologies synchronize on-prem AD to Entra ID. Cloud Sync is the
cloud-managed, lightweight agent; Connect Sync is the full on-box engine. Pick
**one per set of objects**.

| | **Entra Cloud Sync** *(this VM 109)* | **Entra Connect Sync** *(VM 106, lab-aadc01)* |
|---|---|---|
| What it is | Lightweight provisioning **agent**; sync rules live in the cloud | Full sync **engine** installed on a dedicated member server |
| Where configured | Entirely **cloud-side** (Entra admin center) — no on-box wizard | On-box **wizard** + Synchronization Service Manager |
| Footprint | **Very light** (thin agent, no SQL) | Heavier (SQL LocalDB / SQL, full config) |
| Runs on | A member server (this VM) **or even the DC**; multiple agents | Dedicated member server |
| **High availability** | **Yes — add more agents** (active/active, automatic failover) | Single active server + a staging server (manual swap) |
| Multiple **disconnected** forests | **Yes** (great for mergers / multi-forest) | Yes, but a single engine connects all reachable forests |
| Password Hash Sync (PHS) | ✅ | ✅ |
| Seamless SSO | ✅ | ✅ |
| Pass-through Auth (PTA) | ✅ | ✅ |
| AD FS / federation | ❌ | ✅ |
| Filtering granularity | **OU / group scoped** | OU **and** attribute-based (complex filtering) |
| **Device / group writeback** | ❌ (no writeback) | ✅ |
| **Hybrid Azure AD Join** (writes SCP) | ⚠️ does **not** configure the SCP — set Hybrid join up separately | ✅ (the wizard writes the SCP) |
| Exchange hybrid attribute writeback | ❌ | ✅ |
| Large / complex topologies | Limited (object counts + advanced scenarios capped) | ✅ full feature set |
| Best for | Simple scopes, multi-forest disconnected, low footprint, quick HA | Device scenarios, writeback, complex filtering, full control |

**Key Cloud Sync limitations to remember:** no device or group **writeback**, no
**SCP** for Hybrid Azure AD Join, **OU/group-scoped** filtering only (no
attribute-based complex filtering), no AD FS, and it targets **a group/OU scope**
rather than huge or highly-customized topologies. If you need any of those, use
Connect Sync on VM 106 instead.

---

## Prerequisites

- [ ] A **Microsoft Entra tenant** — a free Entra dev tenant, or an
      **M365 E3/E5** or **EMS** trial (any gives you a tenant + onmicrosoft.com domain)
- [ ] A **Hybrid Identity Administrator** or **Global Administrator** account in
      that tenant (used to register the agent; expect **MFA**)
- [ ] A **verified routable domain** in Entra **OR** plan to use the default
      `<tenant>.onmicrosoft.com` (see the non-routable UPN section below — mandatory reading)
- [ ] **Internet access** from `lab-cloudsync01` (NAT via `10.10.10.1`)
- [ ] **.NET Framework 4.7.2+** (ships with Server 2022)
- [ ] **lab-dc01 reachable** and `lab.local` healthy (`Resolve-DnsName lab.local` works from this VM)
- [ ] VM 109 created by Terraform (`enable_cloudsync = true`) with Windows Server 2022 installed and VirtIO drivers present

---

## Step 1 – Enable in Terraform

Set the toggle and apply:

```hcl
# infrastructure/proxmox/terraform/terraform.tfvars
enable_cloudsync = true
```

```bash
cd /home/user/ProxmoxInfra/infrastructure/proxmox/terraform
terraform apply
```

This creates VM 109. Boot it and install Windows Server 2022 (Desktop
Experience) exactly like the other servers (load the VirtIO SCSI + NetKVM
drivers, set the local Administrator password, change the placeholder).

---

## Step 2 – Install the Provisioning Agent

### Option A – Ansible

```bash
ansible-playbook -i inventory/lab.yml playbooks/cloudsync.yml
```

(Requires WinRM enabled on the VM and correct credentials in inventory.)

### Option B – PowerShell script (two phases)

Copy `powershell/install-cloudsync.ps1` to the VM and run it from an **elevated**
PowerShell session. The script is two-phase, just like the DC / SCCM scripts:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-cloudsync.ps1 -DomainJoinCredential (Get-Credential)
```

- **Phase 1** (auto-detected when the box isn't `LAB-CLOUDSYNC01` / not joined):
  rename to `LAB-CLOUDSYNC01`, set static IP `10.10.10.41`, DNS `10.10.10.10`,
  join `lab.local`, **reboot**.
- **Phase 2** (run the *same command* after reboot, logged in as a domain admin):
  test internet to `login.microsoftonline.com:443` (it **fails with a clear
  pfSense/OPNsense NAT message** if unreachable), download the agent from
  `https://aka.ms/EntraProvisioningAgent`, install it silently (`/quiet`), then
  print the cloud-side next steps.

> Unlike Connect Sync, Cloud Sync has **no on-box configuration wizard** for the
> sync rules. The script only renames/joins/installs the agent and then hands you
> off to the Entra admin center + the `AADCloudSyncTools` PowerShell module.

---

## CRITICAL: The non-routable `@lab.local` UPN problem

This is **the same caveat as Connect Sync** — Cloud Sync does not change it.
`lab.local` is a **non-routable** domain; you can never prove ownership of
`.local` to Microsoft. Entra **only accepts a UPN suffix that maps to a verified
domain** in the tenant. If your on-prem users have UPNs like `jdoe@lab.local`,
Entra **cannot verify `lab.local`** and silently rewrites the suffix, creating the
cloud user as:

```
jdoe@<tenant>.onmicrosoft.com
```

That breaks a clean SSO experience. **Fix it BEFORE the first sync.**

### The fix (do this BEFORE provisioning)

1. **Add an alternative, routable UPN suffix in AD.**
   - GUI: **Active Directory Domains and Trusts** → right-click the root →
     **Properties** → **UPN Suffixes** tab → add e.g.
     `labdemo.onmicrosoft.com` (your tenant) or a verified custom domain → OK.
   - PowerShell:
     ```powershell
     Set-ADForest -Identity (Get-ADForest).Name -UPNSuffixes @{ add = "labdemo.onmicrosoft.com" }
     ```

2. **Stamp users with the routable suffix** (adding the suffix only makes it
   *available*; existing users still carry `@lab.local`):
   ```powershell
   Get-ADUser -Filter "Enabled -eq 'True'" -Properties UserPrincipalName |
     Where-Object { $_.UserPrincipalName -like "*@lab.local" } |
     ForEach-Object {
       $new = ($_.UserPrincipalName -split "@")[0] + "@labdemo.onmicrosoft.com"
       Set-ADUser -Identity $_ -UserPrincipalName $new
     }
   ```

3. **Verify the domain in Entra** (skip if you used the built-in
   `onmicrosoft.com`, which is already verified). For a custom domain, add it in
   the Entra admin center and complete DNS verification.

> The `install-aadconnect.ps1` script (VM 106) contains a `Set-LabUsersUpnSuffix`
> helper for exactly this; the same approach applies here. The on-prem
> `sAMAccountName` / `LAB\jdoe` logon is unaffected — only the UPN changes.

---

## Step 3 – Cloud-Side Configuration (Entra admin center)

All Cloud Sync configuration happens in the **cloud**. After the agent is
installed:

### 3a. Register the agent

The agent configuration wizard launches at the end of the silent install. If it
didn't, start it manually:

```
C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\AADConnectProvisioningAgentWizard.exe
```

Sign in with a **Hybrid Identity Administrator / Global Administrator** (expect
**MFA**) and register the agent against the **lab.local** forest.

### 3b. Build the configuration in the portal

1. **Entra admin center** → **Identity** → **Hybrid management** →
   **Microsoft Entra Connect** → **Cloud sync**.
2. **New configuration** → select the registered **lab.local** forest.
3. Set the **scope** by **OU or group** (e.g. `OU=Users`). Remember: Cloud Sync
   is OU/group scoped — there is no attribute-based filtering.
4. Enable **Password Hash Sync** (and **Seamless SSO** if desired).
5. **Enable** the configuration to start provisioning, then **Provision on
   demand** a test user to confirm it flows before enabling broadly.

### 3c. Manage from PowerShell (AADCloudSyncTools)

Cloud Sync ships a dedicated module instead of `Get-ADSyncScheduler` (which is a
Connect-Sync cmdlet and does **not** apply here):

```powershell
Install-Module -Name AADCloudSyncTools -Scope AllUsers
Import-Module AADCloudSyncTools
Connect-AADCloudSyncTools                 # sign in to the tenant
Get-AADCloudSyncToolsServiceStatus        # agent + service health
Export-AADCloudSyncToolsLogs              # collect provisioning logs for support
```

---

## Verification

| Check | Command / Location | Expected |
|---|---|---|
| Agent service running | `Get-Service AADConnectProvisioningAgent` (on this VM) | `Running` |
| Agent health (portal) | Entra admin center → **Cloud sync** → your configuration | agent shows **Active / Healthy** |
| Service status (module) | `Get-AADCloudSyncToolsServiceStatus` | agent + service healthy |
| Provisioning logs | Entra admin center → Cloud sync → **Logs** (or `Export-AADCloudSyncToolsLogs`) | objects provisioned, no errors |
| Users synced | Entra admin center → **Users** | on-prem users present, **routable UPN**, "synced" source, `On-premises sync enabled = Yes` |
| Provision on demand | Cloud sync config → **Provision on demand** → pick a user | the user provisions successfully |

> Note: `Get-ADSyncScheduler` / `Get-ADSyncToolsX` are **Connect Sync** cmdlets
> and are **not applicable** to Cloud Sync. Use **AADCloudSyncTools** instead.

---

## When to Use Which

| Situation | Recommendation |
|---|---|
| You want the **smallest footprint** and cloud-managed rules | **Cloud Sync** (this VM 109) |
| **Multiple disconnected forests** (mergers, multi-org) | **Cloud Sync** — designed for it |
| You want **HA** quickly | **Cloud Sync** — just add a second agent |
| You need **Hybrid Azure AD Join** (co-management) | **Connect Sync** (VM 106) — it writes the SCP; Cloud Sync does not |
| You need **device / group / Exchange writeback** | **Connect Sync** (VM 106) |
| You need **attribute-based (complex) filtering** or **AD FS** | **Connect Sync** (VM 106) |
| Large / highly-customized topology | **Connect Sync** (VM 106) |

> **Recommendation for this lab:** because the lab's headline goal is
> **co-management** (which depends on Hybrid Azure AD Join / the SCP), the
> primary identity path is **Connect Sync on VM 106**. Stand up **Cloud Sync on
> VM 109** alongside it to **compare** the lightweight approach — register both
> agents if you like, but **scope them to different OUs/groups** so the two
> engines never provision the **same objects**.

---

## File map

| File | Purpose |
|---|---|
| `README.md` | This guide |
| `powershell/install-cloudsync.ps1` | Two-phase: provision lab-cloudsync01 + install the Entra Cloud Sync provisioning agent, then hand off to cloud-side config |
| `../azuread-connect/README.md` | Entra Connect Sync (VM 106) — the full-engine alternative |
