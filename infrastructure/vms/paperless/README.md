# lab-paperless01 — Paperless-ngx

**VM ID:** 122 | **IP:** 10.10.10.72 | **Toggle:** `enable_paperless = true`

[Paperless-ngx](https://docs.paperless-ngx.com/) is an open-source document management system (DMS) with OCR, full-text search, automatic tagging, and a modern web UI. Drop scanned documents into a consume folder and Paperless processes, indexes, and makes them searchable.

---

## Stack Components

| Container | Image | Purpose |
|---|---|---|
| `paperless-web` | `ghcr.io/paperless-ngx/paperless-ngx` | Web server + OCR workers |
| `paperless-db` | `postgres:16` | Document metadata storage |
| `paperless-redis` | `redis:7` | Async task queue (Celery broker) |

---

## Prerequisites

- Ubuntu 22.04 LTS installed on VM 122
- SSH access as `ubuntu` from the Ansible control machine
- (Optional) NAS SMB share mounted for the consume directory

---

## Deployment (Ansible)

```bash
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/paperless.yml
```

Or manually on the VM:

```bash
mkdir -p /opt/paperless-ngx
cd /opt/paperless-ngx
cp /path/to/infrastructure/vms/paperless/docker/docker-compose.yml .
cp /path/to/infrastructure/vms/paperless/docker/.env.example .env
nano .env   # fill in secret key, admin credentials, etc.

docker compose pull
docker compose up -d
```

---

## First Login

Web UI: `http://10.10.10.72:8000` (or `http://paperless.lab.local` via Nginx Proxy Manager)

If `PAPERLESS_ADMIN_USER` is set in `.env`, the account is created automatically. Otherwise:

```bash
docker compose exec webserver python3 manage.py createsuperuser
```

---

## Consume Directory (Auto-Import)

Paperless watches `/usr/src/paperless/consume` inside the container (mapped to `./consume` on the host). Documents placed there are automatically OCR-processed and imported.

**With TrueNAS NAS integration:**

```bash
# On lab-paperless01, mount the NAS SMB share
apt install cifs-utils -y
mkdir -p /mnt/nas-consume
mount -t cifs //10.10.10.70/consume /mnt/nas-consume \
  -o username=paperless,password=yourpassword,uid=1000,gid=1000

# Make mount persistent (add to /etc/fstab)
echo "//10.10.10.70/consume /mnt/nas-consume cifs username=paperless,password=yourpassword,uid=1000,gid=1000,_netdev 0 0" >> /etc/fstab
```

Then change the consume volume in `docker-compose.yml`:
```yaml
- /mnt/nas-consume:/usr/src/paperless/consume
```

---

## Export / Backup

```bash
# Export all documents to the export directory
docker compose exec webserver document_exporter ../export

# The export/ directory contains all originals + JSON metadata
# Back it up to TrueNAS via rsync or SMB
rsync -av /opt/paperless-ngx/export/ //10.10.10.70/backup/paperless/
```

---

## Access via Nginx Proxy Manager

1. In NPM, add a Proxy Host:
   - Domain: `paperless.lab.local`
   - Forward to: `10.10.10.72:8000`
2. Add DNS A record on lab-dc01:
   ```powershell
   Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "paperless" -IPv4Address "10.10.10.71"
   ```
