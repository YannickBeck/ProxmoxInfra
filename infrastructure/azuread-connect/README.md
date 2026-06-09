# lab-aadc01 – Azure AD Connect / Microsoft Entra ID Sync Guide

This document covers standing up **hybrid identity** for the lab on
`lab-aadc01` (VMID **106**, `10.10.10.40` on the internal `vmbr1` bridge).

The goal: synchronize the on-prem Active Directory (`lab.local`) into
**Microsoft Entra ID** (formerly Azure AD) so the lab can do:

- **Hybrid Azure AD Join** of `lab-client01`
- **Intune** enrollment of those devices
- **SCCM ↔ Intune co-management** (workload slider)

> Without directory sync, your Entra/Intune tenant is **cloud-only** — the
> on-prem domain accounts and the domain-joined client cannot become Entra
> identities/devices, and co-management cannot be established.

This VM is provisioned by Terraform only when the boolean variable
`enable_aadconnect` is set to `true` (default **false**). Internet access from
this VM is **required** — the sync engine talks to Entra ID over TCP 443 and
must reach `login.microsoftonline.com`. Use the pfSense / Proxmox NAT gateway
(`10.10.10.1`) or temporarily attach an internet-capable NIC.

---

## VM Facts

| Property | Value |
|---|---|
| Name | `lab-aadc01` |
| VMID | `106` |
| Role | Hybrid identity sync (Entra Connect Sync) |
| IP | `10.10.10.40/24` (static) |
| Gateway | `10.10.10.1` (pfSense / Proxmox NAT — internet) |
| DNS | `10.10.10.10` (lab-dc01) |
| OS | Windows Server 2022 (Desktop Experience) |
| Domain | `lab.local` (NetBIOS `LAB`) |
| Local admin pw | `LabAdm1n!2024` (placeholder — change for real use) |
| Terraform gate | `enable_aadconnect = true` |

---

## Two Options for Directory Sync

There are two Microsoft sync technologies. Pick **one**.

| | **(A) Entra Connect Sync** *(full "Azure AD Connect" agent)* | **(B) Entra Cloud Sync** *(lightweight provisioning agent)* |
|---|---|---|
| What it is | Full sync engine installed on a dedicated member server | Lightweight agent; sync rules live in the cloud |
| Runs on | Dedicated member server (this `lab-aadc01`) | A member server **or even the DC**; multiple agents for HA |
| Footprint | Heavier; SQL LocalDB/SQL, full config wizard | Very light; configured entirely in the Entra portal |
| Password Hash Sync (PHS) | ✅ | ✅ |
| Seamless SSO | ✅ | ✅ |
| Pass-through Auth (PTA) | ✅ | ✅ |
| AD FS / federation | ✅ | ❌ |
| **Hybrid Azure AD Join** (writes SCP) | ✅ (configured by the wizard) | ⚠️ limited — Cloud Sync does **not** configure the SCP; you set Hybrid join up separately |
| Device / group writeback | ✅ | ❌ (no writeback) |
| Exchange hybrid attribute writeback | ✅ | ❌ |
| Filtering granularity | OU **and** attribute-based | OU / group scoped |
| Best for | Full control, device scenarios, this lab | Simple labels, multi-forest disconnected, quick setups |

### Recommendation for this lab

> **Use Option A — Microsoft Entra Connect Sync** on `lab-aadc01`, configured
> with **Password Hash Synchronization (PHS)** + **Seamless SSO**, and with
> **Hybrid Azure AD Join enabled** under the wizard's Device options.
>
> Reason: Hybrid Azure AD Join (which co-management depends on) needs the
> **Service Connection Point (SCP)** written to AD. Entra Connect Sync's wizard
> does this for you; Cloud Sync does not. PHS + Seamless SSO keeps the lab
> simple (no extra PTA agents, no AD FS to maintain) while still giving a real
> SSO experience.

Option B (Cloud Sync) is documented here as the lightweight alternative and is
perfectly fine if you only want users in the cloud and will configure Hybrid
Join by other means.

---

## Prerequisites

- [ ] A **Microsoft Entra tenant** — a free Entra dev tenant, or an
      **M365 E3/E5** or **EMS** trial (any gives you a tenant + onmicrosoft.com domain)
- [ ] A **Global Administrator** account in that tenant (used by the wizard; expect **MFA**)
- [ ] **Intune license** on the user(s) you'll co-manage (EMS E3/E5, M365 E3/E5, or Intune trial)
- [ ] A **verified routable domain** in Entra **OR** plan to use the default
      `<tenant>.onmicrosoft.com` (see the non-routable UPN section below — this is mandatory reading)
