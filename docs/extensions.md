# Extensions – ProxmoxInfra Lab

This branch keeps the existing Windows lab and adds only the new logical pool model, TrueNAS and the dedicated Docusaurus VM. The former standalone Nginx Proxy Manager, Paperless and GitLab VMs are not part of this branch.

## Infrastructure overview

| Pool | VM/Host | Toggle | Rolle | Tools | Status |
|---|---|---|---|---|---|
| `pool-core-access` | Proxmox, Packer templates | – | Hypervisor and templates | Proxmox VE, Packer | Existing |
| `pool-network-firewall` | VM 107 OPNsense or VM 100 pfSense | `enable_opnsense` / `enable_pfsense` | Gateway, NAT, firewall | OPNsense, pfSense, optional AdGuard Home | Optional |
| `pool-sccm-lab` | VMs 101–106 and 108 | Per-VM toggles | Windows AD/SCCM lab | AD DS, SCCM, SQL, WSUS | Existing / optional |
| `pool-nas-storage` | VM 120 TrueNAS | `enable_nas` | ZFS, SMB, NFS and backup target | TrueNAS Scale; OpenMediaVault planned alternative | New |
| `pool-nas-storage` | VM 127 Docusaurus | `enable_docusaurus` | Independent documentation site | Docusaurus, Docker Compose, Nginx container | New |
| `pool-linux-clients` | VMs 110–111 | `enable_linux01` / `enable_linux02` | Linux lab systems | Ubuntu, Rocky Linux | Optional |
| `pool-platform-services` | VM 125/126 reserved | Future | Consolidated services and lightweight Git | Docker Compose, Forgejo; GitLab optional/heavy | Planned |
| `pool-ai-mcp-data` | VMIDs 130–139 reserved | `enable_ai_mcp_stack` | AI and automation | AnythingLLM, Open WebUI, Ollama, MCP, optional Qdrant/LiteLLM | Planned |
| `pool-observability-security` | VMIDs 140–149 reserved | `enable_observability_stack` | Monitoring and security | Beszel, Uptime Kuma; optional Grafana/Wazuh | Planned |
| `pool-backup-dr` | VMIDs 150–159 reserved | `enable_backup_dr` | Backup and disaster recovery | Proxmox Backup Server | Planned |
| `pool-devops-automation` | VMIDs 160–169 reserved | `enable_devops_automation` | CI and automation | Ansible, Semaphore, Terraform/OpenTofu, PowerShell 7 | Planned |

The complete pool tree and VMID registry are in [logical-pools.md](logical-pools.md).

