# Lab Extension Suggestions – ProxmoxInfra

Additional components that complement the base Windows lab. Each entry is justified by a concrete use case relevant to an SCCM/Intune/AD professional. Entries are ordered by recommended deployment priority.

---

## Summary Table

| # | Component | VMID | Role | Priority |
|---|---|---|---|---|
| 1 | Prometheus + Grafana | 120 | Infrastructure monitoring, Windows Exporter metrics, alerting | **High** |
| 2 | Apache Guacamole | 121 | Browser-based RDP/SSH — no VPN client needed for console access | **High** |
| 3 | Proxmox Backup Server (PBS) | 123 | Deduplicated VM snapshots before risky config changes | **High** |
| 4 | Wazuh SIEM | 122 | Windows Event Log collection, Sysmon, security alerting | Medium |
| 5 | Gitea | 124 | Local Git server for scripts, Ansible playbooks, GPO backups | Medium |
| 6 | File / Print Server | 126 | DFS namespaces, SMB shares, GPO software deployment testing | Medium |
| 7 | Bastion Host (Linux) | 128 | SSH jump host, replaces direct ZeroTier-to-VM exposure | Medium |
| 8 | Exchange Server 2019 | 125 | Mail infrastructure, AD integration, Outlook / OWA testing | Low |
| 9 | Portainer (Docker Host) | 127 | Container platform for lightweight support services | Low |
| 10 | Windows Server 2019 VM | 129 | Compatibility testing of older SCCM clients and OS builds | Low |

---

## 1 — Prometheus + Grafana (VM 120)

**Priority: High**

**What it does:** Collects metrics from all lab components — Proxmox host (via `pve` exporter), Windows VMs (via `windows_exporter`), Linux VMs (via `node_exporter`), and the Raspberry Pi — and renders them in a unified dashboard.

**Why it matters for your role:**
- SCCM infrastructure health (SQL Server performance counters, SCCM component status) is much easier to monitor in a dashboard than by reading WMI manually.
- Alert rules catch disk pressure (SCCM content library fills up fast), CPU spikes during software deployments, and SQL blocking.
- Grafana dashboards for Windows AD/SCCM are available as community templates — import them from grafana.com/dashboards.

**Minimum resources:** 2 vCPU, 4 GB RAM, 40 GB disk. Run on Ubuntu 22.04 or as a Docker stack.

**Key exporters to install:**
- `windows_exporter` on lab-dc01, lab-sccm01 (MSI install, exposed on port 9182)
- `mssql` exporter for SQL Server metrics on lab-sccm01
- Proxmox VE exporter (Python script, scrapes the PVE API at `192.168.1.100:8006`)
- `node_exporter` on Linux VMs and Raspberry Pi (already added to `client-linux.yml` playbook)

**Setup sketch:**
```bash
# On VM 120 (Ubuntu)
docker run -d -p 9090:9090 -v /etc/prometheus:/etc/prometheus prom/prometheus
docker run -d -p 3000:3000 grafana/grafana
```

---

## 2 — Apache Guacamole (VM 121)

**Priority: High**

**What it does:** A clientless remote desktop gateway. You access all lab VMs over RDP or SSH through a standard web browser — no VPN, no RDP client, no SSH client required. Works on tablets and restricted corporate laptops.

**Why it matters for your role:**
- Eliminates the ZeroTier + SSH tunnel + RDP client chain. Open a browser → authenticate once → click the VM you want.
- Particularly valuable when accessing the lab from a corporate machine where installing a VPN client is restricted.
- Can be the single access point protected by two-factor authentication (TOTP), replacing per-VM password management.
- Provides an audit trail of sessions (screen recording to S3/local storage).

**Minimum resources:** 2 vCPU, 2 GB RAM, 20 GB disk. Runs on Ubuntu 22.04 + Tomcat, or as a Docker Compose stack (recommended).

**Setup sketch (Docker Compose):**
```yaml
services:
  guacd:
    image: guacamole/guacd
  guacamole:
    image: guacamole/guacamole
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRES_HOSTNAME: db
    ports:
      - "8080:8080"
  db:
    image: postgres:16
```

**After setup:** Add each lab VM as a connection (RDP for Windows, SSH for Linux). Set the Guacamole server as the entry point in ZeroTier routing rules.

---

## 3 — Proxmox Backup Server (PBS) (VM 123)

**Priority: High**

**What it does:** A dedicated backup appliance that integrates directly with Proxmox VE. Creates deduplicated, incremental VM backups stored on a separate datastore.

**Why it matters for your role:**
- Snapshot before any risky operation (SCCM upgrade, AD schema extension, CU installation). If something breaks, roll back in minutes.
- Deduplication means a 200 GB VM set takes far less space when backed up daily — incremental changes are small.
- Test full DR scenarios: delete a VM, restore from PBS, verify SCCM still works. This is directly relevant to backup planning in enterprise environments.
- Built-in encryption means lab backups stay confidential even on shared storage.

**Minimum resources:** 2 vCPU, 2 GB RAM, the larger the better for the backup datastore (500 GB+ recommended if backing up all VMs). Can run as a VM or on a dedicated small machine.

