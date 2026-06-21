# Logical Proxmox Resource Pools

This document is the authoritative logical inventory for the Proxmox lab. Terraform creates the pools in `infrastructure/proxmox/terraform/pools.tf`; existing VMs declare their membership with `pool_id`.

Pools express ownership and lifecycle, not a requirement for one VM per application. Except for SCCM/Windows roles and appliance-like workloads such as OPNsense, TrueNAS SCALE and Proxmox Backup Server, new Linux services should run as Docker Compose or LXC stacks on a small number of shared hosts.

`pool-core-access` is also an inventory boundary: Proxmox resource pools cannot contain the physical Proxmox node or Raspberry Pi itself. It can contain Packer-generated templates when Terraform manages them.

## Complete target structure

```text
ProxmoxInfra Logical Pools
|
+-- pool-core-access
|   +-- proxmox-host             # Physical Proxmox VE host; not a VM
|   +-- raspberry-pi-gateway     # ZeroTier, WOL and optional admin API
|   `-- packer-templates         # Optional Server/Client golden images
|
+-- pool-network-firewall
|   +-- lab-opnsense01           # Recommended gateway: NAT, routing, VLANs, Unbound, optional Suricata
|   +-- lab-fw01                 # pfSense CE alternative; never run with OPNsense
|   `-- lab-dns-filter01         # Optional AdGuard Home helper
|
+-- pool-sccm-lab
|   +-- lab-dc01                 # AD DS, DNS, DHCP and Group Policy
|   +-- lab-sccm01               # Configuration Manager, SQL, MP, DP, SUP/WSUS, optional reporting
|   +-- lab-client01             # Windows 11 deployment/patch/compliance tests
|   +-- lab-client02             # Optional pilot and rollback client
|   +-- lab-ca01                 # Optional AD CS Enterprise Root CA
|   +-- lab-dc02                 # Optional AD/DNS redundancy and failure drills
|   `-- lab-aadc01               # Optional Entra Connect and co-management tests
|
+-- pool-nas-storage
|   +-- lab-nas01                # Recommended: TrueNAS SCALE, ZFS, SMB/NFS/iSCSI, snapshots
|   +-- lab-nas-lite01           # Optional lightweight OpenMediaVault alternative
|   `-- lab-docusaurus01         # Dedicated Docusaurus VM; optional NAS-backed build archives
|
+-- pool-platform-services
|   +-- lab-services01           # Shared Docker Compose/LXC service host
|   |   +-- Nginx Proxy Manager
|   |   +-- Paperless-ngx
|   |   +-- optional Vaultwarden
|   |   +-- optional Homepage or Homarr
|   |   +-- optional IT-Tools
|   |   `-- optional Dockge
|   +-- lab-git01                # Lightweight Git/CI host
|   |   +-- Forgejo              # Recommended GitLab alternative
|   |   +-- optional Forgejo Actions or Woodpecker CI
|   |   `-- source repositories
|   `-- lab-gitlab01             # Optional heavy GitLab CE/CI alternative
|
+-- pool-ai-mcp-data
|   +-- lab-ai-stack01           # Recommended: deliberately one all-in-one stack
|   |   +-- AnythingLLM
|   |   +-- Open WebUI
|   |   +-- Ollama
|   |   +-- MCP servers
|   |   +-- optional Qdrant
|   |   `-- optional LiteLLM
|   `-- lab-ai-workflow01        # Optional only when workflows become important
|       +-- Dify
|       +-- optional Postgres
|       +-- optional Redis
|       `-- optional dedicated vector DB
|
+-- pool-observability-security
|   +-- lab-monitor01            # Start small: Beszel + Uptime Kuma
|   |   +-- Beszel
|   |   +-- Uptime Kuma
|   |   +-- optional Grafana
|   |   +-- optional Prometheus
|   |   `-- optional Loki
|   `-- lab-siem01               # Optional Wazuh single-node stack and agents
|
+-- pool-backup-dr
|   +-- lab-pbs01                # Preferred: Proxmox Backup Server
|   `-- lab-restore01            # Disposable restore validation and DR drills
|
+-- pool-devops-automation
|   +-- lab-automation01         # Ansible, Semaphore, Terraform/OpenTofu, PowerShell 7, API scripts
|   `-- lab-runner01             # Optional Forgejo/Woodpecker/Docker build runner
|
`-- pool-linux-clients
    +-- lab-linux01              # Ubuntu SSH/Ansible/Docker/monitoring target
    +-- lab-linux02              # Rocky/Alma/RHEL-like baseline target
    `-- lab-kali01               # Optional and disposable security-test VM
```