- [ ] **Internet access** from `lab-aadc01` (NAT via `10.10.10.1`)
- [ ] **.NET Framework 4.7.2+** (ships with Server 2022)
- [ ] **lab-dc01 reachable** and `lab.local` healthy (`Resolve-DnsName lab.local` works from this VM)

---

## CRITICAL: The non-routable `@lab.local` UPN problem

`lab.local` is a **non-routable** domain — you can never prove ownership of
`.local` to Microsoft. Entra **only accepts a User Principal Name (UPN) suffix
that maps to a verified domain** in the tenant. If your on-prem users have UPNs
like `jdoe@lab.local`, then at sync time Entra **cannot verify `lab.local`** and
will silently replace the suffix, creating the cloud user as:

```
jdoe@<tenant>.onmicrosoft.com
```

That breaks a clean SSO experience and is confusing for testing. **Fix it
before the first sync** by giving users a UPN whose suffix Entra *can* verify.

### The fix (do this BEFORE syncing)

1. **Add an alternative, routable UPN suffix in AD.**
   - GUI: **Active Directory Domains and Trusts** → right-click the root →
     **Properties** → **UPN Suffixes** tab → add e.g.
     `labdemo.onmicrosoft.com` (your tenant) or a verified custom domain → OK.
   - PowerShell (what `install-aadconnect.ps1` does in Phase 2):
     ```powershell
     Set-ADForest -Identity (Get-ADForest).Name -UPNSuffixes @{ add = "labdemo.onmicrosoft.com" }
     ```

2. **Stamp users with the routable suffix.** Adding the suffix only makes it
   *available*; existing users still carry `@lab.local`. Bulk-update them:
   ```powershell
   # Helper provided in install-aadconnect.ps1 (Set-LabUsersUpnSuffix), or inline:
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

> **Why this matters:** with a verified routable suffix matching the user UPN,
> users sync as `jdoe@labdemo.onmicrosoft.com` (or your custom domain) — a real,
> sign-in-able identity — instead of being rewritten to
> `jdoe@<tenant>.onmicrosoft.com`. The on-prem `sAMAccountName` and
> `LAB\jdoe` logon are unaffected; only the UPN changes.

---

## Step-by-step — Option A (Entra Connect Sync)

### 1. Prepare the UPN suffix
Do the **non-routable UPN fix** above first (suffix added + users stamped).
`install-aadconnect.ps1` Phase 2 adds the suffix automatically and reminds you
to stamp users.

### 2. Provision the server + stage the installer
Copy `powershell/install-aadconnect.ps1` to the VM and run it. It is two-phase
(mirrors the DC/SCCM scripts):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-aadconnect.ps1 -DomainJoinCredential (Get-Credential) `
    -UpnSuffix "labdemo.onmicrosoft.com"
