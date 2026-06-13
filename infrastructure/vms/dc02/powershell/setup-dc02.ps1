<#
.SYNOPSIS
    Two-phase setup script for lab-dc02: rename + domain-join, then promote to Domain Controller.

.DESCRIPTION
    Phase 1 (machine not yet named LAB-DC02 or not yet domain-joined):
        - Renames the computer to LAB-DC02
        - Sets a static IPv4 address, subnet mask, gateway, and DNS
        - Joins the machine to the specified domain
        - Restarts the computer

    Phase 2 (machine already named LAB-DC02 and domain-joined but not yet a DC):
        - Installs the AD-Domain-Services Windows feature plus DNS and RSAT tools
        - Promotes the server as an additional domain controller in the existing domain
        - Sets the DSRM (Safe Mode Administrator) password
        - Restarts the computer to complete promotion

    The script is idempotent: re-running it on a machine that has already completed
    either phase will skip that phase and report the current state.

.PARAMETER SafeIp
    Static IPv4 address to assign to this server's first adapter (default: 10.10.10.11).

.PARAMETER PrefixLength
    Subnet prefix length (default: 24, i.e. 255.255.255.0).

.PARAMETER Gateway
    Default gateway IPv4 address (default: 10.10.10.1).

.PARAMETER PrimaryDns
    Primary DNS server IPv4 address — should be lab-dc01 (default: 10.10.10.10).

.PARAMETER DomainName
    Fully-qualified domain name to join and promote into (default: lab.local).

.PARAMETER SafeModePassword
    Directory Services Restore Mode (DSRM) password as a SecureString.
    Prompt example: -SafeModePassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force)

.PARAMETER DomainJoinCredential
    PSCredential for an account with permission to join computers and add domain controllers
    (e.g. LAB\Administrator). Prompt example: -DomainJoinCredential (Get-Credential)

.EXAMPLE
    .\setup-dc02.ps1 `
      -SafeIp "10.10.10.11" `
      -Gateway "10.10.10.1" `
      -PrimaryDns "10.10.10.10" `
      -DomainName "lab.local" `
      -SafeModePassword (ConvertTo-SecureString "S@feMode!2024" -AsPlainText -Force) `
      -DomainJoinCredential (Get-Credential)

.NOTES
    Run as local Administrator in Phase 1.
    Run as Domain Admin (LAB\Administrator) in Phase 2 (after the Phase 1 reboot).
    Requires Windows Server 2016 or later.
    Tested on Windows Server 2022.
#>

[CmdletBinding()]
param (
    [string]$SafeIp       = "10.10.10.11",
    [int]$PrefixLength    = 24,
    [string]$Gateway      = "10.10.10.1",
    [string]$PrimaryDns   = "10.10.10.10",
    [string]$DomainName   = "lab.local",

    [Parameter(Mandatory = $true)]
    [SecureString]$SafeModePassword,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]$DomainJoinCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-Done {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "    [-] SKIP: $Message" -ForegroundColor Yellow
}

function Test-IsDomainController {
    $role = (Get-WmiObject Win32_ComputerSystem).DomainRole
    # DomainRole: 4 = Backup DC, 5 = Primary DC — both are DCs
    return ($role -eq 4 -or $role -eq 5)
}

function Test-IsDomainMember {
    $cs = Get-WmiObject Win32_ComputerSystem
    return ($cs.PartOfDomain -eq $true)
}

