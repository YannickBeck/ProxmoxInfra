#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure lab-rootca01 (VM 112) as an OFFLINE STANDALONE Root CA
    for the two-tier lab PKI. This machine stays in a WORKGROUP and is
    powered off after it has signed the issuing (sub) CA certificate.

.DESCRIPTION
    This script is two-phase, mirroring setup-ca.ps1 / setup-dc02.ps1. It
    detects which phase it is in by checking the computer name and whether
    AD CS has already been configured.

      PHASE 1 (computer not named LAB-ROOTCA01):
        - Renames the computer to LAB-ROOTCA01
        - Sets a static IPv4 address (10.10.10.31) on the vmbr1 adapter
        - Does NOT join a domain (a Standalone Root CA stays in a workgroup
          so its private key never lives on a domain-reachable machine)
        - Reboots the server

      PHASE 2 (computer named LAB-ROOTCA01, AD CS not yet configured):
        - Installs the ADCS-Cert-Authority feature + management tools
        - Configures a STANDALONE Root CA (LAB-Offline-Root-CA), 4096-bit
          key, SHA256, 20-year validity
        - Configures a LONG CRL publication interval (default 52 weeks) and
          disables delta CRLs, because an offline root publishes its CRL
          rarely and by hand
        - Sets the validity period for certificates the root issues (the
          sub-CA cert) to 10 years
        - Restarts certsvc and publishes a fresh CRL
        - Exports the root .crt and .crl to C:\PKI_Export so they can be
          transferred to the issuing CA and into AD

    Every step is idempotent: re-running the script skips work that is
    already done (rename, IP, feature install, CA config, export).

    AFTER PHASE 2: keep this machine OFFLINE. You only power it on again to
    sign / renew the issuing CA certificate or to re-publish the root CRL.

.PARAMETER SafeIp
    Static IPv4 address to assign to this server. Default: 10.10.10.31

.PARAMETER RootCaName
    Common name of the offline Standalone Root CA. Default: LAB-Offline-Root-CA

.PARAMETER ValidityYears
    Validity period (years) of the root CA's own self-signed certificate.
    Default: 20

.PARAMETER CrlPeriodWeeks
    CRL publication interval in weeks. A long value suits an offline root
    that publishes its CRL manually and infrequently. Default: 52

.PARAMETER IssuedValidityYears
    Validity period (years) the root grants to certificates it ISSUES — i.e.
    the issuing/sub CA certificate. Default: 10

.EXAMPLE
    # Phase 1 (rename + static IP, then reboot — NO domain join):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-rootca.ps1

.EXAMPLE
    # Phase 2 (after reboot, as local Administrator):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup-rootca.ps1

.NOTES
    Run from an elevated PowerShell session on lab-rootca01.
    Requires Windows Server 2022 with the VirtIO network driver installed.
    This server is intentionally NOT domain-joined and has no internet need.
    Companion guide: ..\README.md   (two-tier PKI build sequence)
#>

param(
    [string]$SafeIp              = "10.10.10.31",
    [string]$RootCaName          = "LAB-Offline-Root-CA",
    [int]$ValidityYears          = 20,
    [int]$CrlPeriodWeeks         = 52,
    [int]$IssuedValidityYears    = 10
)

$ErrorActionPreference = "Stop"

# Fixed values for this role
$RootHostname = "LAB-ROOTCA01"
$SubnetPrefix = 24
$ExportDir    = "C:\PKI_Export"
$CertEnrollDir = "C:\Windows\System32\CertSrv\CertEnroll"

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
$currentName = $env:COMPUTERNAME
$isNamed     = ($currentName -eq $RootHostname)

# The CA is considered configured if the certsvc service exists AND a CA name
# subkey is present under the Configuration registry path. Install-Adcs... is
# NOT idempotent and throws if a CA already exists, so we guard it.
$caConfigured = $false
$certSvc   = Get-Service -Name "CertSvc" -ErrorAction SilentlyContinue
$caRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
if ($certSvc -and (Test-Path $caRegPath)) {
    $caKey = Get-ChildItem -Path $caRegPath -ErrorAction SilentlyContinue
    if ($caKey) { $caConfigured = $true }
}

# We are in PHASE 2 once the machine is correctly named (it never joins a domain).
$phase2 = $isNamed

