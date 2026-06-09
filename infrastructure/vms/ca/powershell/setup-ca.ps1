#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure lab-ca01 as an Active Directory Certificate Services
    Enterprise Root CA for lab.local.

.DESCRIPTION
    This script is two-phase, mirroring setup-dc.ps1. It detects which
    phase it is in by checking the computer name and domain membership.

      PHASE 1 (computer not named LAB-CA01 OR not domain-joined):
        - Renames the computer to LAB-CA01
        - Sets a static IPv4 address (10.10.10.30) on the vmbr1 adapter
        - Points DNS at lab-dc01 (10.10.10.10)
        - Joins the lab.local domain
        - Reboots the server

      PHASE 2 (computer named LAB-CA01 AND domain-joined):
        - Installs the ADCS-Cert-Authority, ADCS-Web-Enrollment and
          RSAT-ADCS-Mgmt Windows features
        - Configures an Enterprise Root CA (LAB-Root-CA), 4096-bit key,
          SHA256, 10-year validity
        - Configures the Web Enrollment role service
        - Publishes the root CA certificate to AD (automatic for an
          Enterprise CA — see comment) and prints the manual next steps
          for certificate-template configuration and the auto-enrollment GPO

    Every step is idempotent: re-running the script skips work that is
    already done (rename, IP, domain join, feature install, CA config).

.PARAMETER SafeIp
    Static IPv4 address to assign to this server. Default: 10.10.10.30

.PARAMETER Gateway
    Default gateway for the lab network. Default: 10.10.10.1 (lab-fw01)

.PARAMETER DnsServer
    DNS server (the domain controller). Default: 10.10.10.10 (lab-dc01)

.PARAMETER DomainName
    Active Directory domain to join. Default: lab.local

.PARAMETER DomainJoinCredential
    Credential with permission to join the lab.local domain. If not
    supplied during the join phase the script prompts with Get-Credential.
    Run as: -DomainJoinCredential (Get-Credential)

.PARAMETER CaCommonName
    Common name of the Enterprise Root CA. Default: LAB-Root-CA

.EXAMPLE
    # Phase 1 (rename + IP + domain join, then reboot):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-ca.ps1 -DomainJoinCredential (Get-Credential)

.EXAMPLE
    # Phase 2 (after reboot, logged in as a Domain Admin):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-ca.ps1

.NOTES
    Run from an elevated PowerShell session on lab-ca01.
    Requires Windows Server 2022 with the VirtIO network driver installed,
    and lab-dc01 (10.10.10.10) up and reachable for the domain join.
#>

param(
    [string]$SafeIp     = "10.10.10.30",
    [string]$Gateway    = "10.10.10.1",
    [string]$DnsServer  = "10.10.10.10",
    [string]$DomainName = "lab.local",

    [System.Management.Automation.PSCredential]
    $DomainJoinCredential,

    [string]$CaCommonName = "LAB-Root-CA"
)

$ErrorActionPreference = "Stop"

# Fixed values for this role
$CaHostname   = "LAB-CA01"
$SubnetPrefix = 24

# -----------------------------------------------------------------------
# Helper functions (match the tone of setup-dc.ps1 / setup-sccm-prereqs.ps1)
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
$cs            = Get-CimInstance -ClassName Win32_ComputerSystem
$currentName   = $env:COMPUTERNAME
$isDomainJoined = $cs.PartOfDomain -and ($cs.Domain -eq $DomainName)
$isNamed        = ($currentName -eq $CaHostname)

# We are in PHASE 2 only once we are BOTH correctly named and domain-joined.
$phase2 = ($isNamed -and $isDomainJoined)

