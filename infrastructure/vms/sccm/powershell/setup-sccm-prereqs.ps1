#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install SCCM prerequisites on lab-sccm01.

.DESCRIPTION
    Configures a Windows Server 2022 VM as an SCCM Current Branch prerequisite
    host. Performs:
    - Computer rename to LAB-SCCM01
    - Static IP assignment (10.10.10.20)
    - Domain join to lab.local
    - Installation of all required Windows features for SCCM
    - Creation of SCCM sources staging directory

    NOTE: SQL Server and SCCM CB itself must be installed manually after this
    script completes. See infrastructure/vms/sccm/README.md for full guide.

.PARAMETER DomainJoinCredential
    Credential with permission to join the lab.local domain.
    Run as: -DomainJoinCredential (Get-Credential)

.PARAMETER DomainName
    Active Directory domain to join. Default: lab.local

.PARAMETER SCCMHostname
    Hostname to assign to this server. Default: LAB-SCCM01

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-sccm-prereqs.ps1 -DomainJoinCredential (Get-Credential)

.NOTES
    Run from an elevated PowerShell session on lab-sccm01.
    The script will restart the server once (after domain join).
    Run it again after restart if needed (features install is idempotent).
#>

param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]
    $DomainJoinCredential,

    [string]$DomainName    = "lab.local",
    [string]$DCHostname    = "lab-dc01.lab.local",
    [string]$SCCMHostname  = "LAB-SCCM01",
    [string]$LabIPAddress  = "10.10.10.20",
    [string]$SubnetPrefix  = "24",
    [string]$DefaultGateway = "10.10.10.1",
    [string]$DNSServer     = "10.10.10.10",
    [string]$SourcesDir    = "C:\SCCM_Sources"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# Step 1: Rename computer
# -----------------------------------------------------------------------
Write-Step "Checking computer name..."
if ($env:COMPUTERNAME -ne $SCCMHostname) {
    Write-Step "Renaming computer to $SCCMHostname..."
    Rename-Computer -NewName $SCCMHostname -Force
    Write-OK "Computer renamed. Will apply after reboot."
} else {
    Write-OK "Computer is already named $SCCMHostname"
}

# -----------------------------------------------------------------------
# Step 2: Set static IP
# -----------------------------------------------------------------------
Write-Step "Setting static IP address $LabIPAddress/$SubnetPrefix..."

$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not $adapter) {
    Write-Error "No active network adapter found. Install VirtIO NetKVM driver first."
    exit 1
}

# Remove existing configuration
Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

# Set new static IP
New-NetIPAddress `
    -InterfaceAlias $adapter.Name `
    -IPAddress      $LabIPAddress `
    -PrefixLength   $SubnetPrefix `
    -DefaultGateway $DefaultGateway

# Set DNS to the Domain Controller
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DNSServer

Write-OK "IP set: $LabIPAddress/$SubnetPrefix | Gateway: $DefaultGateway | DNS: $DNSServer"

# Wait briefly for network stack to stabilise
Start-Sleep -Seconds 3

# -----------------------------------------------------------------------
# Step 3: Verify connectivity to DC
# -----------------------------------------------------------------------
Write-Step "Verifying connectivity to Domain Controller at $DNSServer..."
$pingResult = Test-Connection -ComputerName $DNSServer -Count 2 -Quiet
if ($pingResult) {
    Write-OK "Domain Controller is reachable."
} else {
    Write-Warning "Cannot reach DC at $DNSServer. Check network config and that lab-dc01 is running."
    Write-Warning "Continuing anyway — domain join may fail."
}

