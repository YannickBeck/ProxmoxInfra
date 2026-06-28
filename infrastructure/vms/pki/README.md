# Two-Tier PKI – Offline Root CA + Enterprise Issuing CA Setup Guide

This document covers building a **two-tier Public Key Infrastructure (PKI)** for
the `lab.local` domain: an **offline Standalone Root CA** (`lab-rootca01`, VM 112)
that signs a single subordinate certificate, and an online **Enterprise
Subordinate / Issuing CA** (`lab-subca01`, VM 113) that does all day-to-day
certificate issuance. This is the **realistic enterprise alternative** to the
single-tier Enterprise Root CA (`lab-ca01`, VM 104, `enable_ca`).

Both VMs are provisioned by Terraform only when the boolean variable
`enable_twotier_pki` is set to `true` (default **false**).

> **Do NOT enable both `enable_ca` and `enable_twotier_pki`.** They are two
> different designs for the **same role** (the lab's internal PKI). Pick one:
> the simple single-tier CA (VM 104) **or** this two-tier hierarchy (VMs 112 +
> 113). Running both would give the lab two competing roots.

---

## VM Facts

### lab-rootca01 — Offline Standalone Root CA

| Item | Value |
|---|---|
| VM ID | 112 |
| Hostname | `lab-rootca01` / `LAB-ROOTCA01` |
| IP address | `10.10.10.31/24` |
| Gateway | none (isolated, offline) |
| DNS | none |
| Domain | **WORKGROUP** (NOT domain-joined) |
| Role | **Offline Standalone Root CA** |
| CA common name | `LAB-Offline-Root-CA` |
| Key / hash | 4096-bit RSA, SHA256 |
| Validity | **20 years** (root); issues the sub-CA cert for 10 years |
| Normal state | **Powered OFF** after issuing the sub-CA cert |

### lab-subca01 — Enterprise Subordinate / Issuing CA

| Item | Value |
|---|---|
| VM ID | 113 |
| Hostname | `lab-subca01` / `LAB-SUBCA01` |
| IP address | `10.10.10.32/24` |
| Gateway | `10.10.10.1` (lab-fw01) |
| DNS | `10.10.10.10` (lab-dc01) |
| Domain | `lab.local` (NetBIOS `LAB`) — domain-joined |
| Role | **Enterprise Subordinate (Issuing) CA**, Web Enrollment |
| CA common name | `LAB-Issuing-CA` |
| Key / hash | 4096-bit RSA, SHA256 |
| Validity | **10 years** (signed by the offline root) |
| Normal state | Online — handles all certificate issuance |

Enable via `terraform.tfvars`:

```hcl
enable_twotier_pki = true
```

---

## Why Two-Tier?

A two-tier hierarchy — an **offline root** plus an **online issuing CA** — is the
**enterprise standard** for AD CS, and it exists to protect the most valuable
thing in the PKI: the **root private key**.

- **Root key protection.** The root CA's private key is the trust anchor for
  *every* certificate in the environment. If it is compromised, the entire PKI
  must be torn down and rebuilt. In a two-tier design the root is a **standalone,
  workgroup, offline** machine: it is powered off and disconnected from the
  network, so its private key **cannot be compromised over the network**. It is
  switched on only briefly to sign or renew the issuing CA certificate (and to
  re-publish its long-lived CRL).
- **The issuing CA does the day-to-day work.** All routine issuance —
  auto-enrolled computer/user certs, LDAPS DC certs, SCCM/IIS web certs — is
  handled by the **online Enterprise issuing CA**, which *is* AD-integrated and
  therefore supports certificate **templates** and **auto-enrollment**.
- **Compromise containment & clean revocation.** If the *issuing* CA is ever
  compromised, you revoke its single certificate at the root and stand up a new
  issuing CA — without rebuilding the trust anchor that every machine already
  trusts.

### Contrast with the single-tier CA (VM 104, `enable_ca`)

| | **Single-tier Enterprise Root CA** (VM 104, `enable_ca`) | **Two-tier PKI** (VMs 112 + 113, `enable_twotier_pki`) |
|---|---|---|
| Tiers | One CA: an Enterprise Root that also issues | Offline Standalone Root **+** online Enterprise Issuing CA |
| Root key exposure | Root is **online**, domain-joined, issuing daily | Root is **offline / workgroup / powered off** — protected |
| Realism | Simpler; fine for a quick lab | **Mirrors production** enterprise PKI design |
| Setup effort | Lower (one VM, one script) | Higher (two VMs + a manual cert exchange) |
| Templates / auto-enrollment | Yes (the root is Enterprise) | Yes (on the **issuing** CA) |
| Best for | Fast PKI, learning the basics | Practising the real-world offline-root pattern |

> **Reminder:** enable **exactly one** of `enable_ca` *or* `enable_twotier_pki`.

---

## Hierarchy Diagram

```
                 ┌──────────────────────────────────────────┐
                 │      lab-rootca01  (VM 112)                │
                 │      LAB-Offline-Root-CA                   │
                 │      Standalone Root CA                    │
                 │      WORKGROUP · 10.10.10.31 · OFFLINE     │
                 │      4096-bit · SHA256 · 20-year validity  │
                 └────────────────────┬─────────────────────┘
                                      │  signs the sub-CA certificate
                                      │  (issued for 10 years), then
                                      │  the root is powered OFF.
                                      ▼
                 ┌──────────────────────────────────────────┐
                 │      lab-subca01  (VM 113)                 │
                 │      LAB-Issuing-CA                        │
                 │      Enterprise Subordinate (Issuing) CA   │
                 │      lab.local · 10.10.10.32 · ONLINE      │
                 │      4096-bit · SHA256 · 10-year validity  │
                 └────────────────────┬─────────────────────┘
                                      │  issues end-entity certs
            ┌─────────────────────────┼─────────────────────────┐
            ▼                         ▼                         ▼
   DC / LDAPS certs        SCCM / IIS web certs      Workstation / user
   (lab-dc01, lab-dc02)    (lab-sccm01 MP/DP/SUP)    client-auth certs
```

---

## Prerequisites

Before starting, ensure:

- [ ] **lab-dc01 is running** and the `lab.local` domain is available (for the
      issuing CA's domain join and AD publication)
- [ ] DNS resolution works from `lab-subca01` (`Resolve-DnsName lab.local` returns the DC)
- [ ] Both VMs (112 + 113) have been created by Terraform (`enable_twotier_pki = true`)
      and Windows Server 2022 is installed on each
- [ ] VirtIO storage + network drivers are installed on both VMs
- [ ] You can log in as a **Domain Admin / Enterprise Admin** of `lab.local`
      (required to configure the Enterprise issuing CA and publish the root into AD)
- [ ] A way to **move files** between the offline root and the issuing CA
      (a temporary shared folder, a copied ISO, or a brief SMB copy)
- [ ] `enable_ca` is **NOT** also set (do not run both PKI designs)

---

## Build Sequence

### 1 — Build / boot both VMs

Set `enable_twotier_pki = true` in `terraform.tfvars`, then:

```bash
cd /home/user/ProxmoxInfra/infrastructure/proxmox/terraform
terraform apply
qm start 112    # lab-rootca01
qm start 113    # lab-subca01
```

Install **Windows Server 2022 Standard (Desktop Experience)** on each (load the
VirtIO SCSI + NetKVM drivers, set the local Administrator password, change the
placeholder).

### 2 — Root CA (VM 112): install, DO NOT domain-join

The root CA stays in a **WORKGROUP**. Copy `setup-rootca.ps1` to VM 112 and run
it from an **elevated** PowerShell session (two phases):

```powershell
# Phase 1 — rename + static IP (10.10.10.31), then reboot (no domain join)
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-rootca.ps1

# Phase 2 — after reboot, as the LOCAL Administrator
.\setup-rootca.ps1
```

Phase 2:

1. Installs `ADCS-Cert-Authority` + management tools
2. Configures a **Standalone Root CA** `LAB-Offline-Root-CA` (4096-bit, SHA256, 20 years)
3. Sets a **long CRL publication interval** for an offline root (default **52
   weeks**) and **disables delta CRLs** — an offline root publishes its CRL
   rarely and copies it out **manually**
4. Sets the validity of certificates the root **issues** (the sub-CA cert) to **10 years**
5. Restarts `certsvc` and publishes a fresh CRL (`certutil -CRL`)
6. **Exports** the root `.crt` and `.crl` to `C:\PKI_Export\`

> **Ansible alternative:** `ansible-playbook -i inventory/lab.yml playbooks/pki-root.yml`

Transfer `C:\PKI_Export\*.crt` and `*.crl` from the root to the issuing CA now
(you will need them in step 4).

### 3 — Sub CA (VM 113): domain-join, generate the request

Copy `setup-subca.ps1` to VM 113 and run it (two phases):

```powershell
# Phase 1 — rename + static IP (10.10.10.32) + domain join, then reboot
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-subca.ps1 -DomainJoinCredential (Get-Credential)

# Phase 2 — after reboot, as a Domain/Enterprise Admin
.\setup-subca.ps1
```

Phase 2 installs `ADCS-Cert-Authority`, `ADCS-Web-Enrollment` + tools and runs
`Install-AdcsCertificationAuthority -CAType EnterpriseSubordinateCA`. Because the
parent (offline root) is **not online**, the cmdlet cannot fetch a signed cert —
it instead **emits a request file** and the CA service stays **stopped**:

```
C:\LAB-SUBCA01.lab.local_LAB-Issuing-CA.req
```

The script reports the exact `.req` path and **pauses** with the cert-exchange
instructions. **This pause is expected** — the issuing CA cannot start until the
offline root signs that request.

> **Ansible alternative:** `ansible-playbook -i inventory/lab.yml playbooks/pki-sub.yml`

### 4 — THE CERT EXCHANGE (the crux)

This is the step that ties the two tiers together. Do it precisely, in order.

**a. Take the `.req` to the offline root.** Copy
`C:\LAB-SUBCA01.lab.local_LAB-Issuing-CA.req` from the issuing CA to the **offline
root** (e.g. into `C:\PKI_Import\` on `lab-rootca01`). Power the root on for this.

**b. On the OFFLINE ROOT — submit, issue, retrieve:**

```powershell
# Submit the request — a Standalone CA leaves it PENDING (does not auto-issue).
certreq -submit C:\PKI_Import\LAB-SUBCA01.lab.local_LAB-Issuing-CA.req
#   -> note the "RequestId" it prints, e.g. 2

# Issue (approve) the pending request:
certutil -resubmit 2

# Retrieve the signed issuing-CA certificate:
certreq -retrieve 2 C:\PKI_Export\subca.cer
```

**c. Bring the issued cert + root files BACK to the issuing CA.** Copy these from
the root's `C:\PKI_Export\` to `lab-subca01` (e.g. `C:\PKI_Import\`):

- `subca.cer` — the signed issuing-CA certificate
- `LAB-Offline-Root-CA.crt` — the root certificate
- `LAB-Offline-Root-CA.crl` — the root CRL

**d. On the ISSUING CA — trust the root, publish it to AD, install the cert, start the service:**

```powershell
# Add the root to the local machine + AD trust so the chain builds:
certutil -addstore -f Root C:\PKI_Import\LAB-Offline-Root-CA.crt
certutil -dspublish -f C:\PKI_Import\LAB-Offline-Root-CA.crt RootCA
certutil -dspublish -f C:\PKI_Import\LAB-Offline-Root-CA.crl

# Install the signed issuing-CA cert into THIS CA, then start it:
certutil -installCert C:\PKI_Import\subca.cer
Start-Service certsvc
```

**e. Finish the issuing CA.** Re-run `.\setup-subca.ps1` once more — it detects the
CA service is now **running**, configures **Web Enrollment**, and prints the
verification commands.

### 5 — Power off the root CA and keep it offline

```powershell
# On the Proxmox host
qm stop 112
```

Leave `lab-rootca01` **powered off**. Switch it on again only to renew the issuing
CA certificate or to **re-publish the root CRL** (roughly every 52 weeks: on the
root run `certutil -CRL`, re-export the fresh `.crl`, copy it back, and
`certutil -dspublish -f LAB-Offline-Root-CA.crl`).

---

## Post-Setup (on the ISSUING CA)

Everything below happens on **`lab-subca01`** (the issuing CA) — the offline root
issues nothing but the sub-CA cert. These steps mirror the single-tier guide;
where the steps are identical, **reference** `infrastructure/vms/ca/README.md`
rather than duplicating them.

### Certificate templates

Create templates with `certtmpl.msc` on `LAB-SUBCA01`, then **publish** them for
issuance (`certsrv.msc → Certificate Templates → New → Certificate Template to
Issue`). The full template table (ConfigMgr Web Server, Workstation
Authentication, ConfigMgr Client DP, LDAPS, code signing) is documented in
[`../ca/README.md`](../ca/README.md) — the same templates apply here, just on the
issuing CA instead of the single-tier root.

### Auto-enrollment GPO

Create a GPO linked at the **domain root** enabling **Certificate Services Client
- Auto-Enrollment** for both Computer and User scopes. See
[`../ca/README.md`](../ca/README.md) (Auto-Enrollment GPO) for the exact GPMC steps.

### SCCM / LDAPS / web certificates

The consuming services are identical to the single-tier design — the issuing CA
provides the **ConfigMgr Web Server** cert (SCCM HTTPS/PKI), **Workstation
Authentication** for clients, and the **Domain Controller / Kerberos
Authentication** certs that light up **LDAPS** on the DCs. See
[`../ca/README.md`](../ca/README.md) (LDAPS, "Which Lab Service Consumes Which
Certificate") for the per-service details.

---

## Verification

Run these on `LAB-SUBCA01` (and the root where noted):

| Command / tool | What it checks |
|---|---|
| `certutil -CAInfo` | CA name, type (**Enterprise Subordinate** on the issuing CA; **Standalone Root** on the root), validity |
| `certutil -ping` | The CA service (`certsvc`) responds (issuing CA online) |
| `certutil -pingadmin` | The CA **admin** interface responds (needed for issuance management) |
| `pkiview.msc` (Enterprise PKI) | The **whole hierarchy** — both the root and the issuing CA, with **CDP/AIA** for each — should be **OK (green)** |
| `Get-CertificationAuthority` (PSPKI) | Lists the CA(s) the lab knows about (install with `Install-Module PSPKI`) |
| `certsrv.msc` → **Issued Certificates** | Confirms the issuing CA is actually issuing to clients/DCs |
| `certutil -getreg CA\CRLPeriod*` (on the root) | Confirms the long offline-root CRL period (52 weeks) |

> In an isolated lab, `pkiview.msc` may flag the default **HTTP CDP/AIA** URLs as
> unreachable. That is expected; either ignore it or trim the unreachable
> CDP/AIA URLs in `certsrv.msc → CA Properties → Extensions`. The **LDAP** CDP/AIA
> entries (published into AD by the cert exchange in step 4) should be green.

---

## Troubleshooting

- **Issuing CA service won't start (`certsvc` stopped after Phase 2)** — expected
  until the cert exchange is done. The CA needs its signed cert installed
  (`certutil -installCert subca.cer`) before `Start-Service certsvc` succeeds.
- **`certreq -retrieve` says the request is still pending** — you skipped the
  issue step on the root; run `certutil -resubmit <RequestId>` first.
- **`certutil -installCert` fails with a chain / trust error** — the root cert is
  not yet trusted on the issuing CA. Run `certutil -addstore -f Root
  LAB-Offline-Root-CA.crt` (and the `-dspublish` commands) *before*
  `-installCert`.
- **pkiview.msc shows the issuing CA's CDP/AIA red** — the root CRL is not
  published into AD or has expired. Re-publish on the root (`certutil -CRL`),
  copy the fresh `.crl` back, and `certutil -dspublish -f
  LAB-Offline-Root-CA.crl`.
- **`Install-AdcsCertificationAuthority` says a CA already exists** — the role is
  already configured; both scripts guard against this and skip. To start over you
  must uninstall the CA role first.

---

## Relevant Files

| Path | Purpose |
|---|---|
| `infrastructure/proxmox/terraform/main.tf` | VM 112 / 113 resources (gated by `enable_twotier_pki`) |
| `infrastructure/proxmox/terraform/variables.tf` | `enable_twotier_pki` variable |
| `infrastructure/vms/pki/powershell/setup-rootca.ps1` | Two-phase offline Standalone Root CA script (VM 112) |
| `infrastructure/vms/pki/powershell/setup-subca.ps1` | Two-phase Enterprise Issuing CA script (VM 113) |
| `infrastructure/vms/ca/README.md` | Single-tier Enterprise Root CA (VM 104) — templates / GPO / LDAPS reference |
| `infrastructure/vms/ca/powershell/setup-ca.ps1` | Single-tier CA script (the `enable_ca` alternative) |
