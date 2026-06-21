# =======================================================================
# Proxmox resource pools
# =======================================================================
# Pools model ownership and lifecycle boundaries. They are intentionally
# created independently of optional workloads so the logical structure is
# stable even when a project currently contains no deployed VM or container.

resource "proxmox_virtual_environment_pool" "core_access" {
  pool_id = "pool-core-access"
  comment = "Proxmox access, Raspberry Pi gateway and golden-image templates"
}

resource "proxmox_virtual_environment_pool" "network_firewall" {
  pool_id = "pool-network-firewall"
  comment = "Firewall, NAT, routing, VLANs, IDS/IPS and optional DNS filtering"
}

resource "proxmox_virtual_environment_pool" "sccm_lab" {
  pool_id = "pool-sccm-lab"
  comment = "Microsoft SCCM / AD / Endpoint Management Lab"
}

resource "proxmox_virtual_environment_pool" "nas_storage" {
  pool_id = "pool-nas-storage"
  comment = "NAS, file services, backup target and shared storage"
}

resource "proxmox_virtual_environment_pool" "platform_services" {
  pool_id = "pool-platform-services"
  comment = "Internal web services, reverse proxy, Git and productivity services"
}

resource "proxmox_virtual_environment_pool" "ai_mcp_data" {
  pool_id = "pool-ai-mcp-data"
  comment = "AI and MCP stack: local LLM UI, RAG, model runtime, MCP servers and optional vector storage"
}

resource "proxmox_virtual_environment_pool" "observability_security" {
  pool_id = "pool-observability-security"
  comment = "Monitoring, uptime checks, logs, metrics and optional SIEM"
}

resource "proxmox_virtual_environment_pool" "backup_dr" {
  pool_id = "pool-backup-dr"
  comment = "Backup, restore validation and disaster recovery"
}

resource "proxmox_virtual_environment_pool" "devops_automation" {
  pool_id = "pool-devops-automation"
  comment = "Automation, IaC, CI runners and operational tooling"
}

resource "proxmox_virtual_environment_pool" "linux_clients" {
  pool_id = "pool-linux-clients"
  comment = "Linux clients and cross-platform management test systems"
}