# -----------------------------------------------------------------------
# Step 4: Join the domain
# -----------------------------------------------------------------------
$currentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
if ($currentDomain -ne $DomainName) {
    Write-Step "Joining domain $DomainName..."
    Add-Computer -DomainName $DomainName `
                 -Credential $DomainJoinCredential `
                 -OUPath "OU=Servers,DC=lab,DC=local" `
                 -Force
    Write-OK "Joined domain $DomainName. Restart required."
} else {
    Write-OK "Already joined to domain $DomainName"
}

# -----------------------------------------------------------------------
# Step 5: Install Windows features required for SCCM
# -----------------------------------------------------------------------
Write-Step "Installing required Windows features for SCCM..."

# Core SCCM prerequisites
$features = @(
    # IIS / Web Server
    "Web-Server",
    "Web-Common-Http",
    "Web-Default-Doc",
    "Web-Dir-Browsing",
    "Web-Http-Errors",
    "Web-Static-Content",
    "Web-Http-Redirect",
    "Web-Http-Logging",
    "Web-Log-Libraries",
    "Web-Request-Monitor",
    "Web-Http-Tracing",
    "Web-Stat-Compression",
    "Web-Dyn-Compression",
    "Web-Filtering",
    "Web-Basic-Auth",
    "Web-Windows-Auth",
    "Web-Net-Ext45",
    "Web-Asp-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Mgmt-Console",
    "Web-Metabase",
    "Web-WMI",
    "Web-Mgmt-Tools",

    # BITS (Background Intelligent Transfer Service)
    "BITS",
    "BITS-IIS-Ext",

    # RDC (Remote Differential Compression)
    "RDC",

    # .NET Framework
    "NET-Framework-45-Core",
    "NET-Framework-45-ASPNET",
    "NET-WCF-Services45",
    "NET-WCF-HTTP-Activation45",
    "NET-WCF-TCP-PortSharing45",

    # WSUS (optional, for Software Update Point)
    # "UpdateServices-Services",
    # "UpdateServices-DB",

    # Management tools
    "RSAT-Role-Tools",
    "RSAT-AD-Tools",
    "RSAT-AD-PowerShell"
)

$failedFeatures = @()
foreach ($feature in $features) {
    try {
        $result = Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction Stop
        if ($result.Success -or $result.FeatureResult.Count -gt 0) {
            Write-OK "Installed: $feature"
        }
    } catch {
        # Some features may not exist on all SKUs — warn but continue
        Write-Warning "Could not install $feature : $_"
        $failedFeatures += $feature
    }
}

if ($failedFeatures.Count -gt 0) {
    Write-Host "`n    The following features could not be installed:" -ForegroundColor Yellow
    $failedFeatures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host "    This may be normal if the features are not available on this edition." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# Step 6: Create SCCM sources directory structure
# -----------------------------------------------------------------------
Write-Step "Creating SCCM staging directory at $SourcesDir..."

$subDirs = @(
    "",              # Root
    "\SQLServer",    # SQL Server installation files
    "\SCCM_Setup",  # SCCM CB setup files
    "\Prereqs",      # SCCM prerequisite downloads
    "\ADK",          # Windows ADK installer
    "\Content",      # SCCM content library staging
    "\OSD"           # OS deployment files (drivers, images)
)

foreach ($dir in $subDirs) {
    $path = "$SourcesDir$dir"
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-OK "Created: $path"
    } else {
        Write-OK "Already exists: $path"
    }
}

# -----------------------------------------------------------------------
# Step 7: Configure Windows Firewall for SCCM
# -----------------------------------------------------------------------
Write-Step "Configuring Windows Firewall rules for SCCM..."

$firewallRules = @(
    @{ Name = "SCCM-HTTP";        Port = 80;    Direction = "Inbound" },
    @{ Name = "SCCM-HTTPS";       Port = 443;   Direction = "Inbound" },
    @{ Name = "SCCM-SMB";         Port = 445;   Direction = "Inbound" },
    @{ Name = "SCCM-WSUS-HTTP";   Port = 8530;  Direction = "Inbound" },
    @{ Name = "SCCM-WSUS-HTTPS";  Port = 8531;  Direction = "Inbound" },
    @{ Name = "SCCM-Client-Port"; Port = 10123; Direction = "Inbound" },
    @{ Name = "SCCM-SQL";         Port = 1433;  Direction = "Inbound" }
)

foreach ($rule in $firewallRules) {
    try {
        $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule `
                -DisplayName  $rule.Name `
                -Direction    $rule.Direction `
                -Protocol     TCP `
                -LocalPort    $rule.Port `
                -Action       Allow `
                -Profile      Domain,Private | Out-Null
            Write-OK "Firewall rule created: $($rule.Name) (port $($rule.Port))"
        } else {
            Write-OK "Firewall rule exists: $($rule.Name)"
        }
    } catch {
        Write-Warning "Could not create firewall rule $($rule.Name): $_"
    }
}

# -----------------------------------------------------------------------
# Summary and next steps
# -----------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  SCCM Prerequisites Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT MANUAL STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. RESTART the server (if domain join or rename was performed)" -ForegroundColor Yellow
Write-Host "     Restart-Computer -Force" -ForegroundColor White
Write-Host ""
Write-Host "  2. Install SQL Server 2019/2022 Evaluation" -ForegroundColor Yellow
Write-Host "     - Place installer in: $SourcesDir\SQLServer\" -ForegroundColor White
Write-Host "     - Use collation: SQL_Latin1_General_CP1_CI_AS" -ForegroundColor White
Write-Host "     - Service account: LAB\svc-sccm" -ForegroundColor White
Write-Host ""
Write-Host "  3. Download and install Windows ADK + WinPE Add-on" -ForegroundColor Yellow
Write-Host "     https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor White
Write-Host ""
Write-Host "  4. Download SCCM CB Evaluation and place in $SourcesDir\SCCM_Setup\" -ForegroundColor Yellow
Write-Host "     https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager" -ForegroundColor White
Write-Host ""
Write-Host "  5. Extend AD Schema (run as Schema Admin):" -ForegroundColor Yellow
Write-Host "     $SourcesDir\SCCM_Setup\SMSSETUP\BIN\X64\extadsch.exe" -ForegroundColor White
Write-Host ""
Write-Host "  6. Run SCCM Setup from $SourcesDir\SCCM_Setup\splash.hta" -ForegroundColor Yellow
Write-Host "     - Site Code: LAB" -ForegroundColor White
Write-Host "     - Site Name: Lab Demo" -ForegroundColor White
Write-Host ""
Write-Host "  See infrastructure/vms/sccm/README.md for full guide." -ForegroundColor Cyan