**Integration:** Add PBS as a backup storage in Proxmox UI → Datacenter → Storage → Add → Proxmox Backup Server. Configure a backup job for all lab VMs at a schedule that suits your work.

---

## 4 — Wazuh SIEM (VM 122)

**Priority: Medium**

**What it does:** An open-source SIEM/XDR platform. Wazuh agents run on each Windows and Linux VM and forward security events (Windows Event Logs, Sysmon events, file integrity monitoring, vulnerability data) to the central Wazuh server.

**Why it matters for your role:**
- SCCM deployments generate a large number of Windows events (software installation, task sequences, boundary changes). Wazuh lets you correlate these across all clients in a single view.
- Practice investigating security events in a lab before encountering them in production. Simulate an attack (e.g., Mimikatz on lab-client01), see what Sysmon + Wazuh captures.
- Wazuh includes a MITRE ATT&CK mapping view, useful for understanding the detection coverage of your endpoint posture.
- Intune/Defender for Endpoint telemetry supplemented by Wazuh creates a full view of the lab's security state.

**Minimum resources:** 4 vCPU, 8 GB RAM, 100 GB disk (Wazuh + OpenSearch are memory-hungry). Run on Ubuntu 22.04.

**Quick install:**
```bash
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
bash wazuh-install.sh -a
```

**Sysmon on Windows VMs:** Deploy Sysmon with the SwiftOnSecurity configuration via a GPO or via the `ansible/playbooks/sccm.yml` playbook for maximum event visibility.

---

## 5 — Gitea (VM 124)

**Priority: Medium**

**What it does:** A lightweight, self-hosted Git server with a GitHub-like web UI. Stores PowerShell scripts, Ansible playbooks, Terraform modules, GPO backups, and SCCM application sources inside the lab network.

**Why it matters for your role:**
- Centralises all lab configuration in a versioned repository inside the lab — no dependency on internet access during setup.
- Enables Git-triggered automation: a webhook from Gitea can trigger an Ansible playbook run when a script is updated.
- Practice infrastructure-as-code workflows (branch → PR → merge → deploy) in the same environment you'd use in an enterprise.
- Back up Group Policy Objects by exporting them to a Gitea repository via a scheduled task — a common enterprise practice.

**Minimum resources:** 1 vCPU, 1 GB RAM, 20 GB disk. Runs as a single binary on any Linux VM, or as a Docker container alongside Guacamole or Portainer.

**Setup:**
```bash
# On Ubuntu (or alongside Portainer)
docker run -d \
  --name gitea \
  -p 3000:3000 -p 22:22 \
  -v /srv/gitea:/data \
  gitea/gitea:latest
```

---

## 6 — File / Print Server (VM 126)

**Priority: Medium**

**What it does:** A dedicated Windows Server VM running the File Services and Print and Document Services roles. Hosts DFS namespaces, SMB shares, and a shared printer (virtual or mapped to a PDF writer).

**Why it matters for your role:**
- SCCM software distribution can be tested end-to-end: publish an application with a source on the file server, deliver it to lab-client01, verify in the SCCM console.
- DFS Replication with lab-dc02 is a common enterprise pattern — practise configuring and monitoring it.
- GPO software deployment (APPX, MSI via Group Policy Software Installation) requires a central share — this VM provides one.
- Quota and access control testing: set NTFS permissions + File Server Resource Manager quotas, verify enforcement.

**Minimum resources:** 2 vCPU, 4 GB RAM, 60 GB OS + additional data disk as needed.

**Suggested VMID:** 126, hostname `lab-fs01`, IP `10.10.10.25`.

---

## 7 — Bastion Host / Jump Server (VM 128)

**Priority: Medium**

**What it does:** A hardened Linux VM (Ubuntu 22.04 minimal) that serves as the single SSH entry point into the lab. All external access routes through the bastion; no lab VM is directly reachable from ZeroTier except the bastion.

**Why it matters for your role:**
- Follows the principle of least privilege: only the bastion's SSH port is exposed, not every VM's RDP port.
- Centralises logging of all access (who logged in, from where, to which target VM, when).
- PAM integration with the lab AD domain means lab admins can authenticate with their AD credentials on the bastion.
- Use it as the Ansible control node for running playbooks directly inside the lab network without WinRM traversing ZeroTier.

**Minimum resources:** 1 vCPU, 1 GB RAM, 20 GB disk. Hardened: fail2ban, UFW allowing only port 22 from ZeroTier subnet (172.22.0.0/16).

**Suggested VMID:** 128, hostname `lab-bastion01`, IP `10.10.10.5`.

**Alternative:** If Guacamole (VM 121) is deployed, it can serve a similar purpose for browser-based access. Use the bastion specifically for SSH-based Ansible management.

---

## 8 — Exchange Server 2019 (VM 125)

**Priority: Low**

**What it does:** Microsoft Exchange Server 2019 for the `lab.local` domain. Provides a fully functional mail infrastructure including Outlook connectivity, OWA (Outlook Web Access), and Exchange ActiveSync.