| VM | VMID | Toggle | Hostname | IP | Role | Guide |
|---|---|---|---|---|---|---|
| pfSense router | 100 | `enable_pfsense` | lab-fw01 | 10.10.10.1 (LAN) | NAT internet, firewall, VLAN-ready | [pfsense/README.md](../infrastructure/vms/pfsense/README.md) |
| Enterprise Root CA | 104 | `enable_ca` | lab-ca01 | 10.10.10.30 | AD CS PKI for SCCM/LDAPS/IIS | [ca/README.md](../infrastructure/vms/ca/README.md) |
| Secondary DC | 105 | `enable_dc02` | lab-dc02 | 10.10.10.11 | AD replication, DNS redundancy, FSMO | [dc02/README.md](../infrastructure/vms/dc02/README.md) |
| Azure AD Connect | 106 | `enable_aadconnect` | lab-aadc01 | 10.10.10.40 | Entra ID sync (Connect Sync), Hybrid AADJ, co-mgmt | [azuread-connect/README.md](../infrastructure/azuread-connect/README.md) |
| Entra Cloud Sync | 109 | `enable_cloudsync` | lab-cloudsync01 | 10.10.10.41 | Lightweight cloud-side hybrid identity agent | [entra-cloudsync/README.md](../infrastructure/entra-cloudsync/README.md) |
| Two-tier PKI | 112 + 113 | `enable_twotier_pki` | lab-rootca01 / lab-subca01 | 10.10.10.31 / .32 | Offline Root CA + Enterprise Issuing CA | [pki/README.md](../infrastructure/vms/pki/README.md) |
| TrueNAS storage | 120 | `enable_nas` | lab-nas01 | 10.10.10.70 | ZFS, SMB/NFS, iSCSI, backup target | [nas/README.md](../infrastructure/vms/nas/README.md) |
| Docusaurus docs | 127 | `enable_docusaurus` | lab-docusaurus01 | 10.10.10.74 | Dedicated documentation VM | [docusaurus/README.md](../infrastructure/vms/docusaurus/README.md) |
| WSUS disk on SCCM | – | `wsus_content_disk_size` | lab-sccm01 | – | Extra disk (E:\\WSUS) for Software Update Point | [sccm/README.md](../infrastructure/vms/sccm/README.md#software-update-point) |

## Firewall choice

OPNsense is the recommended firewall. Set exactly one of the following:

---

## Recommended Build Order

The extensions have dependencies. If you are enabling multiple at once, deploy in this sequence:

```
Base lab (DC01 + SCCM + Client)
    │
    ├─ 1. Router — choose ONE (or neither, using Proxmox host as gateway):
    │       a) OPNsense (enable_opnsense, VM 107) — recommended; IDS/IPS support.
    │       b) pfSense (enable_pfsense, VM 100) — alternative.
    │       Required before: WSUS sync, Azure AD Connect, ADK downloads.
    │
    ├─ 2. NAS (enable_nas, VM 120) — optional; ZFS storage, SMB/NFS, backup target.
    │
    ├─ 3. Packer (optional, replaces manual ISO install)
    │       Run packer build before terraform apply with clones.
    │
    ├─ 4. PKI — choose ONE:
    │       a) Single-tier Enterprise Root CA (enable_ca, VM 104) — simple.
    │       b) Two-tier PKI (enable_twotier_pki, VMs 112+113) — enterprise-realistic.
    │       Requires: DC01 up and domain ready (for the Enterprise/Issuing CA).
    │       Required before: SCCM PKI mode, LDAPS, proper Intune certs.
    │
    ├─ 5. Secondary DC (enable_dc02)
    │       Requires: DC01 healthy, domain functioning.
    │       Independent of CA, but deploy CA first if LDAPS on both DCs is wanted.
    │
    ├─ 6. WSUS disk (wsus_content_disk_size > 0) + setup-wsus-sup.ps1
    │       Requires: router (internet for sync), DC01 (domain), SCCM installed.
    │
    ├─ 7. Hybrid identity — choose ONE (or both, to compare):
    │       a) Azure AD Connect / Entra Connect Sync (enable_aadconnect, VM 106) — full engine.
    │       b) Entra Cloud Sync (enable_cloudsync, VM 109) — lightweight cloud-side agent.
    │       Requires: internet to Entra, DC01, CA (recommended for LDAPS).
    │       Required before: Hybrid AADJ, Intune co-management.
    │
    └─ 8. Docusaurus (enable_docusaurus, VM 127) — anytime, independent of other VMs.
```

## Firewall choice

OPNsense is the recommended firewall. Set exactly one of the following:

```hcl
enable_opnsense = true
enable_pfsense  = false
```

Terraform rejects a configuration in which both firewalls are enabled because both would claim `10.10.10.1`.

## TrueNAS VM

Set `enable_nas = true` to create VM 120 (`lab-nas01`, `10.10.10.70`) with a separate OS and data disk. Installation and ZFS/share setup are documented in [infrastructure/vms/nas/README.md](../infrastructure/vms/nas/README.md).

## Dedicated Docusaurus VM

Set `enable_docusaurus = true` to create VM 127 (`lab-docusaurus01`, `10.10.10.74`). It runs independently of any Git platform:

```bash
cd /opt/proxmoxinfra
docker compose -f infrastructure/vms/docusaurus/docker/docker-compose.yml up -d --build
```

The deployment is described in [infrastructure/vms/docusaurus/README.md](../infrastructure/vms/docusaurus/README.md).

## Windows extensions detail

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

## 7 – Entra Cloud Sync (Lightweight Hybrid Identity)

**Toggle:** `enable_cloudsync = true`

Deploys `lab-cloudsync01` (VM 109, 10.10.10.41), a domain-joined member server running the **Microsoft Entra Cloud Sync** provisioning agent. Cloud Sync is Microsoft's modern, lightweight alternative to the full Entra Connect Sync engine (extension 6). It syncs `lab.local` users and groups into Microsoft Entra ID, but the sync configuration and rules live **in the cloud** (the Entra admin center) rather than in a heavyweight on-prem application.

**Cloud Sync vs Connect Sync — when to use which:**

| | Entra Cloud Sync (VM 109) | Entra Connect Sync (VM 106) |
|---|---|---|
| Agent footprint | Lightweight provisioning agent | Full sync engine + SQL LocalDB |
| Configuration | Cloud-side (Entra admin center) | On-prem (Synchronization Service Manager) |
| Multiple disconnected forests | Yes (native) | Complex (single instance) |
| High availability | Yes (multiple agents, active-active) | Staging server (active-passive) |
| Device writeback / Hybrid AADJ | Limited | Full support |
| Group writeback, exchange hybrid | Not supported | Supported |
| Best for | Simpler tenants, multi-forest, HA | Full feature set, device sync, complex filtering |

**Why deploy it in the lab:** Cloud Sync is the direction Microsoft is steering most hybrid customers. Standing up both VM 106 and VM 109 lets you compare the two approaches side by side — a genuinely useful exercise for an SCCM/Intune professional planning a real migration. (Do not sync the *same* objects with both agents simultaneously; scope them to different OUs if running both.)

**Important:** Like Connect Sync, Cloud Sync needs a **routable UPN suffix** — the non-routable `@lab.local` suffix must be supplemented with a verified domain or `<tenant>.onmicrosoft.com` suffix before sync.

**Setup:** `ansible-playbook -i inventory/lab.yml playbooks/cloudsync.yml` (or run `install-cloudsync.ps1`), then finish the configuration cloud-side. Full steps in `infrastructure/entra-cloudsync/README.md`.

**Requires:** A Microsoft Entra / M365 tenant and internet access from lab-cloudsync01 (via pfSense/OPNsense NAT).

---

## 8 – Two-Tier PKI (Offline Root CA + Enterprise Issuing CA)

**Toggle:** `enable_twotier_pki = true`

Deploys a realistic **two-tier PKI hierarchy** — the design used in virtually every production enterprise:

- **lab-rootca01** (VM 112, 10.10.10.31) – an **offline standalone Root CA** in a workgroup. It signs exactly one thing (the issuing CA's certificate) and is then powered off and kept offline so its private key can never be compromised over the network.
- **lab-subca01** (VM 113, 10.10.10.32) – a domain-joined **Enterprise Subordinate / Issuing CA** that handles all day-to-day certificate issuance (auto-enrollment, SCCM PKI, LDAPS, web server certs).

```
        ┌────────────────────────────┐
        │   lab-rootca01 (VM 112)    │   Offline · Workgroup
        │   Standalone Root CA       │   LAB-Offline-Root-CA
        │   20-year cert · OFFLINE   │   (powered off after signing)
        └─────────────┬──────────────┘
                      │ signs the issuing CA certificate (manual transfer)
        ┌─────────────▼──────────────┐
        │   lab-subca01 (VM 113)     │   Online · Domain-joined
        │   Enterprise Issuing CA    │   LAB-Issuing-CA
        │   Auto-enrollment, SCCM,   │
        │   LDAPS, web certs         │
        └────────────────────────────┘
```

**Two-tier vs the single-tier Enterprise Root CA (extension 3):** The single-tier `enable_ca` (VM 104) is simpler — one domain-joined Enterprise Root CA does everything — and is perfectly fine for a quick lab. The two-tier design is what you would actually build in production, where keeping the root key offline is a hard requirement. **Pick one or the other — do not enable both `enable_ca` and `enable_twotier_pki`**, since having two roots in the same domain is messy and serves no purpose.

**The key step — the offline cert exchange:** Because the root is offline, the issuing CA's `Install-AdcsCertificationAuthority` produces a certificate *request* (`.req`) instead of completing immediately. You manually carry that request to the offline root, sign it, carry the issued certificate back, install it, and start the CA service. The full `certreq`/`certutil` command sequence is documented in `infrastructure/vms/pki/README.md`.

**What it enables (same as the single-tier CA, but enterprise-grade):**
- SCCM PKI / HTTPS mode with a trusted issuing chain
- LDAPS on the domain controllers
- Auto-enrolled client authentication and computer certificates via GPO
- Web server certificates for IIS, WSUS, and internal HTTPS services

**Setup:** `ansible-playbook -i inventory/lab.yml playbooks/pki-root.yml` then `playbooks/pki-sub.yml` (with the manual cert-exchange step in between), or run `setup-rootca.ps1` and `setup-subca.ps1`. Full steps in `infrastructure/vms/pki/README.md`.