function Test-HasCorrectName {
    return ($env:COMPUTERNAME -ieq "LAB-DC02")
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

Write-Step "Pre-flight checks"

$isDC     = Test-IsDomainController
$isJoined = Test-IsDomainMember
$hasName  = Test-HasCorrectName

Write-Host "    ComputerName : $env:COMPUTERNAME"
Write-Host "    DomainJoined : $isJoined"
Write-Host "    IsDomainCtrl : $isDC"

if ($isDC) {
    Write-Skip "This machine is already a Domain Controller. Nothing to do."
    exit 0
}

# ---------------------------------------------------------------------------
# Phase 1 — Rename, set static IP, join domain, reboot
# ---------------------------------------------------------------------------

if (-not $hasName -or -not $isJoined) {
    Write-Step "Phase 1: Rename, configure network, and join domain"

    # -- Static IP --
    Write-Step "Configuring static IP $SafeIp/$PrefixLength (gateway $Gateway, DNS $PrimaryDns)"
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($null -eq $adapter) {
        Write-Error "No active network adapter found. Cannot configure IP."
        exit 1
    }

    # Remove existing IPv4 configurations on the adapter
    $existingIp = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
                    -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($existingIp) {
        foreach ($ip in $existingIp) {
            Remove-NetIPAddress -InputObject $ip -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    $existingRoute = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex `
                       -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    if ($existingRoute) {
        Remove-NetRoute -InputObject $existingRoute -Confirm:$false -ErrorAction SilentlyContinue
    }

    New-NetIPAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -AddressFamily IPv4 `
        -IPAddress $SafeIp `
        -PrefixLength $PrefixLength `
        -DefaultGateway $Gateway | Out-Null

    Set-DnsClientServerAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -ServerAddresses @($PrimaryDns) | Out-Null

    Write-Done "Static IP configured on adapter '$($adapter.Name)'"

    # -- Rename --
    if (-not $hasName) {
        Write-Step "Renaming computer to LAB-DC02"
        Rename-Computer -NewName "LAB-DC02" -Force -ErrorAction Stop
        Write-Done "Computer renamed to LAB-DC02 (takes effect after reboot)"
    } else {
        Write-Skip "Computer name is already LAB-DC02"
    }

    # -- Domain join --
    if (-not $isJoined) {
        Write-Step "Joining domain '$DomainName'"

        # Verify connectivity to DC before attempting join
        $dcReachable = Test-Connection -ComputerName $PrimaryDns -Count 2 -Quiet
        if (-not $dcReachable) {
            Write-Error "Cannot reach DNS/DC at $PrimaryDns. Check network configuration before attempting domain join."
            exit 1
        }

        Add-Computer `
            -DomainName $DomainName `
            -Credential $DomainJoinCredential `
            -NewName "LAB-DC02" `
            -Force `
            -ErrorAction Stop

        Write-Done "Successfully joined domain '$DomainName'"
    } else {
        Write-Skip "Machine is already domain-joined"
    }

    Write-Host "`n[*] Phase 1 complete. The computer will restart now." -ForegroundColor Cyan
    Write-Host "    After reboot, log in as $DomainName\Administrator and re-run this script" `
        -ForegroundColor Yellow
    Write-Host "    to execute Phase 2 (AD DS promotion)." -ForegroundColor Yellow

    Start-Sleep -Seconds 5
    Restart-Computer -Force
    exit 0
}

# ---------------------------------------------------------------------------
# Phase 2 — Install AD DS and promote to Domain Controller
# ---------------------------------------------------------------------------

Write-Step "Phase 2: Install AD DS features and promote to Domain Controller"

# -- Install Windows Features --
Write-Step "Installing AD-Domain-Services, DNS, and RSAT tools"

$features = @(
    "AD-Domain-Services",
    "DNS",
    "RSAT-AD-AdminCenter",
    "RSAT-ADDS",
    "RSAT-AD-PowerShell",
    "RSAT-DNS-Server"
)

$installResult = Install-WindowsFeature -Name $features -IncludeManagementTools

if ($installResult.Success) {
    Write-Done "Windows features installed successfully"
    if ($installResult.RestartNeeded -eq "Yes") {
        Write-Host "    A restart is required before promotion. Restarting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        Restart-Computer -Force
        exit 0
    }
} else {
    Write-Error "Feature installation failed. Check the Windows Event Log for details."
    exit 1
}

# -- Promote to Domain Controller --
Write-Step "Promoting LAB-DC02 as an additional DC in '$DomainName'"

# Verify AD DS module is available after feature install
Import-Module ADDSDeployment -ErrorAction Stop

$dcPromoParams = @{
    InstallDns                    = $true
    CreateDnsDelegation           = $false
    DomainName                    = $DomainName
    SafeModeAdministratorPassword = $SafeModePassword
    Credential                    = $DomainJoinCredential
    ReplicationSourceDC           = ""           # empty = let AD pick the best source
    DatabasePath                  = "C:\Windows\NTDS"
    LogPath                       = "C:\Windows\NTDS"
    SysvolPath                    = "C:\Windows\SYSVOL"
    NoRebootOnCompletion          = $false       # reboot automatically after promotion
    Force                         = $true
}

# Guard: do not attempt promotion if already a DC (re-run safety)
if (Test-IsDomainController) {
    Write-Skip "Machine is already a Domain Controller. Skipping promotion."
    exit 0
}

Write-Host "    Calling Install-ADDSDomainController — the server will reboot automatically." `
    -ForegroundColor Yellow
Write-Host "    This may take several minutes." -ForegroundColor Yellow

Install-ADDSDomainController @dcPromoParams

# If NoRebootOnCompletion were $true, we would reboot here.
# With $false the cmdlet triggers the reboot itself after completion.
Write-Done "Promotion initiated. The server is rebooting to complete AD DS installation."