The AI/MCP design intentionally avoids a database farm. AnythingLLM and Open WebUI use their bundled storage first; Qdrant is added only when an external vector database is demonstrably required. LiteLLM is similarly optional and is introduced only when a shared model gateway adds value. `lab-ai-workflow01` with Dify may be added later if workflow orchestration becomes a real requirement, not by default.

The recommended baseline is deliberately this small:

```text
pool-ai-mcp-data
`-- lab-ai-stack01
    +-- AnythingLLM
    +-- Open WebUI
    +-- Ollama
    +-- MCP servers
    +-- optional Qdrant
    `-- optional LiteLLM
```

## Priority

1. `pool-sccm-lab`
2. `pool-network-firewall`
3. `pool-nas-storage`
4. `pool-platform-services`
5. `pool-ai-mcp-data`
6. `pool-observability-security`
7. `pool-backup-dr`
8. `pool-devops-automation`
9. `pool-linux-clients`

`pool-core-access` is foundational inventory and therefore sits outside this workload rollout order.

## VMID registry

Existing IDs remain unchanged. Planned IDs are reservations for future Terraform resources; enabling a roadmap toggle does not create a VM until that resource is implemented.

| VMID | Host | Pool | State |
|---:|---|---|---|
| 100 | lab-fw01 | pool-network-firewall | Existing, optional pfSense alternative |
| 101 | lab-dc01 | pool-sccm-lab | Existing, core |
| 102 | lab-sccm01 | pool-sccm-lab | Existing, core |
| 103 | lab-client01 | pool-sccm-lab | Existing, core |
| 104 | lab-ca01 | pool-sccm-lab | Existing, optional |
| 105 | lab-dc02 | pool-sccm-lab | Existing, optional |
| 106 | lab-aadc01 | pool-sccm-lab | Existing, optional |
| 107 | lab-opnsense01 | pool-network-firewall | Existing, recommended gateway |
| 108 | lab-client02 | pool-sccm-lab | Existing, optional |
| 109 | lab-dns-filter01 | pool-network-firewall | Reserved |
| 110 | lab-linux01 | pool-linux-clients | Existing, optional |
| 111 | lab-linux02 | pool-linux-clients | Existing, optional |
| 112 | lab-kali01 | pool-linux-clients | Reserved |
| 113 | lab-srv2019 | pool-sccm-lab | Reserved, optional compatibility target |
| 120 | lab-nas01 | pool-nas-storage | Existing, recommended NAS |
| 124 | lab-nas-lite01 | pool-nas-storage | Reserved |
| 125 | lab-services01 | pool-platform-services | Reserved consolidation target |
| 126 | lab-git01 | pool-platform-services | Reserved Forgejo/CI host |
| 127 | lab-docusaurus01 | pool-nas-storage | Existing Terraform resource, optional dedicated docs VM |
| 130 | lab-ai-stack01 | pool-ai-mcp-data | Reserved |
| 131 | lab-ai-workflow01 | pool-ai-mcp-data | Reserved, optional |
| 140 | lab-monitor01 | pool-observability-security | Reserved |
| 141 | lab-siem01 | pool-observability-security | Reserved, optional |
| 150 | lab-pbs01 | pool-backup-dr | Reserved, preferred backup appliance |
| 151 | lab-restore01 | pool-backup-dr | Reserved, disposable |
| 160 | lab-automation01 | pool-devops-automation | Reserved |
| 161 | lab-runner01 | pool-devops-automation | Reserved, optional |
| 170 | lab-mail01 | pool-sccm-lab | Reserved, optional heavy Exchange lab |
| 9000/9001 | Packer templates | pool-core-access | Reserved template range |

This clean branch does not include the former dedicated Nginx, Paperless or GitLab resources. Future web applications are consolidated on `lab-services01`; Git uses `lab-git01` with Forgejo unless GitLab-specific features justify adding the heavier alternative later.

## Firewall invariant

OPNsense is the recommended firewall. pfSense remains supported as an alternative. Both use LAN gateway `10.10.10.1`, so `enable_opnsense` and `enable_pfsense` must never both be `true`. Terraform enforces this with resource lifecycle preconditions in addition to documenting it here.