```

- **Phase 1** (auto-detected when the box isn't `LAB-AADC01` / not joined):
  rename to `LAB-AADC01`, set static IP `10.10.10.40`, DNS `10.10.10.10`, join
  `lab.local`, reboot.
- **Phase 2** (run the *same command* after reboot, logged in as a domain
  admin): ensure RSAT AD PowerShell, add the routable UPN suffix to the forest,
  test internet to Entra, download the Entra Connect MSI, and **launch the
  wizard**.

### 3. Wizard choices (run the wizard — do NOT pick Express)

| Wizard page | Choice |
|---|---|
| Install type | **Customize** (not "Use express settings") |
| User sign-in | **Password Hash Synchronization** + **Enable single sign-on** (Seamless SSO) |
| Connect to Entra ID | Sign in with a **Global Administrator** (expect **MFA**) |
| Connect directories | Add the **lab.local** forest (enterprise/domain admin creds) |
| Entra sign-in | Confirm the UPN attribute is the **routable suffix** and shows **Verified** |
| Domain/OU filtering | **Sync selected domains and OUs** → tick `OU=Users` and your SCCM OUs (`OU=Servers`, `OU=Clients`) |
| Optional features | Leave defaults (PHS already chosen) |
| **Device options** | **Configure Hybrid Azure AD join** → Windows 10+ domain-joined → select the `lab.local` forest so the wizard writes the **SCP** |
| Ready to configure | Tick **Start the synchronization process when configuration completes** → **Install** |

### 4. Verify the install
On `lab-aadc01`:
```powershell
Get-ADSyncScheduler                      # SyncCycleEnabled : True
Start-ADSyncSyncCycle -PolicyType Delta  # force a delta sync now
```
Then in the **Entra admin center → Users**, confirm your `lab.local` users
appear with **On-premises sync enabled = Yes** and the routable UPN.

---

## Hybrid Azure AD Join

**What it is:** a device that is **both** joined to on-prem AD **and**
registered in Entra ID. Such devices appear under **Entra → Devices** as
`Hybrid Azure AD joined`, which is what lets them auto-enroll into **Intune**
and participate in **co-management**.

**How Entra Connect sets it up:** when you choose *Configure Hybrid Azure AD
join* in the wizard's **Device options**, it writes a **Service Connection Point
(SCP)** object into your AD forest configuration partition. Domain-joined
Windows clients read the SCP to discover the tenant and then register themselves
with Entra automatically (via a scheduled task / GPO `Automatic-Device-Join`).

**Verify on `lab-client01`** (after the client has applied policy and the next
device-join task has run — a reboot or `gpupdate /force` + wait helps):
```powershell
dsregcmd /status
```
Look for:
```
AzureAdJoined : YES
DomainJoined  : YES
```
(`AzureAdJoined: YES` **and** `DomainJoined: YES` together = hybrid joined.)
If `AzureAdJoined` is `NO`, confirm the SCP exists, the client can reach the
internet/Entra, and that a sync has run since the device was created.

---

## Co-management hand-off (SCCM ↔ Intune)

Once devices are **hybrid Azure AD joined** and the users/devices are
**Intune-licensed**, you can hand workloads to the cloud:

1. In the **SCCM (Configuration Manager) console** → **Administration** →
   **Cloud Services** → **Co-management** → enable co-management (sign in with
   the Entra Global Admin / co-management account).
2. Set the **automatic enrollment** scope (e.g. a pilot collection).
3. Use the **workload slider** to move workloads (Compliance policies, Windows
   Update, Endpoint Protection, etc.) from **Configuration Manager** to
   **Pilot Intune** or **Intune**.

See the SCCM guide for the console steps and prerequisites:
[`../vms/sccm/README.md`](../vms/sccm/README.md).

---

## Verification cheat-sheet

| Check | Command / Location | Expected |
|---|---|---|
| Sync scheduler running | `Get-ADSyncScheduler` (on lab-aadc01) | `SyncCycleEnabled : True` |
| Force a sync | `Start-ADSyncSyncCycle -PolicyType Delta` | `Result: Success` |
| Connector run state | `Get-ADSyncConnectorRunStatus` | idle/empty between cycles |
| Users synced | Entra admin center → **Users** | on-prem users present, routable UPN, "synced" source |
| Devices synced | Entra admin center → **Devices** | client listed as **Hybrid Azure AD joined** |
| Client hybrid state | `dsregcmd /status` (on lab-client01) | `AzureAdJoined: YES`, `DomainJoined: YES` |

---

## Option B — Entra Cloud Sync (lightweight alternative)

If you want the minimal path instead of the full agent:

1. In the **Entra admin center** → **Identity** → **Hybrid management** →
   **Microsoft Entra Connect** → **Cloud sync** → **Download agent**.
2. Install the **provisioning agent** on a member server (or even on
   `lab-dc01`), register it with the tenant (Global Admin sign-in), and add the
   `lab.local` forest.
3. Back in the portal, create a **configuration**, scope it by **OU/group**,
   enable **Password Hash Sync**, and start provisioning.

**Remember the limits:** Cloud Sync does **not** write the SCP for Hybrid Azure
AD Join and has **no writeback**. If you go this route and still want hybrid
join, configure the SCP manually (PowerShell module
`Initialize-ADSyncDomainJoinedComputerSync` / `Get-AzureADSSO`) or via GPO.

---

## Licensing & cost-free options

| Capability | Cost | Notes |
|---|---|---|
| Directory sync engine (Connect Sync / Cloud Sync) | **Free** | The agents themselves are free to run |
| Password Hash Sync (PHS) | **Free** (Entra ID Free tier) | No paid Entra tier needed |
| Seamless SSO | **Free** | Included |
| **Hybrid Azure AD Join** | **Free** | Covered by Entra ID Free |
| **Intune / co-management** | **License required** | Needs Intune (EMS E3/E5, M365 E3/E5) or an **Intune trial** |
| Tenant | **Free** | Entra dev tenant or an E3/E5/EMS trial |

> Bottom line: you can get a fully synced, hybrid-joined lab at **no cost**
> using the Entra ID Free tier. The **only** paid piece is **Intune** (and thus
> co-management) — start a free **Intune/EMS/M365 trial** to light that up.

---

## File map

| File | Purpose |
|---|---|
| `README.md` | This guide |
| `powershell/install-aadconnect.ps1` | Two-phase: provision lab-aadc01 + add routable UPN suffix + stage/launch the Entra Connect wizard |
