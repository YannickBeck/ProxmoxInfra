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

## Existing Windows extensions

| VM | VMID | Toggle | Role | Guide |
|---|---:|---|---|---|
| Enterprise Root CA | 104 | `enable_ca` | AD CS PKI | [ca/README.md](../infrastructure/vms/ca/README.md) |
| Secondary DC | 105 | `enable_dc02` | AD/DNS redundancy | [dc02/README.md](../infrastructure/vms/dc02/README.md) |
| Azure AD Connect | 106 | `enable_aadconnect` | Entra sync | [azuread-connect/README.md](../infrastructure/azuread-connect/README.md) |
| WSUS disk on SCCM | – | `wsus_content_disk_size` | Software Update Point storage | [sccm/README.md](../infrastructure/vms/sccm/README.md#software-update-point) |
