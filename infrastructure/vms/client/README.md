# lab-client01 – Windows 11 Client Setup Guide

This document covers the setup of `lab-client01` (VM 103), a Windows 11 Enterprise Evaluation client used for testing SCCM management, software deployment, and Intune co-management.

---

## Prerequisites

- VM 103 has been created by Terraform
- `lab-dc01` is running and the `lab.local` domain is available
- `lab-sccm01` is running and SCCM is configured (for SCCM client push)

---

## Step 1 – Install Windows 11 Enterprise

1. Start VM 103: `qm start 103`
2. Open the Proxmox console
3. Boot from the Windows 11 Enterprise Evaluation ISO (IDE2)
4. Proceed through setup:
   - Select region, keyboard layout
   - When prompted "How would you like to set up?" — choose **Set up for work or school** (for domain join) or **Set up for personal use** (then domain-join manually)
   - If setting up offline, press **Shift+F10** at the login screen and run: `oobe\bypassnro.cmd` to skip the Microsoft account requirement
5. Complete setup and create a local account

### VirtIO Network Driver

After installation, the network adapter may not work. Install the VirtIO driver:

1. Open Device Manager → Other devices or Network adapters
2. Right-click the unrecognized device → Update driver → Browse my computer
3. Browse the VirtIO ISO (second CD drive) → `NetKVM\w11\amd64\`
4. Install the **Red Hat VirtIO Ethernet Adapter** driver

---

## Step 2 – Configure IP Address

**Option A – DHCP (recommended for easy setup)**

Leave the IP as DHCP. The DC's DHCP server will assign an address from the `10.10.10.100–200` range. Verify with:
```powershell
ipconfig /all
# Should show 10.10.10.1xx, gateway 10.10.10.1, DNS 10.10.10.10
```

**Option B – Static IP**

If you prefer a fixed IP for the client:
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.50 `
    -PrefixLength 24 -DefaultGateway 10.10.10.1

Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.10.10.10
```

---

## Step 3 – Join the Domain

```powershell
# From an elevated PowerShell on lab-client01
Add-Computer -DomainName "lab.local" `
             -OUPath "OU=Clients,DC=lab,DC=local" `
             -Credential (Get-Credential) `
             -Restart
```

Use `LAB\Administrator` credentials when prompted. The VM will restart after joining.

Alternatively, through the GUI:
1. Settings → System → About → Advanced system settings → Computer Name → Change
2. Select "Domain" and enter `lab.local`
3. Provide domain credentials and restart

---

## Step 4 – Install SCCM Client

### Option A – Client Push from SCCM Console (Recommended)

1. On lab-sccm01, open the **Configuration Manager Console**
2. Go to **Assets and Compliance → Devices**
3. If lab-client01 does not appear, run **Active Directory System Discovery** first
4. Right-click `LAB-CLIENT01` → **Install Client**
5. Follow the wizard — use push installation
6. Monitor in **Monitoring → System Status → Component Status → SMS_CLIENT_CONFIG_MANAGER**

For client push to work, the following must be open on the client:
- Windows Firewall: File and Printer Sharing (admin$ share must be accessible)
- Remote Registry service running: `Start-Service RemoteRegistry; Set-Service RemoteRegistry -StartupType Automatic`

Enable admin shares from an elevated PowerShell on the client:
```powershell
# Ensure admin$ is accessible
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWORD

# Start RemoteRegistry
Start-Service RemoteRegistry
Set-Service RemoteRegistry -StartupType Automatic

# Verify File and Printer Sharing firewall rule is enabled
Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True
```

### Option B – Manual Client Installation

If push install fails, install the SCCM client manually:

1. On lab-sccm01, the client installer is at:
   `C:\Program Files\Microsoft Configuration Manager\Client\ccmsetup.exe`
2. Copy this folder to the client (via UNC path or USB)
3. Run on the client:
   ```cmd
   ccmsetup.exe /mp:lab-sccm01.lab.local SMSMP=lab-sccm01.lab.local SMSSITECODE=LAB
   ```
4. Monitor installation: `Get-Content "C:\Windows\ccmsetup\logs\ccmsetup.log" -Wait`

---

## Step 5 – Verify SCCM Client

After client installation completes:

1. Check in SCCM Console → Assets and Compliance → Devices
2. The client should show **Yes** under "Client" column
3. On the client, check Configuration Manager in Control Panel
4. Run a full machine policy retrieval:
   - Open **Configuration Manager** in Control Panel → Actions tab
   - Run "Machine Policy Retrieval & Evaluation Cycle"

---

## Step 6 – Enroll in Intune (Optional, for Co-management Testing)

For testing Intune policies alongside SCCM:

### Prerequisites
- Azure AD (Entra ID) tenant with Intune licenses
- Hybrid Azure AD Join configured on `lab.local` (requires Azure AD Connect)
- Co-management enabled in SCCM (see lab-sccm01 guide)

### Steps

1. Verify Hybrid Azure AD Join status:
   ```cmd
   dsregcmd /status
   # Look for: AzureAdJoined: YES, DomainJoined: YES
   ```

2. If Hybrid Azure AD Join is not working, troubleshoot with:
   ```cmd
   dsregcmd /debug
   ```

3. After Hybrid Azure AD Join, MDM enrollment happens automatically if configured via Group Policy or Intune auto-enrollment policy

4. Verify Intune enrollment:
   ```powershell
   Get-ScheduledTask | Where-Object { $_.TaskName -like "*Enroll*" }
   # Or check: Settings → Accounts → Access work or school
   ```

---

## Useful Testing Scenarios

Once the client is managed by SCCM (and optionally Intune):

- **Software deployment**: Create an application in SCCM, deploy to the Clients collection
- **Compliance baseline**: Create a compliance baseline and deploy to the Clients collection
- **OSD (OS Deployment)**: Create a task sequence, deploy to the Clients collection
- **Patch management**: Deploy software updates via WSUS/SCCM Software Update Point
- **Intune co-management**: Move compliance policies workload to Intune, verify policy application
- **Remote control**: Use SCCM remote tools to connect to the client

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Client does not appear in SCCM | Run AD System Discovery in SCCM, check boundary configuration |
| Client push fails | Enable admin$, check firewall, verify svc-sccm has local admin on client |
| Client shows as offline | Check that SCCM management point is reachable from client (port 80/443 to lab-sccm01) |
| Co-management not working | Verify Hybrid Azure AD Join status with `dsregcmd /status` |
| DHCP address not received | Check that DC DHCP scope is active and authorized |
