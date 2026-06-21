# Extensions – ProxmoxInfra Lab

This document describes the optional extension VMs that build on top of the base three-VM lab. Each extension is opt-in: enable it by setting the corresponding Terraform boolean in `terraform.tfvars`, then run `terraform apply` and follow the linked setup guide.

---

## Extension Overview

### Windows Lab Extensions

| VM | VMID | Toggle | Hostname | IP | Role | Guide |
|---|---|---|---|---|---|---|
| pfSense router | 100 | `enable_pfsense` | lab-fw01 | 10.10.10.1 (LAN) | NAT internet, firewall, VLAN-ready | [pfsense/README.md](../infrastructure/vms/pfsense/README.md) |
| Enterprise Root CA | 104 | `enable_ca` | lab-ca01 | 10.10.10.30 | AD CS PKI for SCCM/LDAPS/IIS | [ca/README.md](../infrastructure/vms/ca/README.md) |
| Secondary DC | 105 | `enable_dc02` | lab-dc02 | 10.10.10.11 | AD replication, DNS redundancy, FSMO | [dc02/README.md](../infrastructure/vms/dc02/README.md) |
| Azure AD Connect | 106 | `enable_aadconnect` | lab-aadc01 | 10.10.10.40 | Entra ID sync, Hybrid AADJ, co-mgmt | [azuread-connect/README.md](../infrastructure/azuread-connect/README.md) |
| WSUS disk on SCCM | – | `wsus_content_disk_size` | lab-sccm01 | – | Extra disk (E:\\WSUS) for Software Update Point | [sccm/README.md](../infrastructure/vms/sccm/README.md#software-update-point) |

### NAS / Open-Source Services

| VM | VMID | Toggle | Hostname | IP | Role | Guide |
|---|---|---|---|---|---|---|
| TrueNAS Scale | 120 | `enable_nas` | lab-nas01 | 10.10.10.70 | ZFS NAS, SMB/NFS/iSCSI, backup target | [nas/README.md](../infrastructure/vms/nas/README.md) |
| Nginx Proxy Manager | 121 | `enable_nginx` | lab-nginx01 | 10.10.10.71 | Reverse proxy + SSL termination | [nginx/README.md](../infrastructure/vms/nginx/README.md) |
| Paperless-ngx | 122 | `enable_paperless` | lab-paperless01 | 10.10.10.72 | Document management, OCR, search | [paperless/README.md](../infrastructure/vms/paperless/README.md) |
| GitLab CE | 123 | `enable_gitlab` | lab-gitlab01 | 10.10.10.73 | Source control, CI/CD, GitLab Pages | [gitlab/README.md](../infrastructure/vms/gitlab/README.md) |

Also optional — not a VM:

| Component | Guide |
|---|---|
| Packer golden-image templates | [packer/README.md](../infrastructure/packer/README.md) |
| Docusaurus documentation site | [docusaurus-site/](../docusaurus-site/) |

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
    ├─ 6. Azure AD Connect (enable_aadconnect)
    │       Requires: pfSense (internet to Entra), DC01, CA (optional but recommended for LDAPS).
    │       Required before: Hybrid AADJ, Intune co-management.
    │
    │
    │   ── NAS / Open-Source Services ─────────────────────────────────────
    │
    ├─ 7. TrueNAS Scale NAS (enable_nas)
    │       Deploy first in the NAS group — other services can use it for storage.
    │       Configuration is done via the TrueNAS web UI (not Ansible).
    │       Required before: Paperless consume-from-NAS, GitLab backups-to-NAS.
    │
    ├─ 8. Nginx Proxy Manager (enable_nginx)
    │       Reverse proxy for all HTTP services in the lab.
    │       Deploy before finalising URLs for GitLab and Paperless.
    │
    ├─ 9. GitLab CE (enable_gitlab)
    │       Source control, CI/CD, GitLab Pages.
    │       After deploy, push docusaurus-site/ to publish the docs portal.
    │
    └─ 10. Paperless-ngx (enable_paperless)
            Document management with OCR.
            Optionally mount NAS SMB share as the consume directory.
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

---

## 7 – TrueNAS Scale NAS

**Toggle:** `enable_nas = true`

TrueNAS Scale is an open-source NAS OS (Debian + OpenZFS) that provides enterprise-grade storage for the lab. It acts as a central storage backbone: Paperless-ngx consumes documents from a NAS share, GitLab writes backups to the NAS, and general file shares are accessible via SMB from all lab VMs.

**What it provides:**
- ZFS pool with copy-on-write, checksums, snapshots, and optional RAIDZ
- SMB shares (Windows-compatible, AD-integrated)
- NFS shares (Linux-compatible)
- iSCSI block storage (optional)
- Built-in Docker app catalog (run additional containers on the NAS itself)
- Periodic ZFS snapshots for point-in-time recovery

**Terraform creates:**
- scsi0 (32 GB) — TrueNAS OS disk (separate from data)
- scsi1 (`nas_data_disk_size` GB, default 500 GB) — raw data pool disk

**After install:** Configure everything via the TrueNAS web UI at `http://10.10.10.70`. See `infrastructure/vms/nas/README.md` for the full step-by-step.

---

## 8 – Nginx Proxy Manager

**Toggle:** `enable_nginx = true`

Nginx Proxy Manager (NPM) is an open-source reverse proxy with a clean web UI. It routes HTTP/HTTPS traffic from a single IP (`10.10.10.71`) to internal lab services by hostname, and manages SSL certificates.

**What it enables:**
- `gitlab.lab.local` → lab-gitlab01 (VM 123)
- `paperless.lab.local` → lab-paperless01 (VM 122)
- `nas.lab.local` → lab-nas01 (VM 120)
- `*.pages.lab.local` → GitLab Pages (Docusaurus docs)
- Self-signed or Let's Encrypt SSL certificates per host

**Setup:** Run `ansible-playbook ansible/playbooks/nginx.yml`, then configure proxy hosts via the NPM web UI at `http://10.10.10.71:81`. Full steps in `infrastructure/vms/nginx/README.md`.

---

## 9 – GitLab CE

**Toggle:** `enable_gitlab = true`

GitLab Community Edition is the lab's source of truth. It hosts all git repositories, Issues, Merge Requests, and CI/CD pipelines — and specifically publishes the **Docusaurus documentation site** via GitLab Pages.

**The Docusaurus workflow:**
```
Design (Claude Design mockups)
    → Export as PNG/SVG
    → Commit to docusaurus-site/static/img/claude-design/
    → Document in docusaurus-site/docs/design/
    → git push → GitLab CI builds Docusaurus
    → GitLab Pages publishes the site
```

The `docusaurus-site/` directory in this repo is a ready-to-push Docusaurus project. After GitLab is running, create a new project and push it as described in `infrastructure/vms/gitlab/README.md`.

**Resource requirement:** 8 GB RAM minimum (GitLab is memory-intensive). The `docker-compose.yml` uses reduced Puma/Sidekiq workers to fit within the VM's 8 GB.

Full steps in `infrastructure/vms/gitlab/README.md`.

---

## 10 – Paperless-ngx

**Toggle:** `enable_paperless = true`

Paperless-ngx is an open-source Document Management System (DMS). Drop a scanned PDF into the consume folder and Paperless runs OCR (Tesseract), extracts text, auto-tags by correspondent and document type, and makes everything full-text searchable.

**Stack:** Paperless web + PostgreSQL + Redis, all running via Docker Compose.

**Integration with TrueNAS:**
- Mount the NAS `paperless` SMB share as the consume directory
- Paperless auto-imports new documents from the NAS share
- Exports/backups are written back to the NAS

**Setup:** Run `ansible-playbook ansible/playbooks/paperless.yml`. Full steps in `infrastructure/vms/paperless/README.md`.

---

## 11 – Docusaurus Documentation Site

**Not a VM — a GitLab project.** See `docusaurus-site/` in the repo root.

The `docusaurus-site/` directory is a complete, ready-to-run Docusaurus 3 project pre-configured for GitLab Pages deployment. It serves as the lab's documentation portal and knowledge base.

**Structure:**
```
docusaurus-site/
├─ docs/
│  ├─ product/       # Vision, roadmap, user stories
│  ├─ design/        # Claude Design exports, design system
│  ├─ architecture/  # ADRs, system overview
│  ├─ api/           # API documentation
│  └─ runbooks/      # Operational runbooks
├─ static/img/claude-design/  # Design mockups and exports
├─ .gitlab-ci.yml    # Builds and deploys to GitLab Pages
└─ docusaurus.config.ts
```

**To publish:**
1. Create a project on lab-gitlab01
2. `cd docusaurus-site && git init && git push` to that project
3. Update `url` and `baseUrl` in `docusaurus.config.ts`
4. GitLab CI auto-deploys on every push to `main`
