#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure lab-dc01 as an Active Directory Domain Controller for lab.local.

.DESCRIPTION
    This script performs a complete DC setup:
    - Renames the computer to LAB-DC01
    - Sets a static IP address (10.10.10.10)
    - Installs AD DS, DNS, and DHCP Windows features
    - Promotes the server to the first DC in a new forest (lab.local)
    - After reboot: configures DHCP scope, creates OUs, creates service account

    Run this script in two passes:
      Pass 1 (first run):  Renames, sets IP, installs features, promotes DC, reboots
      Pass 2 (after reboot): Configures DHCP, creates OUs and service account

.NOTES
    Requires Windows Server 2022 with the VirtIO network driver installed.
    Run from an elevated PowerShell session on the DC VM.

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-dc.ps1
#>

param(
    [string]$DomainName      = "lab.local",
    [string]$DomainNetbios   = "LAB",
    [string]$DCHostname      = "LAB-DC01",
    [string]$LabIPAddress    = "10.10.10.10",
    [string]$SubnetPrefix    = "24",
    [string]$DefaultGateway  = "10.10.10.1",
    [string]$DhcpScopeStart  = "10.10.10.100",
    [string]$DhcpScopeEnd    = "10.10.10.200",
    [string]$DhcpSubnetMask  = "255.255.255.0",
    # Change this before running — or pass as parameter
    [string]$SafeModePassword = "S@feModeP@ss1!",
    [string]$SvcSccmPassword  = "SccmSvc!2024Lab"
)

$ErrorActionPreference = "Stop"

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

# Determine if we have already been promoted (AD DS is running)
$adInstalled = $false
try {
    $svc = Get-Service -Name "NTDS" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        $adInstalled = $true
    }
} catch {}

# -----------------------------------------------------------------------
# PASS 2: Post-reboot AD configuration
# -----------------------------------------------------------------------
if ($adInstalled) {
    Write-Step "Pass 2 detected (AD DS is running). Configuring DHCP, OUs, and service accounts."

    # -- Configure DHCP Server --
    Write-Step "Configuring DHCP scope..."
    try {
        $scope = Get-DhcpServerv4Scope -ScopeId "10.10.10.0" -ErrorAction SilentlyContinue
        if (-not $scope) {
            Add-DhcpServerv4Scope -Name "LabScope" `
                -StartRange $DhcpScopeStart `
                -EndRange   $DhcpScopeEnd `
                -SubnetMask $DhcpSubnetMask `
                -State Active
            Write-OK "DHCP scope created: $DhcpScopeStart - $DhcpScopeEnd"
        } else {
            Write-OK "DHCP scope already exists — skipping."
        }
    } catch {
        Write-Warning "DHCP scope config failed: $_"
    }

    # Set DHCP options: default gateway, DNS, domain name
    Set-DhcpServerv4OptionValue -ScopeId "10.10.10.0" `
        -Router         $DefaultGateway `
        -DnsServer      $LabIPAddress `
        -DnsDomain      $DomainName

    # Authorize DHCP server in AD (required to serve leases)
    try {
        Add-DhcpServerInDC -DnsName "$DCHostname.$DomainName" -IPAddress $LabIPAddress
        Write-OK "DHCP server authorized in AD."
    } catch {
        Write-Warning "DHCP authorization may already exist: $_"
    }

    # -- Create Organizational Units --
    Write-Step "Creating Organizational Units..."
    $domainDN = (Get-ADDomain).DistinguishedName

    $ous = @("Servers", "Clients", "ServiceAccounts")
    foreach ($ou in $ous) {
        try {
            $existingOU = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
            if (-not $existingOU) {
                New-ADOrganizationalUnit -Name $ou -Path $domainDN -ProtectedFromAccidentalDeletion $false
                Write-OK "Created OU: $ou"
            } else {
                Write-OK "OU already exists: $ou"
            }
        } catch {
            Write-Warning "Failed to create OU $ou : $_"
        }
    }

    # -- Create SCCM Service Account --
    Write-Step "Creating SCCM service account (svc-sccm)..."
    $svcAccountsOU = "OU=ServiceAccounts,$domainDN"
    try {
        $existingUser = Get-ADUser -Identity "svc-sccm" -ErrorAction SilentlyContinue
        if (-not $existingUser) {
            $securePass = ConvertTo-SecureString $SvcSccmPassword -AsPlainText -Force
            New-ADUser `
                -Name             "svc-sccm" `
                -SamAccountName   "svc-sccm" `
                -UserPrincipalName "svc-sccm@$DomainName" `
                -Path             $svcAccountsOU `
                -AccountPassword  $securePass `
                -PasswordNeverExpires $true `
                -Enabled          $true `
                -Description      "SCCM service account"
            Write-OK "Created service account: svc-sccm"
        } else {
            Write-OK "Service account svc-sccm already exists — skipping."
        }
    } catch {
        Write-Warning "Failed to create svc-sccm: $_"
    }

    # -- Move computer account to Servers OU --
    Write-Step "Moving DC computer account to OU=Servers..."
    try {
        $dcAccount = Get-ADComputer -Identity $DCHostname -ErrorAction SilentlyContinue
        if ($dcAccount) {
            Move-ADObject -Identity $dcAccount.DistinguishedName `
                -TargetPath "OU=Servers,$domainDN"
            Write-OK "Moved $DCHostname to OU=Servers"
        }
    } catch {
        Write-Warning "Could not move DC computer account: $_"
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  lab-dc01 configuration complete!" -ForegroundColor Green
    Write-Host "  Domain:        $DomainName" -ForegroundColor Green
    Write-Host "  DC IP:         $LabIPAddress" -ForegroundColor Green
    Write-Host "  DHCP Range:    $DhcpScopeStart - $DhcpScopeEnd" -ForegroundColor Green
    Write-Host "  Service Acct:  LAB\svc-sccm" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    exit 0
}

