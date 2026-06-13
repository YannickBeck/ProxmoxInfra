# lab-opnsense01 – OPNsense CE Router / Firewall (VM 107)

## Overview

`lab-opnsense01` is an optional alternative to `lab-fw01` (pfSense, VM 100). Both serve the same role — the 10.10.10.1 gateway that provides NAT internet access and east-west segmentation for the isolated lab network — but they are **mutually exclusive**. Only one can be active at a time.

Enable via `terraform.tfvars`:

```hcl
enable_opnsense = true
enable_pfsense  = false   # must be false — Terraform will skip VM 107 if pfSense is also true
opnsense_iso    = "OPNsense-24.7-dvd-amd64.iso"
```

---

## OPNsense vs pfSense — Comparison

| Feature | OPNsense CE | pfSense CE |
|---|---|---|
| Base OS | HardenedBSD (FreeBSD-based) | FreeBSD |
| Web UI | Modern, responsive (Bootstrap) | Functional, less modern |
| REST API | Built-in (`os-api` plugin, fully documented) | Limited (unofficial xmlrpc only in CE) |
| IDS/IPS | Suricata (built-in, integrated UI) | Snort or Suricata (package, less integrated) |
| Update cadence | Monthly major releases (24.1, 24.7 …) | Twice-yearly point releases |
| Package management | pkg + firmware UI | pkg |
| HA / CARP | Yes | Yes |
| ZenArmor | Yes (Sensei plugin) | No |
| Community | Strong, European (Deciso) | Strong, American (Netgate) |
| License | 2-clause BSD | Apache 2.0 |
| Recommendation for lab | Preferred — better API for automation | Fine for simpler firewall-only labs |

**Recommendation:** OPNsense is the better choice for a professional automation lab. Its documented REST API enables Ansible/Terraform post-provisioning of firewall rules, aliases, and DNS without manual UI interaction.

---

## Role in the Lab

- **IP on LAN (vmbr1):** `10.10.10.1/24` — same as pfSense
- **WAN (vmbr0):** DHCP from home router
- Provides NAT so lab VMs can reach the internet (Windows Updates, SCCM downloads, Azure AD)
- Optional IDS/IPS via Suricata monitors lab traffic
- Replaces the Proxmox host's `10.10.10.1` address on `vmbr1`

---

## vmbr1 Migration — Remove Proxmox Host IP

Before or immediately after enabling OPNsense, remove the `10.10.10.1/24` address from the Proxmox host's `vmbr1` interface. If both the host and OPNsense hold `10.10.10.1`, routing will break.

Edit `/etc/network/interfaces` on the Proxmox host:

```
# Before (host owns the IP):
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# After (host has no IP on vmbr1 — OPNsense owns it):
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

Then apply: `ifreload -a`

Reverse this change if you later disable OPNsense and want the host to retain reachability on the lab subnet.

---

## Download

1. Go to https://opnsense.org/download/
2. Select: **Architecture** = amd64, **Image type** = dvd, **Mirror** = any
3. Download the `.iso.bz2` file (e.g. `OPNsense-24.7-dvd-amd64.iso.bz2`)
4. Decompress: `bunzip2 OPNsense-24.7-dvd-amd64.iso.bz2`
5. Upload to Proxmox: **Datacenter → pve → local → ISO Images → Upload**

---

## Installation Steps

### 1. Start VM 107 from the Proxmox UI

```bash
qm start 107
```

Open the console (Proxmox UI → VM 107 → Console).

### 2. Boot from ISO

The installer boots automatically. At the login prompt, log in as:

- User: `installer`
- Password: `opnsense`

### 3. Run the Installer

Select **Install (ZFS)** or **Install (UFS)**:

- ZFS is recommended for its data integrity features.
- Select **Auto (UFS)** for simplicity if ZFS feels unfamiliar.
- Choose the target disk (`vtbd0` / `da0` — the 16 GB VirtIO disk).
- Accept defaults for partitioning.
- Set the root password when prompted.
- Reboot when prompted. Remove the ISO (Proxmox UI → Hardware → CD-ROM → Do not use any media) before the VM restarts.

### 4. Assign Interfaces at the Console

After reboot, OPNsense boots to a menu. Choose **1) Assign interfaces**:

```
Do you want to configure LAGGs now? → n
Do you want to configure VLANs now? → n

Enter the WAN interface name or 'a' for auto-detection: vtnet0
Enter the LAN interface name or 'a' for auto-detection: vtnet1
Enter the Optional 1 interface name: (leave blank, press Enter)

