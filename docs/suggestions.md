# Lab Extension Suggestions

This backlog complements the authoritative [logical pool design](logical-pools.md). New tools should normally join an existing shared Docker Compose/LXC host. A dedicated VM is justified only by appliance requirements, operating-system constraints, isolation needs or sustained resource demand.

## Recommended backlog

| Priority | Pool / host | Addition | Deployment guidance |
|---:|---|---|---|
| 1 | `pool-backup-dr` / lab-pbs01 (VMID 150) | Proxmox Backup Server | Preferred dedicated backup appliance; test restores on lab-restore01 |
| 2 | `pool-network-firewall` / lab-opnsense01 (VM 107) | OPNsense + optional Suricata | Recommended gateway; pfSense remains an exclusive alternative |
| 3 | `pool-nas-storage` / lab-nas01 (VM 120) | ZFS snapshots and replication | Keep storage duties on TrueNAS SCALE; OpenMediaVault is the light option |
| 4 | `pool-platform-services` / lab-services01 (VMID 125) | Guacamole, Vaultwarden, Homepage, IT-Tools | Add containers to the shared service host instead of creating one VM each |
| 5 | `pool-platform-services` / lab-git01 (VMID 126) | Forgejo + optional CI | Prefer Forgejo over GitLab CE when the lighter feature set is sufficient |
| 6 | `pool-observability-security` / lab-monitor01 (VMID 140) | Beszel + Uptime Kuma | Start here; add Prometheus/Grafana/Loki only for deeper telemetry |
| 7 | `pool-observability-security` / lab-siem01 (VMID 141) | Wazuh | Optional single-node SIEM after the lightweight monitoring baseline |
| 8 | `pool-devops-automation` / lab-automation01 (VMID 160) | Semaphore and API workflows | Centralize Ansible, Terraform/OpenTofu and PowerShell automation |
| 9 | `pool-sccm-lab` / lab-srv2019 (VMID 113) | Windows Server 2019 compatibility target | Dedicated VM is appropriate because this is an OS test workload |
| 10 | `pool-sccm-lab` / lab-mail01 (VMID 170) | Exchange lab | Heavy, low-priority special case; deploy only for a concrete AD/mail exercise |

## Consolidation rules

- Guacamole, dashboards, registries, LDAP browsers and small admin tools belong on `lab-services01`.
- Git hosting belongs on the future `lab-git01`; use Forgejo by default and add GitLab only if GitLab-specific exercises justify a separate deployment.
- Prometheus, Grafana and Loki extend `lab-monitor01`; they do not each receive a VM.
- Wazuh may use `lab-siem01` because its indexer and retention load warrant isolation.
- File shares belong on TrueNAS SCALE or OpenMediaVault, not on another generic file-server VM unless Windows file-server behavior is itself under test.
- A bastion can run on `lab-automation01`; split it out only when security boundaries require it.

All VMIDs above are consistent with the registry in `logical-pools.md`. Check that registry before introducing another Terraform resource.
