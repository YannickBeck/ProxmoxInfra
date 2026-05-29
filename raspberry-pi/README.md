# Raspberry Pi Gateway

The Raspberry Pi acts as an always-on gateway providing two key capabilities:

1. **ZeroTier VPN node** — keeps an encrypted tunnel open so you can reach your home lab from anywhere
2. **Wake-on-LAN proxy** — sends WOL magic packets to power on the Proxmox host on demand

---

## Hardware Requirements

| Item | Minimum | Recommended |
|---|---|---|
| Model | Raspberry Pi 3B+ | Raspberry Pi 4 (2 GB+ RAM) |
| Storage | 8 GB microSD | 16 GB+ microSD (Class 10 / A1) |
| Network | Ethernet | Wired Ethernet (not WiFi — more reliable for WOL) |
| Power | 5V/2.5A | Official Raspberry Pi USB-C power supply |

---

## Operating System

**Raspberry Pi OS Lite 64-bit** (no desktop environment needed)

Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/):
1. Click the gear icon (advanced settings) before flashing
2. Set hostname: `raspi-lab` (or your preference)
3. Enable SSH
4. Set username: `pi`, password: your choice
5. Configure WiFi only if Ethernet is not available

---

## Network Configuration

| Interface | Address | Notes |
|---|---|---|
| eth0 (home LAN) | 192.168.1.200 | Static; same subnet as Proxmox host |
| ZeroTier (zt...) | 172.22.0.1 | Assigned in ZeroTier Central |

Set a static IP by editing `/etc/dhcpcd.conf`:
```
interface eth0
static ip_address=192.168.1.200/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1
```

Or reserve the IP in your home router's DHCP settings using the Raspi's MAC address.

---

## Role and Services

| Service | Description |
|---|---|
| `zerotier-one` | ZeroTier VPN daemon; provides remote access |
| `wol-api` | Flask REST API to send WOL packets via HTTP (port 8080) |
| `wakeonlan` / `etherwake` | CLI tools for sending WOL magic packets |

---

## Automated Setup

The `setup.sh` script in this directory installs and configures all services automatically:

```bash
# On the Raspberry Pi (via SSH)
git clone <repo-url> ~/ProxmoxInfra
cd ~/ProxmoxInfra/raspberry-pi
chmod +x setup.sh
sudo ./setup.sh
```

The script is **idempotent** — safe to run multiple times. It checks for existing installations before installing.

During the script you will be prompted for:
1. **ZeroTier Network ID** — the 16-character ID from my.zerotier.com
2. **Proxmox host MAC address** — for WOL (e.g., `aa:bb:cc:dd:ee:ff`)
3. **WOL API key** — a secret string to protect the HTTP WOL endpoint

After the script completes, you must:
- **Authorize the Raspi** in ZeroTier Central: https://my.zerotier.com → your network → Members
- Assign it the managed IP `172.22.0.1` in ZeroTier Central

---

## Directory Structure

```
raspberry-pi/
├── README.md           # This file
├── setup.sh            # Automated setup script
├── zerotier/
│   └── README.md       # ZeroTier account setup and config guide
└── wake-on-lan/
    ├── README.md       # WOL explanation and usage
    ├── wol.sh          # CLI script for sending WOL magic packets
    ├── wol-api.py      # Flask REST API for remote WOL
    └── wol-api.service # systemd unit file for the WOL API
```

---

## Quick Reference

```bash
# Check ZeroTier status
sudo zerotier-cli status
sudo zerotier-cli listpeers

# Check ZeroTier network
sudo zerotier-cli listnetworks

# Send WOL packet (CLI)
~/ProxmoxInfra/raspberry-pi/wake-on-lan/wol.sh

# Send WOL via API (from another ZeroTier peer)
curl -X POST http://172.22.0.1:8080/wake \
     -H "X-API-Key: your_api_key" \
     -H "Content-Type: application/json"

# Check WOL API service
sudo systemctl status wol-api
```