# -----------------------------------------------------------------------
# PASS 1: Initial setup, feature install, DC promotion
# -----------------------------------------------------------------------

Write-Step "Pass 1: Initial DC configuration"

# -- Rename computer --
$currentName = $env:COMPUTERNAME
if ($currentName -ne $DCHostname) {
    Write-Step "Renaming computer from '$currentName' to '$DCHostname'..."
    Rename-Computer -NewName $DCHostname -Force
    Write-OK "Computer renamed. Will take effect after reboot."
} else {
    Write-OK "Computer is already named $DCHostname"
}

# -- Set static IP address --
Write-Step "Setting static IP address $LabIPAddress/$SubnetPrefix..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not $adapter) {
    Write-Error "No active network adapter found. Install VirtIO network driver first."
    exit 1
}

# Remove any existing IP configuration
try {
    Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

New-NetIPAddress `
    -InterfaceAlias $adapter.Name `
    -IPAddress      $LabIPAddress `
    -PrefixLength   $SubnetPrefix `
    -DefaultGateway $DefaultGateway

# Set DNS to loopback (will resolve to self after AD install)
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses "127.0.0.1"
Write-OK "Static IP set: $LabIPAddress/$SubnetPrefix, gateway: $DefaultGateway"

# -- Install Windows features --
Write-Step "Installing AD DS, DNS, and DHCP Windows features..."
$features = @(
    "AD-Domain-Services",
    "DNS",
    "DHCP",
    "RSAT-AD-PowerShell",
    "RSAT-DHCP",
    "RSAT-DNS-Server"
)

foreach ($feature in $features) {
    $result = Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue
    if ($result.Success) {
        Write-OK "Installed: $feature"
    } elseif ($result.RestartNeeded -eq "Yes") {
        Write-OK "Installed (restart needed): $feature"
    } else {
        $existing = Get-WindowsFeature -Name $feature
        if ($existing.Installed) {
            Write-OK "Already installed: $feature"
        } else {
            Write-Warning "Failed to install: $feature"
        }
    }
}

# -- Promote to Domain Controller --
Write-Step "Promoting server to Domain Controller for $DomainName..."
Write-Host "    This will reboot the server automatically." -ForegroundColor Yellow
Write-Host "    After reboot, run this script again to complete configuration." -ForegroundColor Yellow

$safeModeSecure = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName                    $DomainName `
    -DomainNetbiosName             $DomainNetbios `
    -DomainMode                    "WinThreshold" `
    -ForestMode                    "WinThreshold" `
    -SafeModeAdministratorPassword $safeModeSecure `
    -InstallDns                    $true `
    -CreateDnsDelegation           $false `
    -NoRebootOnCompletion          $false `
    -Force                         $true

# Script will not reach here — server reboots after promotion
Write-Host "Promotion initiated. Server will reboot..." -ForegroundColor Yellow
