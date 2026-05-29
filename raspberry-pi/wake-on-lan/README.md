# Wake-on-LAN Guide

Wake-on-LAN (WOL) allows the Raspberry Pi to remotely power on the Proxmox host by sending a "magic packet" over the network — even when the host is fully powered off (as long as the NIC remains powered via standby).

---

## How Magic Packets Work

A WOL magic packet is a broadcast UDP datagram containing:
- A synchronization stream of 6 bytes of `0xFF`
- The target NIC's MAC address repeated 16 times

Most NICs and motherboards can receive and act on this packet when the system is in S5 (soft-off) state, provided:
- WOL is enabled in BIOS/UEFI
- The NIC remains powered (via ATX standby 5V)
- The OS has not disabled WOL in the NIC driver settings

---

## Prerequisites

### On the Proxmox Host (one-time setup)

1. **Enable WOL in BIOS/UEFI**:
   - Restart the Proxmox host and enter BIOS (usually Del, F2, or F10 at POST)
   - Look for settings like:
     - "Wake on LAN" → Enabled
     - "Power On by PCI-E" → Enabled
     - "ErP Power Saving" or "EuP" → **Disabled** (this disables WOL if enabled)
   - Save and exit

2. **Note the Proxmox NIC MAC address**:
   ```bash
   # On Proxmox host
   ip link show
   # Example: 2: enp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP>
   #              link/ether aa:bb:cc:dd:ee:ff
   ```

3. **Optional: prevent NIC from disabling WOL in Linux**:
   ```bash
   # Check WOL status
   ethtool enp3s0 | grep "Wake-on"
   # Wake-on: g  (means magic packet is enabled)
   
   # If WOL is showing 'd' (disabled), enable it:
   ethtool -s enp3s0 wol g
   
   # Make persistent via /etc/network/interfaces or a systemd service
   ```

### On the Raspberry Pi

The `setup.sh` script installs `wakeonlan` and `etherwake` and saves the Proxmox MAC address to `/etc/wol/proxmox.conf`.

If you need to set it manually:
```bash
sudo mkdir -p /etc/wol
echo "MAC=aa:bb:cc:dd:ee:ff" | sudo tee /etc/wol/proxmox.conf
sudo chmod 600 /etc/wol/proxmox.conf
```

---

## Sending WOL from the CLI (wol.sh)

The `wol.sh` script reads the MAC address from `/etc/wol/proxmox.conf` and sends a magic packet:

```bash
# Using saved MAC address
./wol.sh

# Override with a specific MAC address
./wol.sh aa:bb:cc:dd:ee:ff
```

The script tries `wakeonlan` first, falls back to `etherwake`.

---

## Sending WOL via HTTP API (wol-api.py)

The `wol-api.py` Flask application provides a REST API so you can trigger WOL from anywhere on the ZeroTier network:

### Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/status` | Health check |
| POST | `/wake` | Send WOL to the saved Proxmox MAC |
| POST | `/wake` with JSON body | Send WOL to a custom MAC |

### Authentication

All `POST` requests require the `X-API-Key` header. The key is stored in `/etc/wol/wol-api.env`.

### Examples

```bash
# Health check
curl http://172.22.0.1:8080/status

# Wake Proxmox host (uses saved MAC from config file)
curl -X POST http://172.22.0.1:8080/wake \
     -H "X-API-Key: your_api_key_here"

# Wake a custom MAC address
curl -X POST http://172.22.0.1:8080/wake \
     -H "X-API-Key: your_api_key_here" \
     -H "Content-Type: application/json" \
     -d '{"mac": "aa:bb:cc:dd:ee:ff"}'
```

### Service Management

```bash
# Check service status
sudo systemctl status wol-api

# View logs
sudo journalctl -u wol-api -f

# Restart service
sudo systemctl restart wol-api

# View API key
sudo grep API_KEY /etc/wol/wol-api.env
```

---

## Subnet Limitations

WOL magic packets are typically broadcast to `255.255.255.255` (limited broadcast). This only reaches devices on the **same broadcast domain** (same subnet).

In this setup:
- The Raspberry Pi is on the same home LAN subnet as the Proxmox host (`192.168.1.0/24`)
- The Raspi broadcasts the magic packet to `255.255.255.255` on its LAN interface
- The Proxmox host receives the packet and wakes up

If the Raspi and Proxmox host are on **different subnets**, you would need:
- A directed broadcast (e.g., `192.168.1.255`) routed by a WOL-capable router
- Or a relay service on the same subnet as the Proxmox host

In a typical home setup, they are on the same subnet, so this is not an issue.

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Host does not wake up | Check BIOS WOL setting; check "ErP/EuP" is disabled |
| `ethtool` shows WOL disabled | Run `ethtool -s enp3s0 wol g` on Proxmox host |
| Wrong MAC address | Verify with `ip link show` on Proxmox host; update `/etc/wol/proxmox.conf` |
| API returns 401 | Check `X-API-Key` header matches key in `/etc/wol/wol-api.env` |
| API service not running | `sudo systemctl start wol-api` and check logs: `journalctl -u wol-api` |
| Packet sent but no wake | Check that Proxmox host is fully powered off (not in sleep) — S5 state should work |
