# Architecture – ProxmoxInfra Windows Lab

This document describes the physical and virtual architecture of the ProxmoxInfra lab environment.

---

## Physical Layer

| Component | Description |
|---|---|
| Proxmox Host | A desktop or small-form-factor PC running Proxmox VE 8.x. Connected to the home router via a wired Ethernet NIC. |
| Home Router | Standard home/SOHO router providing DHCP and internet access on 192.168.1.0/24 |
| Raspberry Pi | Raspberry Pi 4 (2 GB+ RAM), running Raspberry Pi OS Lite 64-bit. Always powered on, connected to the home router via Ethernet. Serves as a ZeroTier VPN endpoint and WOL proxy. |

### Physical Network

```
Internet
   |
[Home Router] 192.168.1.1
   |  (192.168.1.0/24 — home LAN)
   +------[Proxmox Host] 192.168.1.100  (vmbr0: home LAN bridge)
   |
   +------[Raspberry Pi] 192.168.1.200  (static, always on)
```

---

## Virtual Layer

All lab VMs run on the Proxmox host and communicate via the internal bridge `vmbr1` (10.10.10.0/24).

### VM Inventory

**Core VMs (always created):**

| VM | VMID | Hostname | OS | IP Address | Role |
|---|---|---|---|---|---|
| Domain Controller | 101 | lab-dc01 | Windows Server 2022 | 10.10.10.10 | AD DS, DNS, DHCP |
| SCCM + SQL | 102 | lab-sccm01 | Windows Server 2022 | 10.10.10.20 | SCCM CB, SQL Server 2019/2022 |
| Windows 11 Client | 103 | lab-client01 | Windows 11 Enterprise Eval | 10.10.10.50 or DHCP | Domain client, SCCM managed |

**Extension VMs (opt-in via Terraform toggle — see docs/extensions.md):**

| VM | VMID | Toggle | Hostname | IP | Role |
|---|---|---|---|---|---|
| pfSense router | 100 | `enable_pfsense` | lab-fw01 | 10.10.10.1 (LAN) | NAT internet, firewall |
| OPNsense router (recommended) | 107 | `enable_opnsense` | lab-opnsense01 | 10.10.10.1 (LAN) | NAT, firewall, VLANs, optional IDS/IPS; exclusive with pfSense |
| TrueNAS storage | 120 | `enable_nas` | lab-nas01 | 10.10.10.70 | ZFS, SMB/NFS and backup target |
| Docusaurus docs | 127 | `enable_docusaurus` | lab-docusaurus01 | 10.10.10.74 | Dedicated documentation VM in pool-nas-storage |
| Enterprise Root CA | 104 | `enable_ca` | lab-ca01 | 10.10.10.30 | AD CS PKI, SCCM certs, LDAPS |
| Secondary DC | 105 | `enable_dc02` | lab-dc02 | 10.10.10.11 | AD replication, DNS redundancy |
| Azure AD Connect | 106 | `enable_aadconnect` | lab-aadc01 | 10.10.10.40 | Entra sync, Hybrid AADJ, co-mgmt |

### VM Specifications

**Core VMs:**

| VM | vCPU | RAM | OS Disk | Data Disk(s) | Notes |
|---|---|---|---|---|---|
| lab-dc01 | 2 | 4 GB | 60 GB (SCSI) | – | Lightweight; handles DC, DNS, DHCP |
| lab-sccm01 | 4 | 8 GB | 100 GB (SCSI) | 100 GB SQL + optional WSUS disk | OS on scsi0; SQL data on scsi1; optional WSUS on scsi2 |
| lab-client01 | 2 | 4 GB | 60 GB (SCSI) | – | TPM 2.0 emulated for Win11 requirements |

**Extension VMs:**

| VM | vCPU | RAM | Disk | Notes |
|---|---|---|---|---|
| lab-fw01 | 2 | 2 GB | 16 GB | Dual-NIC: vmbr0 (WAN) + vmbr1 (LAN) |
| lab-opnsense01 | 2 | 2 GB | 20 GB | Recommended dual-NIC firewall; alternative to pfSense |
| lab-nas01 | 4 | 8 GB | 32 GB OS + configurable data disk | TrueNAS Scale and ZFS |
| lab-docusaurus01 | 2 | 4 GB | 40 GB | Ubuntu with Docker Compose |
| lab-ca01 | 2 | 4 GB | 60 GB | Enterprise Root CA, domain-joined |
| lab-dc02 | 2 | 4 GB | 60 GB | Replica DC, same specs as DC01 |
| lab-aadc01 | 2 | 4 GB | 60 GB | Member server, needs internet (pfSense) |

