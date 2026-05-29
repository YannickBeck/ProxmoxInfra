# Network Design – ProxmoxInfra Windows Lab

This document covers IP addressing, routing, DNS, DHCP, firewall rules, and port requirements for the lab environment.

---

## IP Address Plan

| Device | Interface | IP Address | Subnet | Notes |
|---|---|---|---|---|
| Home Router | LAN | 192.168.1.1 | 192.168.1.0/24 | Default gateway for home LAN |
| Proxmox Host | vmbr0 (home LAN) | 192.168.1.100 | 192.168.1.0/24 | Recommend reserving this in router DHCP |
| Proxmox Host | vmbr1 (lab) | 10.10.10.1 | 10.10.10.0/24 | Gateway for all lab VMs |
| lab-dc01 | vmbr1 | 10.10.10.10 | 10.10.10.0/24 | Static; set during OS post-install config |
| lab-sccm01 | vmbr1 | 10.10.10.20 | 10.10.10.0/24 | Static; set during OS post-install config |
| lab-client01 | vmbr1 | 10.10.10.50 | 10.10.10.0/24 | Static, or use DHCP (will get 10.10.10.100+) |
| Raspberry Pi | eth0 (home LAN) | 192.168.1.200 | 192.168.1.0/24 | Static; recommend reserving in router |
| Raspberry Pi | ZeroTier | 172.22.0.1 | 172.22.0.0/16 | Assigned in ZeroTier Central |
| Workstation | ZeroTier | 172.22.0.2 | 172.22.0.0/16 | Assigned in ZeroTier Central |
| Proxmox Host | ZeroTier (optional) | 172.22.0.3 | 172.22.0.0/16 | Only if ZT installed on Proxmox host |

---

## vmbr0 – WAN / Home LAN Bridge

- **Proxmox configuration**: Linux bridge with physical NIC attached (e.g., `enp3s0`)
- **IP**: Assigned by home router DHCP (recommend a DHCP reservation for the NIC's MAC)
- **Purpose**: Proxmox management interface. Not typically connected to lab VMs.
- **Internet access**: VMs can be given temporary internet access by adding them to vmbr0, but this bypasses lab isolation. Prefer using the Proxmox host as a NAT gateway when internet is needed temporarily (e.g., for SCCM setup).

---

## vmbr1 – Lab Internal Bridge

- **Proxmox configuration**: Linux bridge with **no physical NIC** (isolated)
- **IP**: `10.10.10.1/24` on the Proxmox host — acts as the default gateway for all VMs
- **No internet access by default** — keeps the lab isolated and self-contained
- All three lab VMs connect exclusively to vmbr1

Configure on Proxmox host (`/etc/network/interfaces`):
```
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    comment Lab internal 10.10.10.0/24
```

---

## DNS

The Domain Controller (lab-dc01) at `10.10.10.10` serves as the **authoritative DNS server** for:
- `lab.local` — Active Directory domain (internal zone, AD-integrated)
- Reverse lookup zone for `10.10.10.x`

All lab VMs must use `10.10.10.10` as their primary DNS server. This is set via static IP configuration on each VM.

DNS forwarding: The DC's DNS forwarder should point to `10.10.10.1` (Proxmox host) or the home router (`192.168.1.1`) for external name resolution — but only if internet access is required.

---

## DHCP

The Domain Controller runs the **Windows DHCP Server** role for the `10.10.10.0/24` subnet.

DHCP Scope configuration:
- **Scope name**: LabScope
- **Range**: 10.10.10.100 – 10.10.10.200
- **Subnet mask**: 255.255.255.0
- **Default gateway (Router option 003)**: 10.10.10.1
- **DNS Server (option 006)**: 10.10.10.10
- **Domain name (option 015)**: lab.local
- **Lease duration**: 8 days

Servers (DC and SCCM) use static IPs outside the DHCP range. The client VM can use DHCP or a static IP.

---

## ZeroTier Overlay Network

- **Network type**: Private (requires authorization of each node)
- **Managed route**: `172.22.0.0/16` via ZeroTier
- **Typical range**: 172.22.0.0/16 (actual assignment depends on what you configure in ZeroTier Central)

Node assignments (configured in ZeroTier Central → Members → Managed IPs):
- Raspberry Pi: `172.22.0.1`
- Workstation: `172.22.0.2`
- Proxmox Host (optional): `172.22.0.3`

ZeroTier does **not** expose the lab VMs directly — the Raspi serves as a jump host. For direct VM RDP access, either:
- SSH tunnel through the Raspi to the Proxmox host, then to a VM
- Add the Proxmox host to ZeroTier and configure routing rules

---

## Firewall Rules

### Proxmox Host (iptables / Proxmox Firewall)

The Proxmox host should allow:
- Port 8006 (TCP): Proxmox web UI — restrict to home LAN or ZeroTier subnet
- Port 22 (TCP): SSH — restrict to home LAN or ZeroTier subnet
- ZeroTier port 9993 (UDP): ZeroTier peer discovery (if ZT is installed on Proxmox host)
- ICMP: Allow ping from lab and home networks

Block by default: all inbound traffic from vmbr1 to the internet (vmbr0) unless explicitly added for a session.

### Raspberry Pi

- Allow port 22 (TCP): SSH from home LAN and ZeroTier
- Allow port 8080 (TCP): WOL API — restrict to ZeroTier subnet (172.22.0.0/16)
- Allow ZeroTier port 9993 (UDP): outbound

### Windows Firewall (lab VMs)

Windows Firewall is configured by the DC Group Policy. Recommended rules:
- Allow WinRM (5985/5986 TCP) from Proxmox host IP for Ansible
- Allow RDP (3389 TCP) from lab subnet (10.10.10.0/24)
- Allow ICMP echo from lab subnet
- Allow SCCM ports (see below) within lab subnet

---

## SCCM Required Ports

For SCCM (Configuration Manager) to function within the lab, the following ports must be open between lab VMs:

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| 80 | TCP | Client → SCCM | HTTP communication |
| 443 | TCP | Client → SCCM | HTTPS communication |
| 135 | TCP | SCCM → Client | RPC endpoint mapper |
| 445 | TCP | SCCM ↔ Client | SMB (file sharing, client push) |
| 2701 | TCP | SCCM → Client | Remote Control |
| 4022 | TCP | SCCM ↔ DC | SQL Service Broker (if SQL on separate host) |
| 8530 | TCP | Client → SCCM | WSUS HTTP (Windows Update) |
| 8531 | TCP | Client → SCCM | WSUS HTTPS |
| 10123 | TCP | Client → SCCM | Alternative client communication port |
| 49152–65535 | TCP | SCCM → Client | RPC dynamic ports |

Since all VMs are on the same vmbr1 subnet (10.10.10.0/24), Windows Firewall domain profile will apply (less restrictive). SCCM client push installation also requires:
- Admin$ share accessible on client
- Remote Registry service running on client
- File and Printer Sharing enabled

---

## Routing Summary

```
Workstation
172.22.0.2
    |
    | ZeroTier (encrypted, internet)
    |
Raspberry Pi
172.22.0.1 / 192.168.1.200
    |
    | Home LAN 192.168.1.0/24
    |
Proxmox Host
192.168.1.100 / 10.10.10.1
    |
    | vmbr1 (internal, no internet)
    |
Lab VMs: 10.10.10.10, .20, .50
```

No routing between ZeroTier and the lab subnet (10.10.10.0/24) by default. The Proxmox host would need to forward traffic and appropriate routes would need to be added in ZeroTier Central to enable direct ZeroTier-to-lab routing.
