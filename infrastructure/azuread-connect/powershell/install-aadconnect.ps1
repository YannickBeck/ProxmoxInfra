#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepare lab-aadc01 (VMID 106) for hybrid identity and install Microsoft
    Entra Connect Sync (the "Azure AD Connect" agent) for lab.local -> Entra ID.

.DESCRIPTION
    This script provisions the dedicated sync member server and stages the
    Entra Connect installer. It runs in TWO passes:

      Pass 1 (machine not named LAB-AADC01 / not domain-joined):
        - Rename computer to LAB-AADC01
        - Set static IP 10.10.10.40/24, gateway 10.10.10.1
        - Set DNS to the lab DC (10.10.10.10) so the domain can be resolved
        - Join the lab.local domain
        - Reboot

      Pass 2 (machine is LAB-AADC01 and domain-joined):
        - Ensure RSAT AD PowerShell tools are present
        - Add a routable alternative UPN suffix to the AD forest (so users do
          NOT sync as <user>@<tenant>.onmicrosoft.com). lab.local is
          non-routable and cannot be verified in Entra.
        - (Optional helper) bulk-stamp users' UPN to the routable suffix
        - Test internet reachability to login.microsoftonline.com:443
        - Download the Entra Connect (Azure AD Connect) MSI
        - LAUNCH the installer interactively

    IMPORTANT: The sync configuration itself is an INTERACTIVE wizard. It
    requires signing in with a Microsoft Entra **Global Administrator** account
    and will almost certainly prompt for **MFA**. This script intentionally
    does NOT attempt a silent/unattended configuration — it only stages and
    launches the wizard, then prints the exact choices to make.

.PARAMETER SafeIp
    Static IPv4 address for this server on vmbr1. Default 10.10.10.40.

.PARAMETER Gateway
    Default gateway (pfSense / Proxmox host providing NAT). Default 10.10.10.1.

.PARAMETER DnsServer
    DNS server = the lab DC (lab-dc01). Default 10.10.10.10.

.PARAMETER DomainName
    AD domain to join. Default lab.local.

.PARAMETER DomainJoinCredential
    [PSCredential] with rights to join the domain (e.g. LAB\Administrator).
    Run as: -DomainJoinCredential (Get-Credential)

.PARAMETER UpnSuffix
    The routable UPN suffix to add to the forest and stamp on users. Use your
    tenant's <tenant>.onmicrosoft.com or a verified custom domain.
    Example: "labdemo.onmicrosoft.com"

.PARAMETER DownloadDir
    Where to download the Entra Connect MSI. Default C:\Install.

.PREREQUISITES
    - Windows Server 2022 (Desktop Experience) installed, VirtIO NIC driver present
    - lab-dc01 up and reachable; lab.local domain functioning
    - A Microsoft Entra tenant + a Global Administrator account
    - Internet access from this VM (sync talks to Entra ID over 443)
    - .NET Framework 4.7.2+ (Server 2022 ships with this)

.EXAMPLE
    # Pass 1 (provision + domain join, then auto-reboot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\install-aadconnect.ps1 -DomainJoinCredential (Get-Credential) `
        -UpnSuffix "labdemo.onmicrosoft.com"

