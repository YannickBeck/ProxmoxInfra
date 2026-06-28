#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepare lab-cloudsync01 (VMID 109) for hybrid identity and install the
    Microsoft Entra Cloud Sync lightweight provisioning agent for
    lab.local -> Entra ID.

.DESCRIPTION
    This script provisions the dedicated Cloud Sync member server and installs
    the Entra provisioning agent. It runs in TWO passes:

      Pass 1 (machine not named LAB-CLOUDSYNC01 / not domain-joined):
        - Rename computer to LAB-CLOUDSYNC01
        - Set static IP 10.10.10.41/24, gateway 10.10.10.1
        - Set DNS to the lab DC (10.10.10.10) so the domain can be resolved
        - Join the lab.local domain
        - Reboot

      Pass 2 (machine is LAB-CLOUDSYNC01 and domain-joined, agent not installed):
        - Test internet reachability to login.microsoftonline.com:443
        - Download the Entra provisioning agent (https://aka.ms/EntraProvisioningAgent)
        - Silently install it (AADConnectProvisioningAgentSetup.exe /quiet)
        - Print the CLOUD-SIDE next steps: the agent is registered and the sync
          rules are configured entirely in the Microsoft Entra admin center
          (Identity -> Hybrid management -> Microsoft Entra Connect -> Cloud sync).

    Unlike Entra Connect Sync, Cloud Sync has **no on-box configuration wizard**.
    The agent is a thin component; all configuration (scoping, PHS, provisioning)
    lives in the cloud. This script therefore only renames/joins/installs and
    then hands you off to the portal + the AADCloudSyncTools PowerShell module.

    Every step is idempotent: re-running the script skips work that is already
    done (rename, IP, domain join, agent install).

.PARAMETER SafeIp
    Static IPv4 address for this server on vmbr1. Default 10.10.10.41.

.PARAMETER Gateway
    Default gateway (pfSense / OPNsense / Proxmox host providing NAT). Default 10.10.10.1.

.PARAMETER DnsServer
    DNS server = the lab DC (lab-dc01). Default 10.10.10.10.

.PARAMETER DomainName
    AD domain to join. Default lab.local.

.PARAMETER DomainJoinCredential
    [PSCredential] with rights to join the domain (e.g. LAB\Administrator).
    If not supplied during the join phase the script prompts with Get-Credential.
    Run as: -DomainJoinCredential (Get-Credential)

.PARAMETER DownloadDir
    Where to download the provisioning agent. Default C:\Install.

.PREREQUISITES
    - Windows Server 2022 (Desktop Experience) installed, VirtIO NIC driver present
    - lab-dc01 up and reachable; lab.local domain functioning
    - A Microsoft Entra tenant + a Hybrid Identity Administrator / Global Administrator
    - Internet access from this VM (the agent talks to Entra ID over 443)
    - .NET Framework 4.7.2+ (Server 2022 ships with this)

.EXAMPLE
    # Pass 1 (provision + domain join, then auto-reboot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\install-cloudsync.ps1 -DomainJoinCredential (Get-Credential)

.EXAMPLE
    # Pass 2 (after reboot — same command; script auto-detects the phase)
    .\install-cloudsync.ps1

.NOTES
    Repo: ProxmoxInfra — infrastructure/entra-cloudsync
    Companion guide: ..\README.md

    Cloud Sync vs Connect Sync (short version):
      - Cloud Sync (this VM 109)  = lightweight agent, cloud-side config, multiple
        disconnected forests, HA via several agents, small footprint. No device
        writeback, no SCP for Hybrid Join, OU/group-scoped filtering only.
      - Connect Sync (VM 106)     = full on-box sync engine + wizard, device/group
        writeback, SCP for Hybrid Azure AD Join, attribute-level filtering.
      You may run BOTH to compare, but do NOT sync the same objects with both.
#>

param(
    [string]$SafeIp        = "10.10.10.41",
    [string]$Gateway       = "10.10.10.1",
    [string]$DnsServer     = "10.10.10.10",
    [string]$DomainName    = "lab.local",

    [System.Management.Automation.PSCredential]
    $DomainJoinCredential,

    [string]$DownloadDir   = "C:\Install"
)

$ErrorActionPreference = "Stop"

$TargetHostname = "LAB-CLOUDSYNC01"
$SubnetPrefix   = "24"
$AgentUrl       = "https://aka.ms/EntraProvisioningAgent"
$AgentPath      = Join-Path $DownloadDir "AADConnectProvisioningAgentSetup.exe"
$AgentInstallDir = "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent"
$AgentServiceName = "AADConnectProvisioningAgent"

# -----------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

# Detect whether the provisioning agent is already installed (service OR path).
function Test-AgentInstalled {
    $svc = Get-Service -Name $AgentServiceName -ErrorAction SilentlyContinue
    if ($svc) { return $true }
    if (Test-Path $AgentInstallDir) { return $true }
    return $false
}

# -----------------------------------------------------------------------
# Phase detection
# -----------------------------------------------------------------------
$cs             = Get-CimInstance -ClassName Win32_ComputerSystem
$isCorrectName  = ($env:COMPUTERNAME -eq $TargetHostname)
$isDomainJoined = ($cs.PartOfDomain -and $cs.Domain -eq $DomainName)
$agentInstalled = Test-AgentInstalled

# We are in PHASE 2 once we are BOTH correctly named and domain-joined.
$phase2 = ($isCorrectName -and $isDomainJoined)

# =======================================================================
# PHASE 2: Server is named LAB-CLOUDSYNC01 and joined to lab.local
# =======================================================================
if ($phase2) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  PHASE 2: Entra Cloud Sync agent on $TargetHostname" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    # -- Test internet connectivity to Entra ID --
    Write-Step "Testing internet connectivity to login.microsoftonline.com:443..."
    $net = Test-NetConnection -ComputerName "login.microsoftonline.com" -Port 443 -WarningAction SilentlyContinue
    if ($net.TcpTestSucceeded) {
        Write-OK "Reached login.microsoftonline.com on 443 — Entra is reachable."
    } else {
        Write-Error "Could NOT reach login.microsoftonline.com:443."
        Write-Warning "Entra Cloud Sync REQUIRES outbound internet from this VM."
        Write-Warning "This isolated lab routes internet through the pfSense/OPNsense"
        Write-Warning "NAT gateway ($Gateway). Confirm that firewall VM is up and"
        Write-Warning "providing NAT to the WAN, or temporarily attach an internet-"
        Write-Warning "capable NIC. The agent cannot register or sync without 443."
        exit 1
    }

    # -- Skip if the agent is already installed --
    if ($agentInstalled) {
        Write-OK "Provisioning agent already installed ($AgentInstallDir) — skipping install."
    } else {
        # -- Download the Entra provisioning agent --
        Write-Step "Staging the Entra Cloud Sync provisioning agent..."
        if (-not (Test-Path $DownloadDir)) {
            New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
        }
        if (Test-Path $AgentPath) {
            Write-OK "Agent installer already downloaded: $AgentPath — skipping download."
        } else {
            Write-Host "    Downloading from $AgentUrl ..." -ForegroundColor Gray
            $oldProgress = $ProgressPreference
            $ProgressPreference = "SilentlyContinue"   # massively speeds up Invoke-WebRequest
            try {
                Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentPath -UseBasicParsing
                Write-OK "Downloaded agent installer to $AgentPath"
            } catch {
                $ProgressPreference = $oldProgress
                Write-Error "Failed to download the provisioning agent: $_"
                Write-Warning "Manually download from https://aka.ms/EntraProvisioningAgent"
                Write-Warning "and place it at $AgentPath, then re-run this script."
                exit 1
            }
            $ProgressPreference = $oldProgress
        }

        # -- Silent install --
        Write-Step "Installing the provisioning agent silently (/quiet)..."
        Start-Process -FilePath $AgentPath -ArgumentList "/quiet" -Wait
        if (Test-AgentInstalled) {
            Write-OK "Provisioning agent installed."
        } else {
            Write-Warning "Installer finished but the agent service/path was not detected."
            Write-Warning "Check $DownloadDir and the Windows Event Log; you may need to run"
            Write-Warning "$AgentPath interactively to inspect the install."
        }
    }

    # -------------------------------------------------------------------
    # NEXT STEPS — Cloud Sync is configured CLOUD-SIDE (no on-box wizard)
    # -------------------------------------------------------------------
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Agent staged. Cloud Sync is configured in the CLOUD." -ForegroundColor Green
    Write-Host "  Host: $TargetHostname.$DomainName ($SafeIp)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  IMPORTANT: Unlike Entra Connect Sync, Cloud Sync has NO on-box" -ForegroundColor Yellow
    Write-Host "  configuration wizard. You register the agent and build the sync" -ForegroundColor Yellow
    Write-Host "  configuration entirely in the Microsoft Entra admin center." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  NEXT STEPS (cloud-side):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Register the agent. The agent configuration wizard launches at" -ForegroundColor Yellow
    Write-Host "     the end of install; if it didn't, start it from:" -ForegroundColor Yellow
    Write-Host "       '$AgentInstallDir\AADConnectProvisioningAgentWizard.exe'" -ForegroundColor White
    Write-Host "     Sign in with a HYBRID IDENTITY ADMIN / GLOBAL ADMIN (expect MFA)" -ForegroundColor White
    Write-Host "     and register the agent against the lab.local forest." -ForegroundColor White
    Write-Host ""
    Write-Host "  2. In the Entra admin center, build the Cloud Sync configuration:" -ForegroundColor Yellow
    Write-Host "       Identity -> Hybrid management -> Microsoft Entra Connect ->" -ForegroundColor White
    Write-Host "       Cloud sync -> New configuration -> pick the lab.local forest." -ForegroundColor White
    Write-Host "     Set the scope (OU/group), enable Password Hash Sync, then" -ForegroundColor White
    Write-Host "     Enable the configuration to start provisioning." -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Install the AADCloudSyncTools PowerShell module for management:" -ForegroundColor Yellow
    Write-Host "       Install-Module -Name AADCloudSyncTools -Scope AllUsers" -ForegroundColor White
    Write-Host "       Import-Module AADCloudSyncTools" -ForegroundColor White
    Write-Host "       Connect-AADCloudSyncTools          # sign in to the tenant" -ForegroundColor White
    Write-Host "       Get-AADCloudSyncToolsServiceStatus # agent + service health" -ForegroundColor White
    Write-Host ""
    Write-Host "  NOTE on UPNs: lab.local is NON-ROUTABLE. As with Connect Sync, add a" -ForegroundColor Yellow
    Write-Host "  routable UPN suffix (e.g. <tenant>.onmicrosoft.com or a verified" -ForegroundColor Yellow
    Write-Host "  custom domain) in AD and stamp users BEFORE the first sync, or they" -ForegroundColor Yellow
    Write-Host "  appear in Entra as <user>@<tenant>.onmicrosoft.com. See ..\README.md." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  See infrastructure/entra-cloudsync/README.md for the full guide." -ForegroundColor Cyan

    # -- Cloud Sync vs Connect Sync helper note --
    Write-Step "Cloud Sync vs Connect Sync (which did you install?)"
    Write-Host "    This VM (109) runs the LIGHTWEIGHT Cloud Sync agent:" -ForegroundColor Gray
    Write-Host "      + small footprint, cloud-side config, multiple disconnected" -ForegroundColor Gray
    Write-Host "        forests, HA by adding more agents." -ForegroundColor Gray
    Write-Host "      - no device writeback, no SCP for Hybrid Azure AD Join, no" -ForegroundColor Gray
    Write-Host "        attribute-level filtering (OU/group scope only)." -ForegroundColor Gray
    Write-Host "    For device writeback / Hybrid Join SCP / large scenarios, use the" -ForegroundColor Gray
    Write-Host "    full Entra Connect Sync on lab-aadc01 (VM 106) instead." -ForegroundColor Gray

    # -- Verification hints --
    Write-Step "Verification (after you enable the cloud configuration)"
    Write-Host "    Agent health (portal): Entra admin center -> Cloud sync ->" -ForegroundColor Gray
    Write-Host "      your configuration -> the agent shows 'Active' / 'Healthy'." -ForegroundColor Gray
    Write-Host "    On THIS server (PowerShell):" -ForegroundColor Gray
    Write-Host "      Get-Service '$AgentServiceName'        # Running" -ForegroundColor White
    Write-Host "      Get-AADCloudSyncToolsServiceStatus    # agent/service health" -ForegroundColor White
    Write-Host "      Export-AADCloudSyncToolsLogs          # collect provisioning logs" -ForegroundColor White
    Write-Host "    In the Entra admin center -> Users: lab.local users appear with" -ForegroundColor Gray
    Write-Host "    'On-premises sync enabled = Yes' once the first cycle runs." -ForegroundColor Gray

    exit 0
}

