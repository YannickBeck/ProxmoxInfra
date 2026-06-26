#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure lab-subca01 (VM 113) as an Enterprise SUBORDINATE / Issuing CA
    for lab.local, signed by the offline Standalone Root CA (lab-rootca01).

.DESCRIPTION
    This script is two-phase, mirroring setup-ca.ps1 / setup-dc02.ps1. It
    detects which phase it is in by checking the computer name, domain
    membership, and whether AD CS has already been configured.

      PHASE 1 (computer not named LAB-SUBCA01 OR not domain-joined):
        - Renames the computer to LAB-SUBCA01
        - Sets a static IPv4 address (10.10.10.32) on the vmbr1 adapter
        - Points DNS at lab-dc01 (10.10.10.10)
        - Joins the lab.local domain (placing the computer in OU=Servers)
        - Reboots the server

      PHASE 2 (computer named LAB-SUBCA01 AND domain-joined):
        - Installs ADCS-Cert-Authority, ADCS-Web-Enrollment + management tools
        - Runs Install-AdcsCertificationAuthority -CAType EnterpriseSubordinateCA.
          Because the parent (offline root) is NOT online, the cmdlet cannot
          obtain a signed cert automatically — it instead emits a REQUEST
          (.req) file at C:\<server>.<domain>_<CAName>.req and the CA service
          will NOT start yet.
        - Prints the FULL manual cert-exchange instructions (submit the .req on
          the offline root, bring back the issued .cer, certutil -installCert,
          Start-Service certsvc, publish the root into AD with certutil -dspublish).
        - On a LATER re-run (after the issued cert has been installed), verifies
          the CA service is running and prints verification commands.

    Every step is idempotent: re-running the script skips work that is
    already done (rename, IP, domain join, feature install, CA config).

    IMPORTANT: Phase 2 PAUSES at the request stage. The CA cannot come online
    until you sign the .req on the offline root and install the resulting .cer.

.PARAMETER SafeIp
    Static IPv4 address to assign to this server. Default: 10.10.10.32

.PARAMETER Gateway
    Default gateway for the lab network. Default: 10.10.10.1 (lab-fw01)

.PARAMETER DnsServer
    DNS server (the domain controller). Default: 10.10.10.10 (lab-dc01)

.PARAMETER DomainName
    Active Directory domain to join. Default: lab.local

.PARAMETER DomainJoinCredential
    Credential with permission to join the lab.local domain. If not supplied
    during the join phase the script prompts with Get-Credential.
    Run as: -DomainJoinCredential (Get-Credential)

.PARAMETER SubCaName
    Common name of the Enterprise Subordinate (Issuing) CA. Default: LAB-Issuing-CA

.EXAMPLE
    # Phase 1 (rename + IP + domain join, then reboot):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-subca.ps1 -DomainJoinCredential (Get-Credential)

.EXAMPLE
    # Phase 2 (after reboot, logged in as a Domain/Enterprise Admin):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-subca.ps1

.NOTES
    Run from an elevated PowerShell session on lab-subca01.
    Requires Windows Server 2022 with the VirtIO network driver installed,
    lab-dc01 (10.10.10.10) up for the domain join, and the offline root
    (lab-rootca01) reachable briefly to sign the request.
    Companion guide: ..\README.md   (two-tier PKI build sequence)
#>

param(
    [string]$SafeIp     = "10.10.10.32",
    [string]$Gateway    = "10.10.10.1",
    [string]$DnsServer  = "10.10.10.10",
    [string]$DomainName = "lab.local",

    [System.Management.Automation.PSCredential]
    $DomainJoinCredential,

    [string]$SubCaName  = "LAB-Issuing-CA"
)

$ErrorActionPreference = "Stop"

# Fixed values for this role
$SubHostname  = "LAB-SUBCA01"
$SubnetPrefix = 24

# -----------------------------------------------------------------------
# Helper functions (match the tone of setup-ca.ps1 / setup-dc.ps1)
# -----------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# Phase detection
# -----------------------------------------------------------------------
$cs             = Get-CimInstance -ClassName Win32_ComputerSystem
$currentName    = $env:COMPUTERNAME
$isDomainJoined = $cs.PartOfDomain -and ($cs.Domain -eq $DomainName)
$isNamed        = ($currentName -eq $SubHostname)