# =======================================================================
# PHASE 2: Install and configure AD CS (Standalone OFFLINE Root CA)
# =======================================================================
if ($phase2) {
    Write-Step "Phase 2 detected (named $RootHostname)."
    Write-Step "Installing and configuring the offline Standalone Root CA."

    # -- Install AD CS Windows features (idempotent) --
    Write-Step "Installing AD CS Windows features..."
    $features = @(
        "ADCS-Cert-Authority",   # Certification Authority role service
        "RSAT-ADCS-Mgmt"         # Management tools (certsrv.msc, pkiview.msc)
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

    # -- Configure the Standalone Root CA (idempotent guard) --
    Write-Step "Checking whether a Certification Authority is already configured..."
    if ($caConfigured) {
        Write-OK "A Certification Authority is already configured — skipping CA install."
    } else {
        Write-Step "Configuring Standalone Root CA '$RootCaName' (4096-bit, SHA256, $ValidityYears years)..."
        Import-Module ADCSDeployment

        # -CAType StandaloneRootCA: NOT AD-integrated (this box is a workgroup
        # member). A standalone root simply signs the subordinate CA request.
        # The private key lives only here and the machine stays offline, so the
        # root key cannot be compromised over the network.
        Install-AdcsCertificationAuthority `
            -CAType                  StandaloneRootCA `
            -CACommonName            $RootCaName `
            -KeyLength               4096 `
            -HashAlgorithmName       SHA256 `
            -ValidityPeriod          Years `
            -ValidityPeriodUnits     $ValidityYears `
            -CryptoProviderName      "RSA#Microsoft Software Key Storage Provider" `
            -Force

        Write-OK "Standalone Root CA '$RootCaName' configured."
    }

    # -------------------------------------------------------------------
    # Offline-root CRL + issued-cert validity configuration (idempotent —
    # certutil -setreg just overwrites the value each run, which is fine).
    # -------------------------------------------------------------------
    Write-Step "Configuring a long CRL publication interval for an offline root ($CrlPeriodWeeks weeks)..."
    # An offline root rarely publishes a CRL and copies it out by hand, so the
    # CRL must stay valid for a long time. Delta CRLs are disabled (0) because
    # an offline root cannot publish deltas on a schedule.
    certutil -setreg CA\CRLPeriodUnits $CrlPeriodWeeks | Out-Null
    certutil -setreg CA\CRLPeriod "Weeks"              | Out-Null
    certutil -setreg CA\CRLDeltaPeriodUnits 0          | Out-Null
    certutil -setreg CA\CRLDeltaPeriod "Days"          | Out-Null
    Write-OK "CRL period set to $CrlPeriodWeeks weeks; delta CRLs disabled."

    Write-Step "Setting the validity period for certificates the root ISSUES ($IssuedValidityYears years)..."
    # This governs the lifetime of the SUBORDINATE/issuing CA certificate that
    # this root will sign. 10 years is typical for an issuing CA under a 20-year root.
    certutil -setreg CA\ValidityPeriodUnits $IssuedValidityYears | Out-Null
    certutil -setreg CA\ValidityPeriod "Years"                   | Out-Null
    Write-OK "Issued-certificate validity set to $IssuedValidityYears years."

    # -- Restart certsvc so the registry changes take effect --
    Write-Step "Restarting the CA service (certsvc) to apply settings..."
    Restart-Service -Name CertSvc -Force
    Start-Sleep -Seconds 3
    Write-OK "certsvc restarted."

    # -- Publish a fresh CRL with the new (long) lifetime --
    Write-Step "Publishing a fresh CRL (certutil -CRL)..."
    try {
        certutil -CRL | Out-Host
        Write-OK "CRL published."
    } catch {
        Write-Warning "certutil -CRL reported: $_"
    }

    # -------------------------------------------------------------------
    # Export the root certificate + CRL for transfer to the issuing CA
    # and for publishing into Active Directory.
    # -------------------------------------------------------------------
    Write-Step "Exporting the root certificate and CRL to $ExportDir ..."
    if (-not (Test-Path $ExportDir)) {
        New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null
    }

    # The configured CA drops its .crt and .crl into CertEnroll. Copy them out.
    $crtFiles = Get-ChildItem -Path $CertEnrollDir -Filter "*.crt" -ErrorAction SilentlyContinue
    $crlFiles = Get-ChildItem -Path $CertEnrollDir -Filter "*.crl" -ErrorAction SilentlyContinue

    if ($crtFiles) {
        Copy-Item -Path $crtFiles.FullName -Destination $ExportDir -Force
        Write-OK "Copied $($crtFiles.Count) root .crt file(s) to $ExportDir"
    } else {
        Write-Warning "No .crt found in $CertEnrollDir. Export the root cert manually with:"
        Write-Warning "    certutil -ca.cert $ExportDir\$RootCaName.crt"
    }

    if ($crlFiles) {
        Copy-Item -Path $crlFiles.FullName -Destination $ExportDir -Force
        Write-OK "Copied $($crlFiles.Count) root .crl file(s) to $ExportDir"
    } else {
        Write-Warning "No .crl found in $CertEnrollDir. Re-run 'certutil -CRL' then copy *.crl."
    }

    # As a belt-and-braces export, also write the CA cert explicitly.
    try {
        certutil -ca.cert (Join-Path $ExportDir "$RootCaName.crt") | Out-Null
        Write-OK "Wrote $ExportDir\$RootCaName.crt (certutil -ca.cert)."
    } catch {
        Write-Warning "certutil -ca.cert reported: $_ (the CertEnroll copy above is usually enough)."
    }

    # -------------------------------------------------------------------
    # Summary and NEXT STEPS
    # -------------------------------------------------------------------
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  lab-rootca01 Offline Standalone Root CA configured!" -ForegroundColor Green
    Write-Host "  CA Common Name: $RootCaName" -ForegroundColor Green
    Write-Host "  CA Host:        $RootHostname ($SafeIp, WORKGROUP)" -ForegroundColor Green
    Write-Host "  Validity:       $ValidityYears years (root) / $IssuedValidityYears years (issued)" -ForegroundColor Green
    Write-Host "  CRL period:     $CrlPeriodWeeks weeks (delta disabled)" -ForegroundColor Green
    Write-Host "  Export folder:  $ExportDir (root .crt + .crl)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  NEXT STEPS (the two-tier cert exchange):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Transfer the root .crt and .crl from $ExportDir to the" -ForegroundColor Yellow
    Write-Host "     issuing CA (lab-subca01, 10.10.10.32). Use a shared folder," -ForegroundColor White
    Write-Host "     a copied VirtIO/ISO, or 'Copy-Item' over an SMB path." -ForegroundColor White
    Write-Host ""
    Write-Host "  2. On lab-subca01, run setup-subca.ps1 — it produces a .req" -ForegroundColor Yellow
    Write-Host "     request file. Bring that .req BACK to THIS root and submit it:" -ForegroundColor White
    Write-Host "       certreq -submit C:\PKI_Import\<subca>.req" -ForegroundColor White
    Write-Host "       # note the RequestId it prints, then issue it:" -ForegroundColor White
    Write-Host "       certutil -resubmit <RequestId>" -ForegroundColor White
    Write-Host "       # retrieve the signed cert:" -ForegroundColor White
    Write-Host "       certreq -retrieve <RequestId> C:\PKI_Export\subca.cer" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Copy subca.cer (plus the root .crt and .crl) back to" -ForegroundColor Yellow
    Write-Host "     lab-subca01 and install it there (certutil -installCert)." -ForegroundColor White
    Write-Host ""
    Write-Host "  4. KEEP THIS MACHINE OFFLINE afterwards. Power it on only to" -ForegroundColor Yellow
    Write-Host "     renew the issuing CA cert or to re-publish the root CRL" -ForegroundColor White
    Write-Host "     (every ~$CrlPeriodWeeks weeks: 'certutil -CRL', re-export, re-dspublish)." -ForegroundColor White
    Write-Host ""
    Write-Host "  See infrastructure/vms/pki/README.md for the full cert exchange." -ForegroundColor Cyan

    # -------------------------------------------------------------------
    # Verification hints
    # -------------------------------------------------------------------
    Write-Host "`n  VERIFICATION COMMANDS:" -ForegroundColor Cyan
    Write-Host "    certutil -CAInfo               # CA name, type (Standalone Root), validity" -ForegroundColor White
    Write-Host "    certutil -ping                 # CA service responds" -ForegroundColor White
    Write-Host "    certutil -getreg CA\CRLPeriod* # confirm the long CRL period" -ForegroundColor White
    Write-Host ""

    Write-Step "Running a quick 'certutil -CAInfo' self-check..."
    try {
        certutil -CAInfo | Out-Host
    } catch {
        Write-Warning "certutil -CAInfo failed: $_"
    }

    exit 0
}

# =======================================================================
# PHASE 1: Rename and set static IP (NO domain join), then reboot
# =======================================================================
Write-Step "Phase 1: preparing $RootHostname (rename, static IP — workgroup, no domain join)."

# -- Rename computer (idempotent) --
if ($currentName -ne $RootHostname) {
    Write-Step "Renaming computer from '$currentName' to '$RootHostname'..."
    Rename-Computer -NewName $RootHostname -Force
    Write-OK "Computer renamed. Takes effect after reboot."
} else {
    Write-OK "Computer is already named $RootHostname"
}

# -- Set static IPv4 on the vmbr1 adapter (idempotent) --
Write-Step "Setting static IP $SafeIp/$SubnetPrefix (no gateway/DNS — isolated offline root)..."
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

    # No -DefaultGateway: an offline root needs no gateway and no DNS. It only
    # ever talks to the issuing CA over a brief, manual file transfer.
    New-NetIPAddress `
        -InterfaceAlias $adapter.Name `
        -IPAddress      $SafeIp `
        -PrefixLength   $SubnetPrefix | Out-Null
    Write-OK "Static IP set: $SafeIp/$SubnetPrefix (no gateway)."
}

# -- NOTE: intentionally NO domain join. A Standalone Root CA stays workgroup. --
Write-OK "Skipping domain join by design — this is an offline Standalone Root CA (workgroup)."

# -- Reboot to apply rename; phase 2 runs on next login --
Write-Host "`n----------------------------------------" -ForegroundColor Yellow
Write-Host "  Phase 1 complete. Rebooting now." -ForegroundColor Yellow
Write-Host "  After reboot, log in as the LOCAL Administrator and re-run:" -ForegroundColor Yellow
Write-Host "    .\setup-rootca.ps1" -ForegroundColor White
Write-Host "  to install and configure the offline Standalone Root CA (phase 2)." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

Restart-Computer -Force