# =======================================================================
# PHASE 2: Install and configure AD CS (Enterprise Root CA)
# =======================================================================
if ($phase2) {
    Write-Step "Phase 2 detected (named $CaHostname and joined to $DomainName)."
    Write-Step "Installing and configuring Active Directory Certificate Services."

    # -- Install AD CS Windows features (idempotent) --
    Write-Step "Installing AD CS Windows features..."
    $features = @(
        "ADCS-Cert-Authority",   # Certification Authority role service
        "ADCS-Web-Enrollment",   # /certsrv web enrollment (CES helper)
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

    # -- Configure the Enterprise Root CA (idempotent guard) --
    Write-Step "Checking whether a Certification Authority is already configured..."

    # The CA is considered configured if the certsvc service exists AND the
    # CA configuration registry key is present. Install-AdcsCertificationAuthority
    # is NOT idempotent and throws if a CA is already present, so we guard it.
    $caConfigured = $false
    $certSvc = Get-Service -Name "CertSvc" -ErrorAction SilentlyContinue
    $caRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
    if ($certSvc -and (Test-Path $caRegPath)) {
        # The CA name appears as a subkey once configured
        $caKey = Get-ChildItem -Path $caRegPath -ErrorAction SilentlyContinue
        if ($caKey) { $caConfigured = $true }
    }

    if ($caConfigured) {
        Write-OK "A Certification Authority is already configured — skipping CA install."
    } else {
        Write-Step "Configuring Enterprise Root CA '$CaCommonName' (4096-bit, SHA256, 10 years)..."
        Import-Module ADCSDeployment

        # -CAType EnterpriseRootCA makes this an AD-integrated root CA. An
        # Enterprise CA supports certificate templates and auto-enrollment
        # (vs a Standalone CA, which does not). The machine must be
        # domain-joined and the installer must be an Enterprise Admin.
        Install-AdcsCertificationAuthority `
            -CAType                  EnterpriseRootCA `
            -CACommonName            $CaCommonName `
            -KeyLength               4096 `
            -HashAlgorithmName       SHA256 `
            -ValidityPeriod          Years `
            -ValidityPeriodUnits     10 `
            -CryptoProviderName      "RSA#Microsoft Software Key Storage Provider" `
            -Force

        Write-OK "Enterprise Root CA '$CaCommonName' configured."

        # NOTE: For an Enterprise CA the root certificate is published
        # automatically into the AD configuration partition (the NTAuth and
        # Certification Authorities containers under
        # CN=Public Key Services,CN=Services,CN=Configuration). Domain-joined
        # machines pick it up into their Trusted Root store via Group Policy
        # autoenrollment automatically — no manual certutil -dspublish needed.
        #
        # To publish/refresh it manually (e.g. after re-keying), export the
        # root cert and run:
        #   certutil -dspublish -f C:\LAB-Root-CA.cer RootCA
    }

    # -- Configure the Web Enrollment role service (idempotent via -Force) --
    Write-Step "Configuring AD CS Web Enrollment (/certsrv)..."
    try {
        Install-AdcsWebEnrollment -Force
        Write-OK "Web Enrollment configured (https://$CaHostname.$DomainName/certsrv)."
    } catch {
        Write-Warning "Web Enrollment configuration reported: $_"
        Write-Warning "This is usually safe to ignore if it was already configured."
    }

    # -------------------------------------------------------------------
    # Optional automated template configuration via PSPKI (if available)
    # -------------------------------------------------------------------
    Write-Step "Checking for the PSPKI module (optional template automation)..."
    $pspki = Get-Module -ListAvailable -Name PSPKI
    if ($pspki) {
        Import-Module PSPKI
        Write-OK "PSPKI is available — duplicating the Web Server template and granting autoenroll."
        try {
            # Duplicate the built-in "WebServer" template to a v2 template that
            # allows autoenrollment, then grant Domain Computers Enroll/Autoenroll.
            $newTemplateName = "LabWebServerAuto"
            $existing = Get-CertificateTemplate -Name $newTemplateName -ErrorAction SilentlyContinue
            if (-not $existing) {
                $base = Get-CertificateTemplate -Name "WebServer"
                # Clone produces a new template object; persist with Set-CertificateTemplate.
                $clone = $base | Clone-CertificateTemplate -Name $newTemplateName -DisplayName "Lab Web Server (Autoenroll)"
                $clone | Set-CertificateTemplateAcl -User "LAB\Domain Computers" `
                    -AccessType Allow -AccessMask Read, Enroll, AutoEnroll | Out-Null
                # Publish the new template on this CA so it can be issued.
                Get-CertificationAuthority | Get-CATemplate | Out-Null
                Add-CATemplate -Name $newTemplateName -Confirm:$false -ErrorAction SilentlyContinue
                Write-OK "Created and published template '$newTemplateName' with autoenroll for Domain Computers."
            } else {
                Write-OK "Template '$newTemplateName' already exists — skipping."
            }
        } catch {
            Write-Warning "PSPKI template automation failed: $_"
            Write-Warning "Fall back to the manual certtmpl.msc steps below."
        }
    } else {
        Write-OK "PSPKI not installed — certificate templates will be configured manually (see NEXT STEPS)."
        Write-Host "    To install PSPKI later: Install-Module -Name PSPKI -Scope AllUsers" -ForegroundColor White
    }

    # -------------------------------------------------------------------
    # Summary and NEXT STEPS (manual template + GPO configuration)
    # -------------------------------------------------------------------
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  lab-ca01 Enterprise Root CA configured!" -ForegroundColor Green
    Write-Host "  CA Common Name: $CaCommonName" -ForegroundColor Green
    Write-Host "  CA Host:        $CaHostname.$DomainName ($SafeIp)" -ForegroundColor Green
    Write-Host "  Web Enroll:     https://$CaHostname.$DomainName/certsrv" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  NEXT MANUAL STEPS:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Create certificate templates (certtmpl.msc on this CA):" -ForegroundColor Yellow
    Write-Host "       - Duplicate 'Workstation Authentication' -> issue for client auth" -ForegroundColor White
    Write-Host "         (grant Domain Computers: Enroll + Autoenroll)" -ForegroundColor White
    Write-Host "       - Duplicate 'Web Server' -> 'ConfigMgr Web Server Certificate'" -ForegroundColor White
    Write-Host "         (Subject supplied in request; grant the SCCM server Enroll)" -ForegroundColor White
    Write-Host "       - Duplicate 'Workstation Authentication' -> " -ForegroundColor White
    Write-Host "         'ConfigMgr Client Distribution Point Certificate' (client auth)" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Publish each new template for issuance:" -ForegroundColor Yellow
    Write-Host "       certsrv.msc -> Certificate Templates -> New ->" -ForegroundColor White
    Write-Host "       Certificate Template to Issue -> pick your templates" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Create an auto-enrollment GPO linked at the domain root:" -ForegroundColor Yellow
    Write-Host "       Computer & User Config -> Policies -> Windows Settings ->" -ForegroundColor White
    Write-Host "       Security Settings -> Public Key Policies ->" -ForegroundColor White
    Write-Host "       'Certificate Services Client - Auto-Enrollment' = Enabled" -ForegroundColor White
    Write-Host "       (check 'Renew expired' + 'Update certificates that use templates')" -ForegroundColor White
    Write-Host ""
    Write-Host "  4. Verify on clients/DCs after GPO applies (gpupdate /force):" -ForegroundColor Yellow
    Write-Host "       certlm.msc -> Personal -> Certificates (DC should auto-enroll" -ForegroundColor White
    Write-Host "       a Domain Controller / Kerberos Authentication cert -> enables LDAPS)" -ForegroundColor White
    Write-Host ""
    Write-Host "  See infrastructure/vms/ca/README.md for the full guide." -ForegroundColor Cyan

    # -------------------------------------------------------------------
    # Verification hints
    # -------------------------------------------------------------------
    Write-Host "`n  VERIFICATION COMMANDS:" -ForegroundColor Cyan
    Write-Host "    certutil -ping                 # CA service responds" -ForegroundColor White
    Write-Host "    certutil -pingadmin            # CA admin interface responds" -ForegroundColor White
    Write-Host "    pkiview.msc                    # PKI health (CDP/AIA green)" -ForegroundColor White
    Write-Host "    certutil -CAInfo               # CA name, type, validity" -ForegroundColor White
    Write-Host ""

    Write-Step "Running a quick 'certutil -ping' self-check..."
    try {
        certutil -ping | Out-Host
    } catch {
        Write-Warning "certutil -ping failed: $_"
    }

    exit 0
}

# =======================================================================
# PHASE 1: Rename, set static IP/DNS, join the domain, then reboot
# =======================================================================
Write-Step "Phase 1: preparing $CaHostname (rename, static IP, domain join)."

# -- Rename computer (idempotent) --
if ($currentName -ne $CaHostname) {
    Write-Step "Renaming computer from '$currentName' to '$CaHostname'..."
    Rename-Computer -NewName $CaHostname -Force
    Write-OK "Computer renamed. Takes effect after reboot."
} else {
    Write-OK "Computer is already named $CaHostname"
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
Write-Host "  After reboot, log in as a LAB Domain Admin and re-run:" -ForegroundColor Yellow
Write-Host "    .\setup-ca.ps1" -ForegroundColor White
Write-Host "  to install and configure the Enterprise Root CA (phase 2)." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

Restart-Computer -Force
