# lab-nginx01 — Nginx Proxy Manager

**VM ID:** 121 | **IP:** 10.10.10.71 | **Toggle:** `enable_nginx = true`

Nginx Proxy Manager (NPM) is an open-source reverse proxy with a clean web UI. It routes incoming HTTP/HTTPS requests to internal lab services by hostname, and handles SSL certificate management (self-signed or Let's Encrypt).

---

## Role in the Lab

| Service | Internal URL | Exposed via NPM as |
|---|---|---|
| GitLab CE | http://10.10.10.73 | http://gitlab.lab.local |
| Paperless-ngx | http://10.10.10.72:8000 | http://paperless.lab.local |
| TrueNAS | http://10.10.10.70 | http://nas.lab.local |
| NPM itself | http://10.10.10.71:81 | (admin only, not proxied) |

---

## Prerequisites

- Ubuntu 22.04 LTS installed on VM 121
- SSH access as `ubuntu` from the Ansible control machine
- Internal DNS (lab-dc01) or `/etc/hosts` entries pointing hostnames to 10.10.10.71

---

## Deployment (Ansible)

```bash
# From the repo root
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/nginx.yml
```

Or manually on the VM:

```bash
mkdir -p /opt/nginx-proxy-manager
cp infrastructure/vms/nginx/docker/docker-compose.yml /opt/nginx-proxy-manager/
cd /opt/nginx-proxy-manager
docker compose up -d
```

---

## First Login

1. Open `http://10.10.10.71:81` in a browser
2. Log in with `admin@example.com` / `changeme`
3. Change the email and password immediately

---

## Adding a Proxy Host

1. Dashboard → **Proxy Hosts** → **Add Proxy Host**
2. **Domain Names:** `gitlab.lab.local`
3. **Forward Hostname:** `10.10.10.73`
4. **Forward Port:** `80`
5. Save — HTTP traffic to `gitlab.lab.local` now reaches GitLab

To enable HTTPS with a self-signed certificate:
- **SSL** tab → **SSL Certificate** → **Request a new SSL Certificate**
- Enable **Force SSL** and **HTTP/2 Support**

---

## Adding DNS Entries

On lab-dc01, add A records in the `lab.local` DNS zone:

```powershell
# On lab-dc01 (PowerShell)
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "gitlab"    -IPv4Address "10.10.10.71"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "paperless" -IPv4Address "10.10.10.71"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "nas"       -IPv4Address "10.10.10.71"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "pages"     -IPv4Address "10.10.10.71"
```

---

## GitLab Pages via Wildcard Proxy

GitLab Pages uses a wildcard subdomain (`*.pages.lab.local`). To route it through NPM:

1. Add a Proxy Host with domain `*.pages.lab.local`
2. Forward to `10.10.10.73:8090` (GitLab Pages port)
3. On lab-dc01, add a wildcard DNS entry:
   ```powershell
   Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "*.pages" -IPv4Address "10.10.10.71"
   ```