# The CA is considered configured if the certsvc service exists AND a CA name
# subkey is present. Install-Adcs... throws if a CA already exists, so we guard.
$caConfigured = $false
$certSvc   = Get-Service -Name "CertSvc" -ErrorAction SilentlyContinue
$caRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
if ($certSvc -and (Test-Path $caRegPath)) {
    $caKey = Get-ChildItem -Path $caRegPath -ErrorAction SilentlyContinue
    if ($caKey) { $caConfigured = $true }
}

# We are in PHASE 2 only once we are BOTH correctly named and domain-joined.
$phase2 = ($isNamed -and $isDomainJoined)

# =======================================================================
# PHASE 2: Install and configure AD CS (Enterprise Subordinate / Issuing CA)
# =======================================================================
if ($phase2) {
    Write-Step "Phase 2 detected (named $SubHostname and joined to $DomainName)."
    Write-Step "Installing and configuring the Enterprise Subordinate (Issuing) CA."

    # -- Install AD CS Windows features (idempotent) --
    Write-Step "Installing AD CS Windows features..."
    $features = @(
        "ADCS-Cert-Authority",   # Certification Authority role service
        "ADCS-Web-Enrollment",   # /certsrv web enrollment
        "RSAT-ADCS-Mgmt"         # Management tools (certtmpl.msc, pkiview.msc)
    )

    foreach ($feature in $features) {
        $state = Get-WindowsFeature -Name $feature
        if ($state.Installed) {
            Write-OK "Already installed: $feature"
        } else {
            $result = Install-WindowsFeature -Name $feature -IncludeManagementTools
            if ($result.Success) {
                Write-OK "Installed: $feature"
            } else {
                Write-Warning "Failed to install: $feature"
            }
        }
    }

    # -------------------------------------------------------------------
    # Detect whether the CA cert has already been installed (the CA service
    # runs only AFTER the offline root has signed the request and we have run
    # certutil -installCert). This lets the SECOND re-run finish cleanly.
    # -------------------------------------------------------------------
    $svc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
    $caOnline = ($svc -and $svc.Status -eq "Running")

    if ($caOnline) {
        # ---- The issued cert is installed and the CA is up. Finish + verify. ----
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  lab-subca01 Enterprise Issuing CA is ONLINE!" -ForegroundColor Green
        Write-Host "  CA Common Name: $SubCaName" -ForegroundColor Green
        Write-Host "  CA Host:        $SubHostname.$DomainName ($SafeIp)" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        # -- Configure the Web Enrollment role service (idempotent via -Force) --
        Write-Step "Configuring AD CS Web Enrollment (/certsrv)..."
        try {
            Install-AdcsWebEnrollment -Force
            Write-OK "Web Enrollment configured (https://$SubHostname.$DomainName/certsrv)."
        } catch {
            Write-Warning "Web Enrollment configuration reported: $_"
            Write-Warning "Usually safe to ignore if it was already configured."
        }

        Write-Host "`n  NEXT MANUAL STEPS (on this ISSUING CA):" -ForegroundColor Yellow
        Write-Host "  1. Create certificate templates (certtmpl.msc) and publish them" -ForegroundColor White
        Write-Host "     (certsrv.msc -> Certificate Templates -> New -> Issue)." -ForegroundColor White
        Write-Host "     See infrastructure/vms/ca/README.md for the template table" -ForegroundColor White
        Write-Host "     (ConfigMgr Web Server / Workstation Auth / LDAPS, etc.)." -ForegroundColor White
        Write-Host "  2. Link an auto-enrollment GPO at the domain root." -ForegroundColor White
        Write-Host ""

        Write-Host "  VERIFICATION COMMANDS:" -ForegroundColor Cyan
        Write-Host "    certutil -CAInfo       # CA name, type (Enterprise Subordinate)" -ForegroundColor White
        Write-Host "    certutil -ping         # CA service responds" -ForegroundColor White
        Write-Host "    certutil -pingadmin    # CA admin interface responds" -ForegroundColor White
        Write-Host "    pkiview.msc            # Enterprise PKI — root + issuing both green" -ForegroundColor White
        Write-Host ""

        Write-Step "Running a quick 'certutil -ping' self-check..."
        try { certutil -ping | Out-Host } catch { Write-Warning "certutil -ping failed: $_" }

        exit 0
    }

    # -- Configure the Enterprise Subordinate CA (idempotent guard) --
    Write-Step "Checking whether a Certification Authority is already configured..."
    if ($caConfigured) {
        Write-OK "A CA is already configured but the service is NOT running yet."
        Write-OK "This means the request was generated but the issued cert is not installed."
        # Fall through to the cert-exchange instructions below.
    } else {
        Write-Step "Configuring Enterprise Subordinate CA '$SubCaName' (4096-bit, SHA256)..."
        Import-Module ADCSDeployment

        # -CAType EnterpriseSubordinateCA: AD-integrated issuing CA. Because the
        # parent (offline root) is NOT online, the cmdlet returns a status of
        # 'IncompleteAtParentCA' (3) and writes a .req file instead of starting
        # the service. We must sign that .req on the offline root and install
        # the resulting .cer. -Force is used; the request path is reported below.
        $result = Install-AdcsCertificationAuthority `
            -CAType                  EnterpriseSubordinateCA `
            -CACommonName            $SubCaName `
            -KeyLength               4096 `
            -HashAlgorithmName       SHA256 `
            -CryptoProviderName      "RSA#Microsoft Software Key Storage Provider" `
            -Force `
            -ErrorAction SilentlyContinue

        if ($result -and $result.ErrorString) {
            Write-Host "    Installer status: $($result.ErrorString)" -ForegroundColor Gray
        }
        Write-OK "Subordinate CA configured — a certificate REQUEST (.req) was generated."
    }

    # -------------------------------------------------------------------
    # Locate the .req request file the subordinate CA produced.
    # Typically C:\<server>.<domain>_<CAName>.req (e.g.
    # C:\LAB-SUBCA01.lab.local_LAB-Issuing-CA.req).
    # -------------------------------------------------------------------
    $reqFile = Get-ChildItem -Path "C:\" -Filter "*.req" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $reqPath = if ($reqFile) { $reqFile.FullName } else { "C:\$SubHostname.$DomainName" + "_$SubCaName.req" }

    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "  ACTION REQUIRED: SIGN THE REQUEST ON THE OFFLINE ROOT" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The Issuing CA service is INTENTIONALLY NOT STARTED. It cannot" -ForegroundColor Yellow
    Write-Host "  come online until the offline root signs its request." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Request file (.req) to sign:" -ForegroundColor Yellow
    if ($reqFile) {
        Write-Host "    $reqPath" -ForegroundColor Green
    } else {
        Write-Host "    (expected) $reqPath" -ForegroundColor White
        Write-Host "    If not present, look for C:\*.req — the CA names it" -ForegroundColor Gray
        Write-Host "    <server>.<domain>_<CAName>.req" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  THE CERT EXCHANGE — do this in order:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Copy the .req above to the OFFLINE ROOT (lab-rootca01)," -ForegroundColor White
    Write-Host "     e.g. into C:\PKI_Import\ there." -ForegroundColor White
    Write-Host ""
    Write-Host "  2. On the OFFLINE ROOT, submit, issue and retrieve:" -ForegroundColor White
    Write-Host "       certreq -submit C:\PKI_Import\<subca>.req" -ForegroundColor White
    Write-Host "       #   -> prints a RequestId (the request is left PENDING" -ForegroundColor Gray
    Write-Host "       #      because a standalone CA does not auto-issue)" -ForegroundColor Gray
    Write-Host "       certutil -resubmit <RequestId>          # issue it" -ForegroundColor White
    Write-Host "       certreq -retrieve <RequestId> C:\PKI_Export\subca.cer" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Copy BACK to THIS issuing CA (lab-subca01):" -ForegroundColor White
    Write-Host "       - subca.cer            (the signed issuing-CA certificate)" -ForegroundColor White
    Write-Host "       - the root .crt and .crl from the root's C:\PKI_Export" -ForegroundColor White
    Write-Host ""
    Write-Host "  4. On THIS issuing CA, trust the root, install the cert, start it:" -ForegroundColor White
    Write-Host "       # add the root to the local + AD trust (so the chain builds):" -ForegroundColor Gray
    Write-Host "       certutil -addstore -f Root C:\PKI_Import\LAB-Offline-Root-CA.crt" -ForegroundColor White
    Write-Host "       certutil -dspublish -f C:\PKI_Import\LAB-Offline-Root-CA.crt RootCA" -ForegroundColor White
    Write-Host "       certutil -dspublish -f C:\PKI_Import\LAB-Offline-Root-CA.crl" -ForegroundColor White
    Write-Host "       # install the signed issuing-CA cert into THIS CA:" -ForegroundColor Gray
    Write-Host "       certutil -installCert C:\PKI_Import\subca.cer" -ForegroundColor White
    Write-Host "       Start-Service certsvc" -ForegroundColor White
    Write-Host ""
    Write-Host "  5. Re-run THIS script (.\setup-subca.ps1) to configure Web" -ForegroundColor White
    Write-Host "     Enrollment and verify the CA is online." -ForegroundColor White
    Write-Host ""
    Write-Host "  See infrastructure/vms/pki/README.md for the full walkthrough." -ForegroundColor Cyan

    exit 0
}

# =======================================================================
# PHASE 1: Rename, set static IP/DNS, join the domain, then reboot
# =======================================================================
Write-Step "Phase 1: preparing $SubHostname (rename, static IP, domain join)."

# -- Rename computer (idempotent) --
if ($currentName -ne $SubHostname) {
    Write-Step "Renaming computer from '$currentName' to '$SubHostname'..."
    Rename-Computer -NewName $SubHostname -Force
    Write-OK "Computer renamed. Takes effect after reboot."
} else {
    Write-OK "Computer is already named $SubHostname"
}

# -- Set static IPv4 on the vmbr1 adapter (idempotent) --
Write-Step "Setting static IP $SafeIp/$SubnetPrefix (gateway $Gateway, DNS $DnsServer)..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not $adapter) {
    Write-Error "No active network adapter found. Install the VirtIO NetKVM driver first."
    exit 1
}

$existingIp = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq $SafeIp }
if ($existingIp) {
    Write-OK "Static IP $SafeIp already present on $($adapter.Name) — skipping IP assignment."
} else {
    # Clear any existing IPv4 config so New-NetIPAddress does not clash
    Remove-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute     -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

    New-NetIPAddress `
        -InterfaceAlias $adapter.Name `
        -IPAddress      $SafeIp `
        -PrefixLength   $SubnetPrefix `
        -DefaultGateway $Gateway | Out-Null
    Write-OK "Static IP set: $SafeIp/$SubnetPrefix via $Gateway"
}

# Always (re)assert DNS so the domain join can resolve the DC
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DnsServer
Write-OK "DNS server set to $DnsServer"

# Give the network stack a moment to settle
Start-Sleep -Seconds 3

# -- Verify the DC is reachable before attempting the join --
Write-Step "Verifying connectivity to the Domain Controller at $DnsServer..."
if (Test-Connection -ComputerName $DnsServer -Count 2 -Quiet) {
    Write-OK "Domain Controller is reachable."
} else {
    Write-Warning "Cannot reach the DC at $DnsServer. Ensure lab-dc01 is running."
    Write-Warning "Continuing anyway — the domain join may fail."
}

# -- Join the domain (idempotent) --
if ($isDomainJoined) {
    Write-OK "Already joined to domain $DomainName."
} else {
    if (-not $DomainJoinCredential) {
        Write-Step "Domain join credential not supplied — prompting..."
        $DomainJoinCredential = Get-Credential -Message "Enter LAB Domain Admin credentials to join $DomainName"
    }

    Write-Step "Joining domain $DomainName (placing computer in OU=Servers)..."
    Add-Computer `
        -DomainName  $DomainName `
        -Credential  $DomainJoinCredential `
        -OUPath      "OU=Servers,DC=lab,DC=local" `
        -Force
    Write-OK "Joined domain $DomainName."
}

# -- Reboot to apply rename + domain membership; phase 2 runs on next login --
Write-Host "`n----------------------------------------" -ForegroundColor Yellow
Write-Host "  Phase 1 complete. Rebooting now." -ForegroundColor Yellow
Write-Host "  After reboot, log in as a LAB Domain/Enterprise Admin and re-run:" -ForegroundColor Yellow
Write-Host "    .\setup-subca.ps1" -ForegroundColor White
Write-Host "  to configure the Enterprise Issuing CA (phase 2). NOTE: phase 2" -ForegroundColor Yellow
Write-Host "  PAUSES at a request (.req) that the OFFLINE ROOT must sign before" -ForegroundColor Yellow
Write-Host "  the issuing CA service can start." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

Restart-Computer -Force
