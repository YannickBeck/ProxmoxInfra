# lab-dc01 – Domain Controller Setup Guide

This document covers the manual and automated steps to configure `lab-dc01` (VM 101) as an Active Directory Domain Controller for the `lab.local` domain.

---

## Prerequisites

- VM 101 has been created by Terraform
- Windows Server 2022 Desktop Experience is installed
- VirtIO network driver is installed (so the VM has network connectivity)
- VM is accessible via the Proxmox console or RDP

---

## Step 1 – Boot from ISO and Install Windows Server 2022

1. Start VM 101 from the Proxmox UI or: `qm start 101`
2. Open the console (Proxmox UI → VM → Console)
3. Boot from the Windows Server 2022 ISO (IDE2)
4. Select **Windows Server 2022 Standard (Desktop Experience)** when prompted
5. On the "Where to install Windows" screen:
   - Click **Load driver**
   - Browse the VirtIO ISO (IDE3) → `vioscsi\2k22\amd64\`
   - Load the **Red Hat VirtIO SCSI controller** driver
   - The 60 GB disk should now appear — select it and continue
6. Complete the installation, set the initial Administrator password when prompted

---

## Step 2 – Post-Install: Network Driver

After Windows installs and restarts, the network adapter will show as unrecognized in Device Manager. Install the VirtIO network driver:

1. Open Device Manager → Network adapters → right-click the unknown device → Update driver
2. Browse the VirtIO ISO (`D:\` or `E:\`) → `NetKVM\2k22\amd64\`
3. Install the **Red Hat VirtIO Ethernet Adapter** driver
4. The NIC should now show as connected

---

## Step 3 – Set Static IP

Open an elevated PowerShell and run (or use the setup-dc.ps1 script):

```powershell
# Find the network adapter
Get-NetAdapter

# Set static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.10 `
    -PrefixLength 24 -DefaultGateway 10.10.10.1

# Set DNS to loopback (DC will be its own DNS server after AD install)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
```

---

## Step 4 – Run the Setup Script

Copy `setup-dc.ps1` to the DC VM (via shared folder, USB, or PowerShell remoting) and run it in an elevated PowerShell session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-dc.ps1
```

The script performs:
1. Renames the computer to `LAB-DC01` and restarts
2. Sets the static IP `10.10.10.10/24`
3. Installs the AD DS, DNS, and DHCP Windows features
4. Promotes the server to a Domain Controller for `lab.local`
5. **Reboots** — log back in after reboot
6. Configures the DHCP scope (10.10.10.100–200)
7. Authorizes the DHCP server in Active Directory
8. Creates the following Organizational Units:
   - `OU=Servers,DC=lab,DC=local`
   - `OU=Clients,DC=lab,DC=local`
   - `OU=ServiceAccounts,DC=lab,DC=local`
9. Creates a service account: `LAB\svc-sccm` (used by SCCM)

---

## Step 5 – What the DC Setup Does (Detail)

### Active Directory Domain Services

- Domain: `lab.local`
- Domain functional level: Windows Server 2016
- Forest functional level: Windows Server 2016
- Promotes the server to the **first DC** in a new forest

### DNS

- AD-integrated DNS zone for `lab.local`
- Reverse lookup zone for `10.10.10.x`
- Forwarder: set to `10.10.10.1` (Proxmox host) for internet name resolution

### DHCP

- Scope: `LabScope` — range `10.10.10.100` to `10.10.10.200`
- Subnet mask: `255.255.255.0`
- Default gateway: `10.10.10.1`
- DNS server: `10.10.10.10`
- Domain name: `lab.local`
- Server authorized in AD (required for DHCP to serve leases)

### Organizational Units

```
lab.local
├── OU=Servers          ← For Server computer accounts (DC, SCCM)
├── OU=Clients          ← For client computer accounts (Win11)
└── OU=ServiceAccounts  ← For service accounts (svc-sccm, etc.)
```

### Service Account

- Username: `svc-sccm`
- OU: `OU=ServiceAccounts,DC=lab,DC=local`
- Used by SCCM for AD discovery and site operations
- Password set in the script — change it to a strong password before use

---

## Step 6 – Validate the Setup

After the script completes:

```powershell
# Check AD domain
Get-ADDomain

# Check DNS
Resolve-DnsName lab.local

# Check DHCP scope
Get-DhcpServerv4Scope

# Check OUs
Get-ADOrganizationalUnit -Filter *

# Check service account
Get-ADUser -Identity svc-sccm
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| No disk visible during Windows install | Load VirtIO SCSI driver from the VirtIO ISO during setup |
| No network after install | Install VirtIO NetKVM driver from Device Manager |
| Cannot promote to DC | Ensure Windows features are installed first (AD DS role) |
| DHCP server not authorised | Run `Add-DhcpServerInDC -DnsName lab-dc01.lab.local` |
| DNS not resolving lab.local from other VMs | Ensure other VMs use 10.10.10.10 as DNS server |
