# ZeroTier – Remote Access Setup

ZeroTier creates an encrypted, peer-to-peer Software Defined Network (SDN) that lets you securely access your home lab from anywhere, as if your devices were on the same local network.

---

## Concepts

- **ZeroTier Network**: A virtual Ethernet network identified by a 16-character hex Network ID
- **Node**: Any device running ZeroTier (Raspberry Pi, workstation, phone)
- **Authorization**: Every node that joins must be manually authorized by you in ZeroTier Central
- **Managed IP**: A virtual IP assigned to each node within the ZeroTier network range

---

## Step 1 – Create a ZeroTier Account and Network

1. Go to https://my.zerotier.com
2. Sign up for a free account (free tier supports up to 25 devices)
3. Click **Create A Network**
4. A new private network is created with a random 16-character Network ID, e.g.:
   ```
   a09acf0233abcdef
   ```
5. **Save this Network ID** — you need it on every device you want to connect

### Network Settings

In ZeroTier Central, on your network page:
- **Access Control**: Private (recommended — each node must be authorized manually)
- **Managed Routes**: Add `172.22.0.0/16` with no gateway (or let ZeroTier auto-assign)
- **IPv4 Auto-Assign**: Enable and set the pool to `172.22.0.1` – `172.22.0.254`

---

## Step 2 – Install ZeroTier on the Raspberry Pi

The `setup.sh` script in the parent directory handles this automatically. If you want to install manually:

```bash
# Official install script (works on Linux ARM and x86)
curl -s https://install.zerotier.com | sudo bash

# Or install via apt after adding the repo (see zerotier.com/download for current GPG key)
```

After installation, the `zerotier-one` service starts automatically:
```bash
sudo systemctl status zerotier-one
```

---

## Step 3 – Join the Network

```bash
# Replace with your actual 16-character Network ID
sudo zerotier-cli join a09acf0233abcdef
```

Output: `200 join OK`

---

## Step 4 – Authorize the Raspberry Pi in ZeroTier Central

1. Go to https://my.zerotier.com → click your network
2. Scroll to the **Members** section
3. Find the Raspi's node ID (shown in `sudo zerotier-cli info`)
4. Check the **Auth** checkbox to authorize the device
5. In the **Managed IPs** column, click the `+` button and enter: `172.22.0.1`
6. The Raspi will receive its ZeroTier IP within a few seconds

Verify:
```bash
sudo zerotier-cli listnetworks
# Should show: <network_id>  OK  PRIVATE  172.22.0.1
```

---

## Step 5 – Install ZeroTier on Your Workstation

Download from: https://www.zerotier.com/download/

| OS | Method |
|---|---|
| Windows | Download and run the MSI installer |
| macOS | Download and run the PKG installer |
| Linux | `curl -s https://install.zerotier.com \| sudo bash` |
| iOS/Android | Install from App Store / Google Play |

After installing, join the same network:
```bash
# Linux / macOS terminal (or via the system tray icon on Windows)
sudo zerotier-cli join a09acf0233abcdef
```

Then authorize the workstation in ZeroTier Central and assign it the managed IP `172.22.0.2`.

---

## Verifying Connectivity

After both devices are authorized and have managed IPs:

```bash
# From your workstation — ping the Raspi
ping 172.22.0.1

# SSH to the Raspi over ZeroTier
ssh pi@172.22.0.1

# Test WOL API
curl http://172.22.0.1:8080/status
```

---

## Suggested Managed IP Assignments

Configure these in ZeroTier Central → Members → Managed IPs:

| Device | Managed IP |
|---|---|
| Raspberry Pi | 172.22.0.1 |
| Workstation | 172.22.0.2 |
| Proxmox Host (optional) | 172.22.0.3 |
| Laptop (optional) | 172.22.0.4 |
| Mobile phone (optional) | 172.22.0.5 |

---

## Checking ZeroTier Status

```bash
# On the Raspberry Pi
sudo zerotier-cli status          # Overall status and node ID
sudo zerotier-cli listnetworks    # Networks joined and their status
sudo zerotier-cli listpeers       # Connected peers
sudo zerotier-cli info            # Version and node ID

# Service management
sudo systemctl status zerotier-one
sudo systemctl restart zerotier-one
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Node not appearing in ZeroTier Central | Wait up to 60 seconds; check `zerotier-cli status` shows `ONLINE` |
| Cannot ping other ZeroTier nodes | Ensure both nodes are authorized and have managed IPs |
| ZeroTier shows `OFFLINE` | Check internet connection; ZeroTier requires outbound UDP port 9993 |
| "Not authorized" in listnetworks | Go to ZeroTier Central and authorize the node |
| SSH connection refused | Ensure SSH is enabled on the Raspi and firewall allows port 22 |