---

## Network Bridges

### vmbr0 – WAN / Home LAN Bridge

- **Type**: Linux bridge with uplink (physical NIC)
- **IP on Proxmox host**: 192.168.1.100/24 (assigned by home router DHCP, ideally reserved)
- **Purpose**: Gives the Proxmox management UI its IP address. Can optionally be attached to VMs that need internet access (e.g., SCCM during setup for prerequisite downloads).
- **No VMs** are connected to vmbr0 by default to keep the lab isolated.

### vmbr1 – Lab Internal Bridge

- **Type**: Linux bridge with **no uplink** (isolated — no physical NIC attached)
- **IP on Proxmox host**: 10.10.10.1/24 (acts as default gateway for lab VMs)
- **CIDR**: 10.10.10.0/24
- **Purpose**: Isolated lab network. All three VMs attach here. Traffic never leaves the Proxmox host.
- **Internet access**: Not available by default. For SCCM setup requiring internet, add an `iptables` masquerade rule on the Proxmox host temporarily:
  ```bash
  iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
  echo 1 > /proc/sys/net/ipv4/ip_forward
  ```

---

## ZeroTier Overlay Network

ZeroTier creates a software-defined Layer 2 network over the internet:

- **Network range**: 172.22.0.0/16 (typical ZeroTier-assigned range; actual range set in ZeroTier Central)
- **Raspberry Pi ZT IP**: 172.22.0.1
- **Workstation ZT IP**: 172.22.0.2
- **Proxmox host ZT IP** (optional): 172.22.0.3 (if ZeroTier is also installed on Proxmox host for direct access)

Traffic flow for remote lab access:
```
Workstation (172.22.0.2)
   |
   | ZeroTier encrypted tunnel
   |
Raspberry Pi (172.22.0.1)
   |
   | Home LAN (192.168.1.0/24)
   |
Proxmox Host (192.168.1.100)
   |
   | Internal bridge (vmbr1 10.10.10.0/24)
   |
Lab VMs (10.10.10.10, .20, .50)
```

---

## Service Dependencies

The lab services have the following dependency chain. Always start them in this order:

```
lab-dc01 (must be fully booted and AD domain ready)
    |
    +-- lab-sccm01 depends on:
    |       - AD domain (lab.local) reachable at 10.10.10.10
    |       - DNS resolution working (DC is DNS server)
    |       - Domain join completed before SQL/SCCM install
    |
    +-- lab-client01 depends on:
            - AD domain for domain join
            - SCCM site server for client push installation
```

---

## Startup Order

When powering on the lab from scratch:

1. **Wake Proxmox host** (via WOL from Raspberry Pi or power button)
2. **Start the selected firewall** (VM 107 OPNsense or VM 100 pfSense, if deployed) and wait for it to be ready
3. **Start lab-nas01** (VM 120, if deployed): `qm start 120`
4. **Start lab-dc01** (VM 101): `qm start 101` — wait ~3–5 min for AD services
5. **Start lab-dc02** (VM 105, if deployed): `qm start 105`
6. **Start lab-ca01** (VM 104, if deployed): `qm start 104`
7. **Start lab-sccm01** (VM 102): `qm start 102` — wait ~5–10 min for SQL + SCCM services
8. **Start lab-aadc01** (VM 106, if deployed): `qm start 106`
9. **Start lab-client01** (VM 103): `qm start 103`
10. **Start lab-docusaurus01** (VM 127, if deployed): `qm start 127`

Shutdown order (reverse):
```bash
qm shutdown 103   # client first
qm shutdown 127   # documentation VM
qm shutdown 106   # Azure AD Connect
qm shutdown 102   # SCCM + SQL
qm shutdown 104   # CA
qm shutdown 105   # DC02
qm shutdown 101   # Primary DC last
qm shutdown 120   # NAS after its consumers
qm shutdown 107   # OPNsense (use VM 100 instead when pfSense is selected)
shutdown -h now   # Proxmox host
```