**Why it matters for your role:**
- Hybrid Exchange with Microsoft 365 (Exchange Hybrid) is a common enterprise migration scenario — set it up to practice coexistence.
- Exchange integrates tightly with AD and requires the AD schema to be extended — a useful exercise for understanding AD schema versioning.
- SCCM can deploy and manage Exchange updates via software deployment or task sequences.
- Required for testing Outlook profile deployment via GPO or Intune.

**Minimum resources:** 4 vCPU, 16 GB RAM, 100 GB OS disk + mailbox database disk. Exchange is resource-intensive — ensure the Proxmox host has enough RAM before adding this.

**Prerequisites:** Exchange 2019 requires Windows Server 2019 (not 2022), .NET Framework 4.8, and the AD schema extension (`Setup /PrepareSchema`). Run the AD schema prep from lab-dc01.

**Suggested VMID:** 125, hostname `lab-mail01`, IP `10.10.10.35`.

---

## 9 — Portainer / Docker Host (VM 127)

**Priority: Low**

**What it does:** A Linux VM running Docker with Portainer as a management UI. Quickly deploys lightweight support services as containers rather than full VMs.

**Why it matters for your role:**
- Run LDAP browser (`phpLDAPadmin`) as a container to inspect AD objects without installing tools on Windows.
- Run a local container registry to store Docker images for testing.
- Host a simple web server for SCCM application/script testing (simulate an internal intranet source).
- Practice Docker/container management — increasingly relevant as enterprises containerise supporting tooling.

**Minimum resources:** 2 vCPU, 4 GB RAM, 60 GB disk. Ubuntu 22.04 + Docker CE.

**Suggested VMID:** 127, hostname `lab-docker01`, IP `10.10.10.70`.

**Services to run as containers:**
- `phpLDAPadmin` — LDAP browser for AD
- `nginx` — web server for testing IIS vs Apache behaviour
- `Minio` — S3-compatible object storage for testing SCCM cloud distribution point scenarios
- `Semaphore` (Ansible UI) — web interface for running Ansible playbooks without a CLI

---

## 10 — Windows Server 2019 VM (VM 129)

**Priority: Low**

**What it does:** A second Windows Server VM running Windows Server 2019 (instead of 2022), domain-joined to `lab.local`.

**Why it matters for your role:**
- Many enterprise environments still run Windows Server 2019. Testing SCCM client push, task sequences, and software deployments against 2019 catches compatibility issues before production.
- SCCM supported OS compatibility matrix testing: verify that task sequences developed for Server 2022 also work on 2019.
- Windows Server 2019 is the supported host OS for Exchange Server 2019 (see above).
- AD group policy settings that behave differently between 2019 and 2022 (e.g., certain security baselines) are easier to identify when you have both OSes in the domain.

**Minimum resources:** 2 vCPU, 4 GB RAM, 60 GB disk. Uses the same Windows Server 2019 ISO (available from Microsoft Eval Center).

**Suggested VMID:** 129, hostname `lab-srv2019`, IP `10.10.10.80`.

---

## Deployment Order for Suggested Extensions

If you deploy multiple suggestions at once, follow this order:

```
Base lab (DC01 + SCCM + Client01)
    │
    ├─ 1. PBS (VM 123)      — backup before anything else changes
    ├─ 2. Guacamole (VM 121) — set up access, then deploy everything else via browser
    ├─ 3. Prometheus/Grafana (VM 120) — visibility into what's happening
    ├─ 4. Gitea (VM 124)    — centralise config versioning
    ├─ 5. Bastion (VM 128)  — harden access
    ├─ 6. Wazuh (VM 122)    — security visibility
    ├─ 7. File Server (VM 126) — test SCCM content distribution
    ├─ 8. Portainer (VM 127) — lightweight service platform
    ├─ 9. Exchange (VM 125)  — after AD schema prep
    └─ 10. WS 2019 (VM 129) — compatibility testing last
```

---

## Resource Budget

Rough additional resource requirements if all suggestions are deployed (beyond the base 5-VM lab):

| Component | vCPU | RAM | Disk |
|---|---|---|---|
| Prometheus + Grafana | 2 | 4 GB | 40 GB |
| Guacamole | 2 | 2 GB | 20 GB |
| PBS | 2 | 2 GB | 500 GB |
| Wazuh | 4 | 8 GB | 100 GB |
| Gitea | 1 | 1 GB | 20 GB |
| File Server | 2 | 4 GB | 120 GB |
| Bastion | 1 | 1 GB | 20 GB |
| Exchange | 4 | 16 GB | 200 GB |
| Portainer | 2 | 4 GB | 60 GB |
| WS 2019 | 2 | 4 GB | 60 GB |
| **Total (all)** | **22** | **46 GB** | **1.14 TB** |

The base lab (3 core + 4 extension VMs) already requires ~22 vCPU and ~26 GB RAM at full deployment. A Proxmox host with **32 GB RAM** comfortably runs the base lab plus the three **High** priority suggestions (PBS, Guacamole, Monitoring). **64 GB RAM** is recommended for a fully-loaded lab including Wazuh and Exchange.