.EXAMPLE
    # Pass 2 (after reboot — same command; script auto-detects the phase)
    .\install-aadconnect.ps1 -DomainJoinCredential (Get-Credential) `
        -UpnSuffix "labdemo.onmicrosoft.com"

.NOTES
    Repo: ProxmoxInfra — infrastructure/azuread-connect
    Companion guide: ..\README.md
#>

param(
    [string]$SafeIp        = "10.10.10.40",
    [string]$Gateway       = "10.10.10.1",
    [string]$DnsServer     = "10.10.10.10",
    [string]$DomainName    = "lab.local",

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]$DomainJoinCredential,

    [Parameter(Mandatory = $true)]
    [string]$UpnSuffix,

    [string]$DownloadDir   = "C:\Install"
)

$ErrorActionPreference = "Stop"

$TargetHostname = "LAB-AADC01"
$SubnetPrefix   = "24"
$AadcMsiUrl     = "https://go.microsoft.com/fwlink/?LinkId=615771"
$AadcMsiPath    = Join-Path $DownloadDir "AzureADConnect.msi"

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

# Optional helper: bulk-stamp every enabled user's UPN to the routable suffix.
# NOT called automatically — review, then call manually if you want it:
#     Set-LabUsersUpnSuffix -OldSuffix "lab.local" -NewSuffix $UpnSuffix
# This is what prevents users from syncing as <user>@<tenant>.onmicrosoft.com.
function Set-LabUsersUpnSuffix {
    param(
        [string]$OldSuffix = "lab.local",
        [Parameter(Mandatory = $true)][string]$NewSuffix,
        [string]$SearchBase  # optional OU DN to scope; default = whole domain
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    $getParams = @{ Filter = "Enabled -eq 'True'"; Properties = "UserPrincipalName" }
    if ($SearchBase) { $getParams["SearchBase"] = $SearchBase }

    Get-ADUser @getParams | ForEach-Object {
        if ($_.UserPrincipalName -and $_.UserPrincipalName -like "*@$OldSuffix") {
            $newUpn = ($_.UserPrincipalName -split "@")[0] + "@$NewSuffix"
            Set-ADUser -Identity $_ -UserPrincipalName $newUpn
            Write-Host "    Updated $($_.SamAccountName) -> $newUpn" -ForegroundColor Green
        }
    }
}

# -----------------------------------------------------------------------
# Phase detection
# -----------------------------------------------------------------------
$cs            = Get-CimInstance -ClassName Win32_ComputerSystem
$isCorrectName = ($env:COMPUTERNAME -eq $TargetHostname)
$isDomainJoined = ($cs.PartOfDomain -and $cs.Domain -eq $DomainName)

# =======================================================================
# PHASE 2: Server is named LAB-AADC01 and joined to lab.local
# =======================================================================
if ($isCorrectName -and $isDomainJoined) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  PHASE 2: Entra Connect staging on $TargetHostname" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    # -- Ensure RSAT AD PowerShell --
    Write-Step "Ensuring RSAT AD PowerShell tools are installed..."
    $rsat = Get-WindowsFeature -Name RSAT-AD-PowerShell
    if (-not $rsat.Installed) {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
        Write-OK "Installed RSAT-AD-PowerShell."
    } else {
        Write-OK "RSAT-AD-PowerShell already present."
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    # -- Add the routable alternative UPN suffix to the forest --
    Write-Step "Ensuring routable UPN suffix '$UpnSuffix' exists on the forest..."
    $forest = Get-ADForest
    if ($forest.UPNSuffixes -contains $UpnSuffix) {
        Write-OK "UPN suffix '$UpnSuffix' already present — skipping."
    } else {
        Set-ADForest -Identity $forest.Name -UPNSuffixes @{ add = $UpnSuffix }
        Write-OK "Added UPN suffix '$UpnSuffix' to forest '$($forest.Name)'."
    }

    Write-Host "    NOTE: The suffix is now AVAILABLE, but existing users still" -ForegroundColor Yellow
    Write-Host "          carry @lab.local. Stamp users with the routable suffix" -ForegroundColor Yellow
    Write-Host "          BEFORE first sync so they do not appear in Entra as" -ForegroundColor Yellow
    Write-Host "          <user>@<tenant>.onmicrosoft.com. To bulk-update, run:" -ForegroundColor Yellow
    Write-Host "          Set-LabUsersUpnSuffix -OldSuffix 'lab.local' -NewSuffix '$UpnSuffix'" -ForegroundColor White
    Write-Host "          (Helper function is defined in this script — review first.)" -ForegroundColor Yellow

    # -- Test internet connectivity to Entra ID --
    Write-Step "Testing internet connectivity to login.microsoftonline.com:443..."
    $net = Test-NetConnection -ComputerName "login.microsoftonline.com" -Port 443 -WarningAction SilentlyContinue
    if ($net.TcpTestSucceeded) {
        Write-OK "Reached login.microsoftonline.com on 443 — Entra is reachable."
    } else {
        Write-Warning "Could NOT reach login.microsoftonline.com:443."
        Write-Warning "Entra Connect sync REQUIRES internet from this VM."
        Write-Warning "Verify the pfSense/NAT gateway ($Gateway) provides internet,"
        Write-Warning "or temporarily attach an internet-capable NIC. Continuing to stage installer."
    }

    # -- Download the Entra Connect (Azure AD Connect) MSI --
    Write-Step "Staging the Entra Connect (Azure AD Connect) installer..."
    if (-not (Test-Path $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }
    if (Test-Path $AadcMsiPath) {
        Write-OK "Installer already downloaded: $AadcMsiPath — skipping download."
    } else {
        Write-Host "    Downloading from $AadcMsiUrl ..." -ForegroundColor Gray
        $oldProgress = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"   # massively speeds up Invoke-WebRequest
        try {
            Invoke-WebRequest -Uri $AadcMsiUrl -OutFile $AadcMsiPath -UseBasicParsing
            Write-OK "Downloaded installer to $AadcMsiPath"
        } catch {
            $ProgressPreference = $oldProgress
            Write-Error "Failed to download Entra Connect MSI: $_"
            Write-Warning "Manually download from https://www.microsoft.com/download/details.aspx?id=47594"
            Write-Warning "and place it at $AadcMsiPath, then re-run this script."
            exit 1
        }
        $ProgressPreference = $oldProgress
    }

    # -- Launch the interactive wizard --
    Write-Step "Launching the Entra Connect setup wizard (interactive)..."
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor Magenta
    Write-Host "  WIZARD CHOICES TO MAKE (do NOT pick Express):" -ForegroundColor Magenta
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor Magenta
    Write-Host "   1. Welcome -> accept license -> Continue" -ForegroundColor White
    Write-Host "   2. Choose 'Customize' (NOT 'Use express settings')." -ForegroundColor White
    Write-Host "   3. Install required components -> Install." -ForegroundColor White
    Write-Host "   4. User sign-in:" -ForegroundColor White
    Write-Host "        [x] Password Hash Synchronization (PHS)" -ForegroundColor White
    Write-Host "        [x] Enable single sign-on (Seamless SSO)" -ForegroundColor White
    Write-Host "   5. Connect to Entra ID: sign in with a GLOBAL ADMIN (expect MFA)." -ForegroundColor White
    Write-Host "   6. Connect your directories: add the lab.local forest using" -ForegroundColor White
    Write-Host "        enterprise admin / domain admin creds (LAB\Administrator)." -ForegroundColor White
    Write-Host "   7. Entra sign-in config: confirm the routable UPN suffix" -ForegroundColor White
    Write-Host "        '$UpnSuffix' is the User Principal Name attribute and is" -ForegroundColor White
    Write-Host "        'Verified'. If it shows 'Not Added/Not Verified', fix the" -ForegroundColor White
    Write-Host "        domain in Entra (or pick onmicrosoft.com) before continuing." -ForegroundColor White
    Write-Host "   8. Domain/OU filtering: 'Sync selected domains and OUs' ->" -ForegroundColor White
    Write-Host "        tick only OU=Users (and your SCCM OUs, e.g. OU=Servers," -ForegroundColor White
    Write-Host "        OU=Clients). Avoid syncing built-in/system OUs." -ForegroundColor White
    Write-Host "   9. Identifying users / groups / filtering: leave defaults." -ForegroundColor White
    Write-Host "  10. Optional features: (PHS already chosen) — leave others off" -ForegroundColor White
    Write-Host "        unless needed." -ForegroundColor White
    Write-Host "  11. Device options: choose 'Configure Hybrid Azure AD join'." -ForegroundColor White
    Write-Host "        - Device operating systems: Windows 10 or later domain-joined" -ForegroundColor White
    Write-Host "        - SCP configuration: select the lab.local forest, authenticate" -ForegroundColor White
    Write-Host "          so the wizard writes the Service Connection Point (SCP) to AD." -ForegroundColor White
    Write-Host "  12. Ready to configure: tick 'Start the synchronization process" -ForegroundColor White
    Write-Host "        when configuration completes' -> Install." -ForegroundColor White
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor Magenta
    Write-Host ""

    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$AadcMsiPath`"" -Wait

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Entra Connect wizard closed." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

    # -- Entra Cloud Sync alternative note --
    Write-Step "Alternative: Microsoft Entra Cloud Sync (lightweight agent)"
    Write-Host "    If you prefer the lightweight provisioning agent instead of the" -ForegroundColor Gray
    Write-Host "    full Connect Sync engine, download the 'Provisioning Agent' from:" -ForegroundColor Gray
    Write-Host "    Entra admin center -> Identity -> Hybrid management ->" -ForegroundColor Gray
    Write-Host "    Microsoft Entra Connect -> Cloud sync -> Download agent." -ForegroundColor Gray
    Write-Host "    It is configured entirely in the cloud portal (no on-box wizard)." -ForegroundColor Gray
    Write-Host "    See ..\README.md (Option B) for capabilities and limits." -ForegroundColor Gray

    # -- Verification hints --
    Write-Step "Verification (after the wizard finishes installing)"
    Write-Host "    On THIS server:" -ForegroundColor Gray
    Write-Host "      Get-ADSyncScheduler                       # SyncCycleEnabled : True" -ForegroundColor White
    Write-Host "      Start-ADSyncSyncCycle -PolicyType Delta    # force a delta sync" -ForegroundColor White
    Write-Host "      Get-ADSyncConnectorRunStatus               # current run state" -ForegroundColor White
    Write-Host "    In the Entra admin center: Users / Devices should now show the" -ForegroundColor Gray
    Write-Host "    synced objects (Directory synced source)." -ForegroundColor Gray
    Write-Host "    On lab-client01 (after a GPUpdate / sync window):" -ForegroundColor Gray
    Write-Host "      dsregcmd /status   # expect AzureAdJoined: YES, DomainJoined: YES" -ForegroundColor White

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
    Write-Error "No active network adapter found. Install the VirtIO network driver first."
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
        Remove-NetRoute -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
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
Write-Host "  (same parameters) to perform Phase 2 (UPN suffix + Entra Connect)." -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
Start-Sleep -Seconds 10
Restart-Computer -Force
