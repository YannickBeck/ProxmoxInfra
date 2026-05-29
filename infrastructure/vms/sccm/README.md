# lab-sccm01 – SCCM + SQL Server Setup Guide

This document covers the manual and semi-automated steps to configure `lab-sccm01` (VM 102) as a Microsoft System Center Configuration Manager (SCCM) Current Branch server with SQL Server.

---

## Prerequisites

Before starting SCCM setup, ensure:

- [ ] **lab-dc01 is running** and the `lab.local` domain is available
- [ ] DNS resolution works from this VM (`Resolve-DnsName lab.local`)
- [ ] VM 102 has been created by Terraform and Windows Server 2022 is installed
- [ ] VirtIO network driver is installed
- [ ] This VM has **internet access** during setup (SCCM Setup downloads prerequisites)

---

## Step 1 – Install Windows Server 2022

Same process as lab-dc01:
1. Boot VM 102 from the Windows Server 2022 ISO
2. Select **Windows Server 2022 Standard (Desktop Experience)**
3. Load the VirtIO SCSI driver from the VirtIO ISO to see the disk
4. Complete installation and set the Administrator password

---

## Step 2 – Run the Prerequisites Script

Copy `setup-sccm-prereqs.ps1` to the SCCM VM and run it:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-sccm-prereqs.ps1 -DomainJoinCredential (Get-Credential)
```

The script:
1. Renames the computer to `LAB-SCCM01`
2. Sets static IP `10.10.10.20/24`
3. Joins the `lab.local` domain
4. Installs all required Windows features for SCCM
5. Creates the `C:\SCCM_Sources` staging directory

---

## Step 3 – Install SQL Server

SCCM requires SQL Server installed before running SCCM Setup.

**Recommended**: SQL Server 2019 or 2022 Evaluation

1. Download SQL Server Evaluation: https://www.microsoft.com/en-us/evalcenter/evaluate-sql-server-2022
2. Mount the ISO or copy the installation files to `C:\SCCM_Sources\SQLServer\`
3. Run `setup.exe` and select **New SQL Server standalone installation**
4. Choose these features: **Database Engine Services** (and optionally Management Tools)
5. Instance name: `MSSQLSERVER` (default instance — SCCM supports this)
6. Service accounts: use `LAB\svc-sccm` for SQL Server and SQL Agent services
7. Collation: **SQL_Latin1_General_CP1_CI_AS** (required by SCCM)
8. Data directories: point to the second disk (`D:\` if visible, otherwise configure after SQL install)

After SQL installs, configure the SQL Server max memory to leave ~2 GB for the OS:
```sql
-- In SQL Server Management Studio or sqlcmd
EXEC sp_configure 'max server memory (MB)', 6144;
RECONFIGURE;
```

---

## Step 4 – Extend Active Directory Schema for SCCM

SCCM requires a one-time AD schema extension. Run this from the **SCCM server** as a **Schema Admin** (domain admin in lab.local is sufficient):

```powershell
# Assuming SCCM setup files are at C:\SCCM_Setup\
C:\SCCM_Setup\SMSSETUP\BIN\X64\extadsch.exe
```

Or use the SCCM Setup wizard which offers to extend the schema.

---

## Step 5 – Download and Stage SCCM Current Branch

1. Download SCCM CB Evaluation:
   https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager
2. Extract/copy the setup files to `C:\SCCM_Sources\SCCM_Setup\`

---

## Step 6 – Download Windows ADK and WinPE Add-on

SCCM Setup requires the Windows Assessment and Deployment Kit (ADK):

1. Download ADK for Windows 11:
   https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
2. Install ADK with at least these features:
   - Deployment Tools
   - Windows Preinstallation Environment (PE) — via the WinPE Add-on
3. Download the WinPE Add-on separately from the same page and install it

Install to the default path: `C:\Program Files (x86)\Windows Kits\10\`

---

## Step 7 – Run SCCM Setup

1. Launch `C:\SCCM_Sources\SCCM_Setup\splash.hta` (or `Setup.exe`)
2. Select **Install a Configuration Manager primary site**
3. Accept license terms and provide your evaluation product key (or leave blank for evaluation)
4. **Prerequisite Downloads**: let it download to `C:\SCCM_Sources\Prereqs\` (requires internet ~1–3 GB)
5. Configure the site:
   - **Site code**: `LAB`
   - **Site name**: `Lab Demo`
   - **Installation folder**: `C:\Program Files\Microsoft Configuration Manager\`
6. **Database**: SQL Server `LAB-SCCM01\MSSQLSERVER` (or just `LAB-SCCM01` for default instance)
7. **SMS Provider**: `LAB-SCCM01`
8. **Client communication settings**: use HTTP (easier for lab; use HTTPS/PKI for production)
9. Complete the wizard

Setup takes 30–60 minutes. Monitor progress in `C:\ConfigMgrSetup.log`.

---

## Step 8 – Post-Install Configuration

After SCCM setup completes, configure these essentials:

### Boundaries and Boundary Group

1. Open **Configuration Manager Console** → Administration → Hierarchy Configuration → Boundaries
2. Add IP Subnet boundary: `10.10.10.0/24`
3. Create a **Boundary Group** called `Lab-BG`:
   - Add the boundary
   - Assign `LAB-SCCM01` as the site system server

### Discovery Methods

Enable and configure:
- **Active Directory System Discovery**: points to `LDAP://DC=lab,DC=local`
- **Active Directory User Discovery**: same path
- **Heartbeat Discovery**: keep enabled

### Client Settings

The default client settings are adequate for lab use. To test co-management with Intune, enable the **Co-management** settings in Client Settings.

### WSUS / Software Update Point (Optional)

If you want to test Windows Update management:
1. Install the WSUS role on lab-sccm01 (or a separate server)
2. Add the Software Update Point role in the SCCM console
3. WSUS uses port 8530 (HTTP) or 8531 (HTTPS)

---

## Step 9 – SCCM Client on lab-client01

Once SCCM is set up, push the client to lab-client01:

1. In the SCCM console → Assets and Compliance → Devices
2. Discover lab-client01 (run AD System Discovery)
3. Right-click lab-client01 → **Install Client** → use push installation
4. Monitor installation in **Monitoring → Client Status**

---

## Intune Co-management (Optional)

To configure co-management between SCCM and Microsoft Intune:

1. You need an **Azure AD (Entra ID) tenant** with Intune licenses (or Microsoft 365 E3/E5)
2. Configure **Hybrid Azure AD Join** for your devices (requires Azure AD Connect or cloud sync on the DC)
3. In the SCCM console → Administration → Cloud Services → **Co-management** → Enable
4. Set the workloads to pilot (e.g., Compliance Policies to Intune, everything else to SCCM)
5. On lab-client01, verify enrollment with: `dsregcmd /status`

---

## Troubleshooting

| Issue | Solution |
|---|---|
| SCCM Setup fails prerequisite check | Check `C:\ConfigMgrSetup.log` for details |
| SQL collation wrong | Reinstall SQL with `SQL_Latin1_General_CP1_CI_AS` collation |
| ADK not found | Verify ADK is installed at the expected path |
| Client push fails | Ensure File and Printer Sharing is enabled and admin$ share exists on client |
| Discovery finds no systems | Check SCCM service account (svc-sccm) has read access to AD |
