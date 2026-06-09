# Extensions – ProxmoxInfra Lab

This document describes the optional extension VMs that build on top of the base three-VM lab. Each extension is opt-in: enable it by setting the corresponding Terraform boolean in `terraform.tfvars`, then run `terraform apply` and follow the linked setup guide.

---

## Extension Overview

| VM | VMID | Toggle | Hostname | IP | Role | Guide |
|---|---|---|---|---|---|---|
| pfSense router | 100 | `enable_pfsense` | lab-fw01 | 10.10.10.1 (LAN) | NAT internet, firewall, VLAN-ready | [pfsense/README.md](../infrastructure/vms/pfsense/README.md) |
| Enterprise Root CA | 104 | `enable_ca` | lab-ca01 | 10.10.10.30 | AD CS PKI for SCCM/LDAPS/IIS | [ca/README.md](../infrastructure/vms/ca/README.md) |
| Secondary DC | 105 | `enable_dc02` | lab-dc02 | 10.10.10.11 | AD replication, DNS redundancy, FSMO | [dc02/README.md](../infrastructure/vms/dc02/README.md) |
| Azure AD Connect | 106 | `enable_aadconnect` | lab-aadc01 | 10.10.10.40 | Entra ID sync, Hybrid AADJ, co-mgmt | [azuread-connect/README.md](../infrastructure/azuread-connect/README.md) |
| WSUS disk on SCCM | – | `wsus_content_disk_size` | lab-sccm01 | – | Extra disk (E:\\WSUS) for Software Update Point | [sccm/README.md](../infrastructure/vms/sccm/README.md#software-update-point) |

Also optional — not a VM:

| Component | Guide |
|---|---|
| Packer golden-image templates | [packer/README.md](../infrastructure/packer/README.md) |

---

## Recommended Build Order

The extensions have dependencies. If you are enabling multiple at once, deploy in this sequence:

```
Base lab (DC01 + SCCM + Client)
    │
    ├─ 1. pfSense (enable_pfsense)
    │       Provides NAT internet to all lab VMs.
    │       Required before: WSUS sync, Azure AD Connect, ADK downloads.
    │
    ├─ 2. Packer (optional, replaces manual ISO install)
    │       Run packer build before terraform apply with clones.
    │
    ├─ 3. Enterprise Root CA (enable_ca)
    │       Requires: DC01 up and domain ready.
    │       Required before: SCCM PKI mode, LDAPS, proper Intune certs.
    │
    ├─ 4. Secondary DC (enable_dc02)
    │       Requires: DC01 healthy, domain functioning.
    │       Independent of CA, but deploy CA first if LDAPS on both DCs is wanted.
    │
    ├─ 5. WSUS disk (wsus_content_disk_size > 0) + setup-wsus-sup.ps1
    │       Requires: pfSense (internet for sync), DC01 (domain), SCCM installed.
    │
    └─ 6. Azure AD Connect (enable_aadconnect)
            Requires: pfSense (internet to Entra), DC01, CA (optional but recommended for LDAPS).
            Required before: Hybrid AADJ, Intune co-management.
```

---

## 1 – pfSense CE Router / Firewall

**Toggle:** `enable_pfsense = true`

pfSense replaces the Proxmox host as the 10.10.10.1 gateway. Once installed, lab VMs gain outbound internet access via NAT — needed for SCCM ADK downloads, Windows Update, and Azure AD Connect syncing to Entra.

**Key action after enabling:** Remove the IP `10.10.10.1/24` from the Proxmox host's `vmbr1` interface to avoid a gateway conflict. See the pfSense README for the exact `/etc/network/interfaces` edit.

**VLAN path (advanced):** pfSense supports VLAN trunk ports on vmbr1, allowing you to later split the flat 10.10.10.0/24 lab into separate VLANs for servers, clients, and management without changing the Proxmox bridge configuration.

---

## 2 – Packer Golden-Image Templates

**No Terraform toggle — a separate build step.**

Packer builds a fully unattended Windows template VM (e.g. VMID 9000 for Server 2022, 9001 for Win11) that Terraform can then *clone* instead of attaching ISOs. This removes the manual Windows installation step entirely.

```bash
cd infrastructure/packer
packer init .
packer build .
```

Afterwards, switch the Terraform resources to use a `clone` block pointing at the template VMID. See `infrastructure/packer/README.md` for details.

---

## 3 – Enterprise Root CA (AD CS)

**Toggle:** `enable_ca = true`

An internal PKI makes the lab enterprise-realistic. Without a CA, SCCM runs in Enhanced HTTP mode (self-signed), LDAPS is unavailable, and Intune co-management lacks proper client certs.

**What it enables:**
- SCCM PKI mode (trusted HTTPS for management point / distribution point)
- LDAPS on port 636 for both DCs (secure AD queries from Intune, Azure AD Connect)
- Client authentication certificates auto-enrolled via GPO
- Web server certificates for IIS, WSUS, and any internal HTTPS services

**Setup:** Run `setup-ca.ps1` (two-phase: domain join, then AD CS install), then configure certificate templates in `certtmpl.msc` and enable auto-enrollment via a GPO. Full steps in `infrastructure/vms/ca/README.md`.

---

## 4 – Secondary Domain Controller

**Toggle:** `enable_dc02 = true`

Promotes a second DC at 10.10.10.11 into the `lab.local` domain. Adds realism and enables practice scenarios:

- **AD replication**: monitor with `repadmin /replsummary`
- **DNS redundancy**: configure 10.10.10.11 as secondary DNS in the DHCP scope
- **FSMO role transfer and seizure**: practice with `Move-ADDirectoryServerOperationMasterRole`
- **DC failure simulation**: shut down DC01, verify that clients and SCCM still work

**Setup:** Run `setup-dc02.ps1` (two-phase) or the `ansible/playbooks/dc02.yml` playbook. Full steps in `infrastructure/vms/dc02/README.md`.

---

## 5 – WSUS / Software Update Point on SCCM

**Toggle:** `wsus_content_disk_size = 150` (or any GB value > 0)

Adds an extra data disk to lab-sccm01 for Windows Server Update Services content. WSUS is installed on the same server as SCCM and configured exclusively through the SCCM console as the **Software Update Point** site system role — never directly via the WSUS console.

**What it enables in SCCM:**
- Windows Update deployment to lab clients
- Update compliance reporting
- Maintenance window + deployment ring testing (Pilot / Production)
- Automatic Deployment Rules (ADR) for Endpoint Protection definitions

**Setup:** Run `setup-wsus-sup.ps1` or `ansible/playbooks/wsus.yml`, then add the Software Update Point role in the SCCM console. Full steps appended to `infrastructure/vms/sccm/README.md`.

---

## 6 – Azure AD Connect / Entra Connect Sync

**Toggle:** `enable_aadconnect = true`

Synchronises `lab.local` Active Directory into Microsoft Entra ID (formerly Azure AD), enabling **Hybrid Azure AD Join** and **Intune co-management** with SCCM. Without this, Intune management is cloud-only (no on-prem AD awareness).

**What it enables:**
- Hybrid Azure AD Join for Windows 11 clients (`dsregcmd /status` → AzureAdJoined: YES + DomainJoined: YES)
- Intune enrollment of domain-joined devices
- SCCM ↔ Intune co-management (slide workloads to Intune)
- Seamless SSO from the intranet

**Important:** The `lab.local` domain is non-routable, so users need an alternative UPN suffix (e.g. `<tenant>.onmicrosoft.com` or a verified custom domain) before sync. The `install-aadconnect.ps1` script handles adding the UPN suffix to the AD forest and provides a helper to bulk-update user UPNs.

**Requires:** A Microsoft Entra / M365 tenant (free dev tenant works for hybrid join; Intune needs a license or trial), and internet access from lab-aadc01 (via pfSense NAT).

Full steps in `infrastructure/azuread-connect/README.md`.
