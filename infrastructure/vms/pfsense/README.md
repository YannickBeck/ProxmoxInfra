# lab-fw01 – pfSense CE Router / Firewall Setup Guide

This document covers deploying `lab-fw01` (VM 100) as a [pfSense CE](https://www.pfsense.org/) router and firewall that sits between the isolated lab network (`vmbr1`, `10.10.10.0/24`) and the home LAN / internet (`vmbr0`, home DHCP).

pfSense replaces the Proxmox host as the lab's `10.10.10.1` gateway and provides **NAT** so lab VMs can reach the internet. Internet access is required for:

- SCCM ADK / WinPE add-on and prerequisite downloads (~1–3 GB)
- Windows Update / WSUS upstream sync
- Azure AD Connect (Entra ID) sync for hybrid join / co-management

…while still keeping the lab logically segmented behind a controllable firewall.

---

## Role Summary

| Property | Value |
|---|---|
| VM ID | 100 |
| Hostname | lab-fw01 |
| Product | pfSense CE 2.7.x |
| Terraform toggle | `enable_pfsense = true` (default `false`) |
| ISO variable | `pfsense_iso` (default `pfSense-CE-2.7.2-RELEASE-amd64.iso`) |
| WAN interface | `vtnet0` → `vmbr0` (home LAN, DHCP) |
| LAN interface | `vtnet1` → `vmbr1` (lab, static `10.10.10.1/24`) |
| LAN gateway IP | `10.10.10.1` (lab default gateway) |
| DHCP server | **Disabled on pfSense** — the Windows DC remains the DHCP server |
| Web GUI | `https://10.10.10.1` (default login `admin` / `pfsense`) |

---

## IMPORTANT – Gateway Migration (avoid IP conflict)

In the **base lab design** the Proxmox host itself owns `10.10.10.1/24` on `vmbr1` and acts as the lab gateway. When pfSense is deployed it takes over `10.10.10.1` as the LAN gateway, so you **must remove the IP from the Proxmox host's `vmbr1`** first, otherwise two devices answer for `10.10.10.1` and ARP/routing breaks.

Convert `vmbr1` on the Proxmox host into a **bridge-only (L2) interface** with no IP:

Edit `/etc/network/interfaces` on the Proxmox host. Change the existing stanza:

```
# BEFORE — Proxmox host holds the lab gateway IP
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    comment Lab internal 10.10.10.0/24
```

to:

```
# AFTER — pfSense (VM 100) owns 10.10.10.1; vmbr1 is L2-only
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    comment Lab internal 10.10.10.0/24 (gateway = pfSense lab-fw01)
```

Apply without rebooting:

```bash
ifreload -a
```

Notes:

- `inet manual` brings the bridge up at layer 2 but assigns **no IP** — exactly what we want when pfSense is the router.
- `bridge-ports none` is kept: `vmbr1` still has no physical uplink. The only path to the internet is **through pfSense's WAN** (`vtnet0` on `vmbr0`).
- After this change the Proxmox host can no longer reach `10.10.10.0/24` directly. That is expected. Manage the lab from a lab VM, or add a static route on the Proxmox host via pfSense's WAN IP if host-to-lab access is needed.
- If you ever remove pfSense (`enable_pfsense = false`), revert this stanza back to the `inet static` form so the lab keeps a gateway.

---

## Network Topology

```
            Home LAN / Internet
            192.168.1.0/24 (DHCP)
                     |
                  vmbr0 (WAN bridge, has physical NIC)
                     |
               +-----------+
               |  lab-fw01 |  VM 100  (pfSense CE)
               |  vtnet0 = WAN (DHCP from home router)
               |  vtnet1 = LAN 10.10.10.1/24  + NAT
               +-----------+
                     |
                  vmbr1 (lab bridge, L2-only, no IP, no uplink)
                     |
   +--------+--------+--------+----------+
   |        |        |        |          |
 dc01     sccm01   client01  dc02      (other lab VMs)
 .10       .20      .50/dhcp  .11
```

---

## Interface Assignment

| pfSense interface | Proxmox NIC order | Bridge | Role | IPv4 |
|---|---|---|---|---|
| WAN | net0 (first) | `vmbr0` | Uplink to home LAN / internet | DHCP (from home router) |
| LAN | net1 (second) | `vmbr1` | Lab gateway | Static `10.10.10.1/24` |

Inside pfSense, VirtIO NICs appear as `vtnet0`, `vtnet1` in PCI order. The Terraform definition attaches `net0` to `vmbr0` (WAN) and `net1` to `vmbr1` (LAN), so:

- `vtnet0` = WAN
- `vtnet1` = LAN

If the order is reversed at the console (you can tell because WAN will not pull a DHCP lease), simply re-run the interface assignment step and swap them.

---

## DHCP Strategy – DC stays the DHCP server (default)

This lab keeps **DHCP on the Windows Domain Controller** (`lab-dc01`, `10.10.10.10`) and **disables the pfSense DHCP server on LAN**.

Why AD-integrated DHCP is preferred here:

- The DC's DHCP is **authorized in Active Directory** and integrates with **DNS dynamic updates**, so leased clients self-register their A/PTR records in the `lab.local` zone automatically.
- It keeps a single source of truth for IP/DNS/scope options (006 DNS, 015 domain, 003 router) and matches real-world Windows infrastructure you are practising for.
- DHCP failover / split-scope drills become possible once `lab-dc02` exists.

> Alternative (not the default): you may instead use **pfSense's DHCP server** and disable the DC's DHCP role. This is simpler if you are not practising Windows DHCP, but you lose AD-integrated dynamic DNS registration and authorization. Pick **one** DHCP server for `10.10.10.0/24` — never run both at once or clients will get conflicting leases.

To disable the pfSense DHCP server on LAN (web GUI): **Services → DHCP Server → LAN tab → uncheck "Enable DHCP server on LAN interface" → Save**.

---

## DNS Strategy

DNS stays Windows-centric, with pfSense only used for upstream internet resolution:

1. **Lab VMs** use the DC (`10.10.10.10`) as their primary DNS server (and `10.10.10.11` once `lab-dc02` exists). This is set by static IP config and by DHCP option 006.
2. **The DC's DNS forwarder** points to **pfSense (`10.10.10.1`)** for any name it is not authoritative for. On the DC:

   ```powershell
   # Forward unresolved queries to pfSense, which forwards to the internet
   Set-DnsServerForwarder -IPAddress 10.10.10.1 -UseRootHint $false
   ```

3. **pfSense DNS Resolver** (`unbound`) resolves/forwards those queries out the **WAN**. In the web GUI: **Services → DNS Resolver → Enable**. For a lab, enabling **Forwarding Mode** to send queries to the home router or a public resolver (e.g. `1.1.1.1`, `9.9.9.9` under **System → General Setup → DNS Servers**) is the simplest and works reliably behind a home router.

Result chain: `lab VM → DC (authoritative for lab.local) → pfSense resolver → internet`.

---

## Outbound NAT

Leave pfSense Outbound NAT in **Automatic** mode (the default):

- **Firewall → NAT → Outbound → Mode: Automatic outbound NAT rule generation.**
- pfSense automatically source-NATs the LAN subnet `10.10.10.0/24` to the WAN interface address, so lab VMs share pfSense's home-LAN IP when reaching the internet.

No manual rules are needed for basic internet access. Switch to **Hybrid** only if you later add VLANs (see Advanced section) and need explicit NAT rules per subnet.

---

## Firewall Rules

pfSense ships with a default **LAN → any allow** rule. For lab convenience this is fine and lets every lab VM reach the internet and each other.

Recommended starting point (Firewall → Rules → LAN):

| # | Action | Protocol | Source | Destination | Notes |
|---|---|---|---|---|---|
| 1 | Pass | any | LAN net | LAN address | Allow lab → pfSense (GUI/DNS/gateway) |
| 2 | Pass | any | LAN net | any | Default lab convenience rule (internet + lab) |

Optional hardening (apply once the lab is stable):

- **Block lab → Proxmox management.** If your Proxmox host management IP is reachable, add a **Block** rule above the allow rule:

  | Action | Protocol | Source | Destination | Notes |
  |---|---|---|---|---|
  | Block | any | LAN net | `192.168.1.100` (Proxmox mgmt IP) | Keep the lab from touching the hypervisor |

- **Block lab → home LAN** (`192.168.1.0/24`) except the gateway, to stop lab traffic leaking onto the home network while still allowing internet via NAT:

  | Action | Protocol | Source | Destination | Notes |
  |---|---|---|---|---|
  | Block | any | LAN net | `192.168.1.0/24` | Place ABOVE the "LAN net → any" allow rule |

- Tighten the default **LAN → any** rule to specific ports (DNS 53, HTTP/HTTPS 80/443) once you know exactly what the lab needs to reach.

> Rule order matters: pfSense evaluates top-to-bottom and stops at the first match. Put block rules **above** the broad allow rule.

---

## Install Steps

### Step 1 – Create the VM with Terraform

Enable the pfSense toggle and (re)apply:

```bash
cd /home/user/ProxmoxInfra/infrastructure/proxmox/terraform

# In terraform.tfvars set:
#   enable_pfsense = true
#   pfsense_iso    = "pfSense-CE-2.7.2-RELEASE-amd64.iso"

terraform plan
terraform apply
```

This creates VM 100 (`lab-fw01`) with two NICs: `net0` → `vmbr0` (WAN), `net1` → `vmbr1` (LAN), and the pfSense ISO mounted. Upload the pfSense ISO to `local:iso/` first (download from <https://www.pfsense.org/download/>).

### Step 2 – Run the pfSense Installer

1. Start the VM: `qm start 100` and open the Proxmox console.
2. Accept the copyright/license screen.
3. Choose **Install pfSense**.
4. Partitioning: **Auto (ZFS)** is recommended (or **Auto (UFS)** for the smallest footprint). Accept defaults (stripe / single disk).
5. Let the installer copy the system, then choose **Reboot**.
6. **Remove the install media** before it boots again: in Terraform-managed VMs the ISO stays attached, so either detach the CD in the Proxmox UI (Hardware → CD/DVD → Do not use any media) or set the boot order to disk-first. Otherwise it boots the installer again.

### Step 3 – Assign Interfaces at the Console

After reboot, pfSense drops to the console menu and asks about interface assignment:

1. **Should VLANs be set up now? [y|n]:** `n` (unless you are doing the advanced VLAN option below).
2. **Enter the WAN interface name:** `vtnet0`
3. **Enter the LAN interface name:** `vtnet1`
4. Leave optional interfaces blank, confirm with `y`.

### Step 4 – Set the LAN IP at the Console

From the console menu choose **2) Set interface(s) IP address → LAN**:

- IPv4 address: `10.10.10.1`
- Subnet bit count: `24`
- Upstream gateway for LAN: **none** (press Enter — LAN is not the WAN)
- IPv6: `n` (none, unless you want it)
- **Enable DHCP server on LAN? `n`** ← keep DHCP on the Windows DC
- Revert web GUI to HTTP? `n` (keep HTTPS)

WAN (`vtnet0`) should already have pulled a DHCP lease from the home router — the console banner shows both interface IPs.

### Step 5 – Finish Configuration in the Web GUI

From a **lab VM** (e.g. lab-dc01 once it has an IP, or any VM on `vmbr1`), browse to:

```
https://10.10.10.1
```

Log in with the defaults **admin / pfsense**, then run the **Setup Wizard**:

1. Set a strong **admin password** (do not leave `pfsense`).
2. Hostname `lab-fw01`, domain `lab.local`.
3. **DNS servers:** the home router or a public resolver (`1.1.1.1`). Uncheck "Override DNS" if you want to keep these.
4. Timezone, then finish.
5. **Services → DNS Resolver → Enable** (and Forwarding Mode for simplicity).
6. **Services → DHCP Server → LAN → ensure DHCP is DISABLED** (DC owns DHCP).
7. Confirm **Firewall → NAT → Outbound** is **Automatic**.
8. Review **Firewall → Rules → LAN** (default allow is present).

Then point the DC's DNS forwarder at `10.10.10.1` (see DNS Strategy above).

---

## Optional / Advanced – VLAN Segmentation

> **Advanced and NOT the default.** The flat `10.10.10.0/24` design above is what the rest of this repo assumes. Only pursue VLANs if you specifically want to practise inter-VLAN routing and firewalling.

A common three-tier scheme:

| VLAN ID | Name | Subnet | pfSense gateway | Purpose |
|---|---|---|---|---|
| 10 | Management | `10.10.10.0/24` | `10.10.10.1` | DC, SCCM, infra (current flat net) |
| 20 | Servers | `10.10.20.0/24` | `10.10.20.1` | Member servers / app servers |
| 30 | Clients | `10.10.30.0/24` | `10.10.30.1` | Win11 clients, test endpoints |

Requirements and caveats:

- **`vmbr1` must be VLAN-aware** on the Proxmox host (set **VLAN aware: yes** on the bridge, or `bridge-vlan-aware yes` in `/etc/network/interfaces`).
- Each VM's NIC must be **tagged** with the correct VLAN tag in Proxmox (Hardware → Network Device → VLAN Tag), or pfSense must carry tagged sub-interfaces on a trunk.
- In pfSense: **Interfaces → Assignments → VLANs** create VLANs 10/20/30 on the LAN parent (`vtnet1`), then assign each as an interface (`LAN`, `OPT1`, `OPT2`) with its gateway IP.
- Add **per-VLAN firewall rules** (e.g. Clients may reach Servers on specific ports only) and switch Outbound NAT to **Hybrid** to NAT each subnet.
- DHCP/DNS scopes on the DC would need to expand to multiple scopes (one per subnet) or use DHCP relay (`ip helper`) per VLAN.

This is a meaningful jump in complexity — treat it as a separate project once the flat lab works.

---

## Verification

From a lab VM (e.g. lab-dc01 or lab-client01):

```powershell
# 1. Reach the pfSense LAN gateway
ping 10.10.10.1

# 2. Confirm NAT to the internet works (raw IP, no DNS)
ping 1.1.1.1

# 3. Confirm DNS resolution through the DC → pfSense → internet chain
nslookup www.microsoft.com
Resolve-DnsName www.microsoft.com

# 4. Confirm the default route points at pfSense
Get-NetRoute -DestinationPrefix 0.0.0.0/0
```

On pfSense itself (**Diagnostics → Ping**, or the console):

```sh
# WAN has a lease and can reach the internet
ping -c 3 1.1.1.1
```

Expected results: `10.10.10.1` replies, `1.1.1.1` replies (NAT working), and external names resolve. If `ping 1.1.1.1` works but `nslookup` fails, the problem is DNS (check the DC forwarder → pfSense resolver). If `10.10.10.1` is unreachable, re-check the Proxmox `vmbr1` migration (it must be `inet manual`) and the pfSense LAN interface assignment.

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Two devices answer for `10.10.10.1` / intermittent connectivity | Proxmox `vmbr1` still has the static IP — change it to `iface vmbr1 inet manual` and run `ifreload -a` |
| WAN has no IP at the console | Wrong NIC assigned as WAN — re-run interface assignment, swap `vtnet0`/`vtnet1` |
| Lab VMs get no DHCP lease | DHCP is disabled on pfSense (intended) — verify the **DC** DHCP scope is active and authorized |
| `ping 1.1.1.1` fails from a lab VM | Outbound NAT not Automatic, or LAN firewall rule missing/blocked; check **Firewall → NAT/Rules** |
| External names don't resolve | DC forwarder not pointing to `10.10.10.1`, or pfSense DNS Resolver disabled |
| Installer boots again after install | Detach the pfSense ISO (CD/DVD → Do not use any media) or set boot order to disk-first |
| Can't reach `https://10.10.10.1` GUI | Browse from a **lab VM** (the Proxmox host no longer has a lab IP); check LAN rule allows LAN→LAN address |
