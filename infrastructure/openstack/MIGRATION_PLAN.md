# Proxmox to OpenStack Migration Plan

## Goal and boundaries

Recreate the lab on OpenStack without importing the Proxmox Terraform state.
The platforms run in parallel until service validation and cutover are complete.
Terraform provisions infrastructure; Ansible and PowerShell configure operating
systems and Microsoft roles.

## Phase 0 - capability and migration decisions

- Record region, availability zones, quotas, external network, supported volume
  types, DNS/NTP, metadata service, and config-drive behavior.
- Prove fixed addressing with Neutron DHCP disabled and validate port security
  for AD, DNS, DHCP broadcasts, RPC, SCCM, WinRM, and RDP.
- Decide between the native Neutron router, a later firewall appliance, or a
  permanently isolated network.
- Confirm image licensing and Windows 11 UEFI/TPM support.
- Define RPO, RTO, owners, maintenance window, rollback deadline, and acceptance
  tests for every stateful role.

Exit criterion: the target-cloud capability matrix has no unresolved blocker.

## Phase 1 - images and foundation

- Build/import generalized Windows Server 2022 and Windows 11 Glance images
  containing VirtIO drivers and Cloudbase-Init.
- Import official Ubuntu and Rocky cloud images if Linux clients are required.
- Configure a remote encrypted Terraform backend and project-scoped application
  credential outside the repository.
- Set deployment_stage=foundation and apply only network, subnet, security
  group, and optional router first.
- Boot a disposable test VM and validate metadata, config-drive, fixed IP, DNS,
  time synchronization, management access, egress, and reboot behavior.

Rollback: remove the disposable resources; the Proxmox lab is untouched.

## Phase 2 - core compute

- Set deployment_stage=identity to create lab-dc01, then configure and validate
  AD DS and DNS before proceeding.
- Set deployment_stage=servers to create lab-sccm01, attach SQL/optional WSUS
  volumes, domain-join it, and
  configure storage before restoring or installing SCCM.
- Set deployment_stage=all to create lab-client01 and validate domain join,
  Group Policy, SCCM client,
  WinRM/RDP, reboot, and patching.
- Feed Terraform outputs into a copied Ansible inventory; do not store passwords
  in Terraform state.

Exit criterion: core services pass functional and restart tests with no route
back to Proxmox required for normal operation.

## Phase 3 - stateful role migration

Use service-aware migration instead of blindly cloning running systems:

- Domain controllers: add a new OpenStack DC, replicate AD/DNS, validate
  replication and SYSVOL, transfer FSMO roles, then demote the old DC.
- CA: back up the CA database, configuration, certificate, and private key;
  restore using the documented AD CS procedure and verify issuance/revocation.
- SCCM/SQL: use supported SCCM site backup/recovery and SQL backup/restore, or a
  separately tested cold P2V; preserve hostname/IP assumptions deliberately.
- Entra Connect: deploy in staging mode, compare synchronization results, and
  switch the active server only after validation.
- Clients: recreate from golden images rather than migrate disposable clients.

A cold P2V is a fallback for compatible non-identity workloads only: shut down
the source, export/convert its disk, import it to Glance/Cinder, then test
drivers, boot mode, activation, networking, and application consistency in
isolation.

## Phase 4 - extensions and remote access

- Enable CA, DC02, Entra Connect, Client02, and Linux clients one role at a time.
- If firewall training is required, add a dedicated appliance module with a
  transit network. Validate whether the cloud permits disabled port security or
  suitable allowed-address pairs before attaching pfSense/OPNsense.
- Replace Raspberry Pi/WOL workflows with Nova lifecycle operations. Provide
  remote access through a VPN/bastion or ZeroTier gateway; do not assign public
  floating IPs to DC/SCCM by default.

## Phase 5 - cutover and decommission

- Freeze writes where required, take verified backups, complete final
  replication/restore, and run the acceptance checklist.
- Switch management routes and automation inventory during the approved window.
- Keep Proxmox systems powered off but recoverable until the rollback deadline.
- Capture OpenStack backups/snapshots and perform a restore test.
- Decommission old systems only after owner sign-off and evidence retention.

## Acceptance checklist

- Terraform plan contains no unexpected replacement or deletion.
- AD replication, DNS, Kerberos, SYSVOL, and time are healthy.
- SQL/SCCM site, content library, distribution, WSUS, and client policy work.
- CA issuance/CRL and Entra synchronization work when those roles are enabled.
- Ansible uses encrypted WinRM/SSH with host verification enabled.
- Management ports are reachable only from approved CIDRs or a bastion.
- Backup restore and rollback have been rehearsed and documented.
