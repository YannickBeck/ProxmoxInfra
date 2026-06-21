# lab-nas01 — TrueNAS Scale

**VM ID:** 120 | **IP:** 10.10.10.70 | **Toggle:** `enable_nas = true`

[TrueNAS Scale](https://www.truenas.com/truenas-scale/) is an open-source NAS operating system based on Debian Linux, using OpenZFS for rock-solid data integrity. It provides SMB, NFS, and iSCSI sharing, a built-in app catalog (Docker containers), snapshot-based backups, and a polished web UI.

TrueNAS is configured almost entirely through its web UI — **not** through Ansible. This README covers the manual setup steps after OS installation.

---

## Prerequisites (before Terraform)

Upload the TrueNAS Scale ISO to Proxmox:
- Download: https://www.truenas.com/download-truenas-scale/
- Filename: `TrueNAS-SCALE-24.10.2.iso` (update `truenas_iso` in tfvars if different)

Terraform creates VM 120 with:
- **scsi0** (32 GB): TrueNAS OS disk
- **scsi1** (`nas_data_disk_size` GB): Raw data disk for the ZFS pool

---

## OS Installation

1. Start VM 120 from the Proxmox UI (`qm start 120`)
2. Boot from the TrueNAS ISO
3. Select **Install/Upgrade** → choose **scsi0 (32 GB)** as the OS target
4. Set the root password
5. After installation, TrueNAS reboots and shows the IP address in the console (or use DHCP → assign static IP via the web UI)

---

## Initial Web UI Configuration

Access the TrueNAS web UI at `http://10.10.10.70` (or the DHCP-assigned IP).

### 1. Set a Static IP

Network → Interfaces → Edit the active interface:
- Disable DHCP
- Add Static IP: `10.10.10.70/24`
- Default gateway: `10.10.10.1`
- DNS server: `10.10.10.10` (lab-dc01)

### 2. Create the ZFS Pool

Storage → Create Pool:
- Pool name: `tank` (or `data`)
- Layout: **Stripe** (single disk for lab, or Mirror/RAIDZ if you add more scsi* disks in Terraform)
- Disk: the **scsi1** raw disk (shown as `sdb` or `nvme0n1` etc.)

### 3. Create Datasets (Shares)

Inside the pool, create datasets for each purpose:

| Dataset | Path | Purpose |
|---|---|---|
| `tank/homes` | `/mnt/tank/homes` | User home directories |
| `tank/media` | `/mnt/tank/media` | Photos, videos, music |
| `tank/backup` | `/mnt/tank/backup` | Backup target for lab VMs |
| `tank/docs` | `/mnt/tank/docs` | Optional Docusaurus build archive |
| `tank/repos` | `/mnt/tank/repos` | Repository backup target for a future Git service |

### 4. Create SMB Shares

Sharing → Windows Shares (SMB) → Add:
- Path: `/mnt/tank/backup`
- Name: `backup`
- Enable: ✓

Repeat for other datasets. The Active Directory integration (System → Directory Services → Active Directory → `lab.local`) lets lab domain users authenticate to SMB shares without separate NAS accounts.

### 5. Create NFS Shares (optional)

Sharing → UNIX Shares (NFS) → Add:
- Path: `/mnt/tank/media`
- Maproot User: `root`
- Authorized Networks: `10.10.10.0/24`

---

## Backup Integration

### Optional Docusaurus archive

The documentation VM has no NAS runtime dependency. If desired, copy release archives or generated static builds to `/mnt/tank/docs` as a separate backup job.

### ZFS Snapshots

TrueNAS takes automatic periodic snapshots of each dataset. Configure under:
Data Protection → Periodic Snapshot Tasks → Add

Recommended schedule for lab:
- Hourly (keep 24), Daily (keep 30), Weekly (keep 8)

---

## Resource Notes

TrueNAS Scale requires **8 GB RAM minimum**. ZFS uses RAM for its ARC cache — the more RAM, the better the read performance. For the lab, 8 GB is sufficient for a few TB of data.

The OS disk (scsi0, 32 GB) is separate from the data pool (scsi1). Never add the OS disk to a ZFS pool.