# =======================================================================
# PHASE 1: Rename, IP, DNS, domain join, reboot
# =======================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PHASE 1: Provision $TargetHostname" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -- Set static IP + DNS --
Write-Step "Configuring static IP $SafeIp/$SubnetPrefix (gateway $Gateway, DNS $DnsServer)..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not $adapter) {
    Write-Error "No active network adapter found. Install the VirtIO NetKVM driver first."
    exit 1
}

$existingIp = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq $SafeIp }
if ($existingIp) {
    Write-OK "Static IP $SafeIp already configured on '$($adapter.Name)'."
} else {
    # Clear any previous IPv4 config on this adapter, then set ours
    try {
        Remove-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    New-NetIPAddress -InterfaceAlias $adapter.Name `
                     -IPAddress      $SafeIp `
                     -PrefixLength   $SubnetPrefix `
                     -DefaultGateway $Gateway | Out-Null
    Write-OK "Set static IP $SafeIp/$SubnetPrefix (gateway $Gateway)."
}

Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DnsServer
Write-OK "DNS server set to $DnsServer (lab-dc01)."

# Give the network stack a moment
Start-Sleep -Seconds 3

# -- Verify the DC is reachable before attempting the join --
Write-Step "Verifying the Domain Controller at $DnsServer is reachable..."
if (Test-Connection -ComputerName $DnsServer -Count 2 -Quiet) {
    Write-OK "Domain Controller $DnsServer is reachable."
} else {
    Write-Warning "Cannot reach DC at $DnsServer. Ensure lab-dc01 is running."
    Write-Warning "Continuing — the domain join below may fail."
}

# -- Rename the computer (takes effect on reboot) --
if ($env:COMPUTERNAME -ne $TargetHostname) {
    Write-Step "Renaming computer '$($env:COMPUTERNAME)' -> '$TargetHostname'..."
    Rename-Computer -NewName $TargetHostname -Force
    Write-OK "Rename queued (applies on reboot)."
} else {
    Write-OK "Computer already named $TargetHostname."
}

# -- Join the domain --
if (-not $isDomainJoined) {
    if (-not $DomainJoinCredential) {
        Write-Step "Domain join credential not supplied — prompting..."
        $DomainJoinCredential = Get-Credential -Message "Enter LAB Domain Admin credentials to join $DomainName"
    }

    Write-Step "Joining domain $DomainName..."
    # Rename + join in one shot where possible so only one reboot is needed.
    Add-Computer -DomainName  $DomainName `
                 -Credential  $DomainJoinCredential `
                 -OUPath      "OU=Servers,DC=lab,DC=local" `
                 -NewName     $TargetHostname `
                 -Force
    Write-OK "Joined $DomainName (computer placed in OU=Servers). Reboot required."
} else {
    Write-OK "Already joined to $DomainName."
}

# -- Reboot to finish Phase 1 --
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "  Phase 1 complete. Rebooting in 10 seconds..." -ForegroundColor Yellow
Write-Host "  After reboot, log in as a DOMAIN admin and re-run this script" -ForegroundColor Yellow
Write-Host "  (same parameters) to perform Phase 2 (install the Cloud Sync agent)." -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
Start-Sleep -Seconds 10
Restart-Computer -Force