Do you want to proceed? → y
```

### 5. Set LAN IP Address at the Console

Choose **2) Set interface IP address** → select **LAN**:

```
Configure IPv4 address LAN interface via DHCP? → n
Enter new LAN IPv4 address: 10.10.10.1
Enter new LAN IPv4 subnet bit count (1 to 32): 24
For LAN, press <ENTER> for none (no upstream gateway): (press Enter)
Configure IPv6 address LAN interface via DHCP6? → n
Enter new LAN IPv6 address: (press Enter — skip IPv6)
Do you want to enable the DHCP server on LAN? → n  (DC handles DHCP)
Do you want to revert to HTTP as the webConfigurator protocol? → n
```

OPNsense will print: `The IPv4 LAN address has been set to 10.10.10.1`

---

## Web GUI Initial Setup

Open a browser from a lab VM (or from the Proxmox host if it has a route to vmbr1) and navigate to:

```
https://10.10.10.1
```

Default credentials:
- Username: `root`
- Password: `opnsense`

Work through the **Setup Wizard**:

1. **General Information:** Hostname = `opnsense`, Domain = `lab.local`, DNS = `1.1.1.1` (or leave as WAN upstream — DC will be set later)
2. **Time Server:** NTP defaults are fine
3. **WAN Interface:** DHCP (from home router via vmbr0)
4. **LAN Interface:** Confirm `10.10.10.1/24`
5. **Admin Password:** Change from default immediately
6. **Reload:** Apply and finish

### Disable OPNsense DHCP on LAN

OPNsense's DHCP server on LAN must be disabled — the lab DC (`lab-dc01`, `10.10.10.10`) handles DHCP for the `10.10.10.0/24` scope.

Navigate to: **Services → DHCPv4 → LAN** → uncheck **Enable DHCP server on LAN interface** → Save.

### Configure NAT (Outbound)

NAT is enabled automatically in Automatic mode. Verify at **Firewall → NAT → Outbound**: the mode should be **Automatic outbound NAT rule generation**. No manual rules are needed for basic internet access.

### DNS Upstream

At **System → Settings → General**, set DNS servers to `1.1.1.1` and `8.8.8.8` for the WAN resolver, or leave blank to inherit from WAN DHCP. Lab VMs should use `10.10.10.10` (DC) as their DNS, which will forward external queries upstream.

---

## Ansible Management

OPNsense exposes a REST API via the `os-api` plugin (enabled by default in 24.x). You can also manage it over SSH.

### SSH Access

Enable SSH in the OPNsense GUI: **System → Settings → Administration** → check **Secure Shell** → allow root login → Save.

From the Ansible control machine:

```bash
ssh root@10.10.10.1
```

### Ansible via community.general.opnsense_* modules

The `community.general` collection includes modules for managing OPNsense firewall aliases, rules, and more. Install it:

```bash
ansible-galaxy collection install community.general
```

Example task to create a firewall alias:

```yaml
- name: Create lab_servers alias
  community.general.opnsense_firewall_alias:
    api_key: "{{ opnsense_api_key }}"
    api_secret: "{{ opnsense_api_secret }}"
    url: "https://10.10.10.1"
    name: lab_servers
    type: network
    content:
      - "10.10.10.0/24"
    state: present
```

Generate an API key at: **System → Access → Users → (user) → API keys → Add**.

---

## IDS/IPS Setup (Suricata)

OPNsense includes Suricata IDS/IPS natively. To enable it:

1. Navigate to **Services → Intrusion Detection → Administration**
2. Check **Enabled**
3. Set **IPS mode** if you want active blocking (inline mode); leave unchecked for detection only
4. Under **Download**, click **Enable** next to `ET open` (Emerging Threats Open Rules — free)
5. Click **Download & Update Rules**
6. Navigate to **Services → Intrusion Detection → Administration → Rules** — rules are now listed
7. Click **Apply** to activate

Monitor alerts at **Services → Intrusion Detection → Alerts**.

---

## Optional: VLAN Setup

OPNsense supports 802.1Q VLANs for additional lab segmentation (e.g., a management VLAN, a DMZ). To add a VLAN:

1. **Interfaces → Other Types → VLAN** → Add
2. Parent interface: `vtnet1` (LAN), VLAN tag: e.g. `20`, Description: `mgmt`
3. Assign it: **Interfaces → Assignments** → add the new VLAN interface
4. Configure its IP, enable DHCP or use static assignments

This mirrors the pfSense VLAN workflow described in `infrastructure/vms/pfsense/README.md`.

---

## Verification

From any lab VM (e.g., lab-dc01 at `10.10.10.10`):

```powershell
# Ping the gateway
ping 10.10.10.1

# Ping an external IP (tests NAT)
ping 8.8.8.8

# DNS resolution test (tests DC → OPNsense → upstream DNS chain)
nslookup google.com 10.10.10.10
```

From the Proxmox host shell:

```bash
# Confirm OPNsense is the only holder of 10.10.10.1
ip addr show vmbr1   # should show no inet address
ping -c 3 10.10.10.1  # should reach OPNsense
```

---

## Relevant Files

| Path | Purpose |
|---|---|
| `infrastructure/proxmox/terraform/main.tf` | VM 107 resource (`proxmox_virtual_environment_vm.opnsense`) |
| `infrastructure/proxmox/terraform/variables.tf` | `enable_opnsense`, `opnsense_iso` variables |
| `infrastructure/proxmox/terraform/terraform.tfvars.example` | Example values for OPNsense toggles |
| `infrastructure/vms/pfsense/README.md` | pfSense equivalent guide (mutually exclusive) |
