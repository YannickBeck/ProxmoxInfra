# lab-gitlab01 — GitLab CE

**VM ID:** 123 | **IP:** 10.10.10.73 | **Toggle:** `enable_gitlab = true`

GitLab Community Edition runs as the lab's single source of truth: git repositories, Issues, Merge Requests, CI/CD pipelines, and GitLab Pages. The Docusaurus documentation site (in `docusaurus-site/`) is built and published by a GitLab CI pipeline to GitLab Pages on every push to `main`.

---

## Architecture

```
GitLab CE (VM 123 / 10.10.10.73)
    ├── Git repositories
    ├── Issues + Merge Requests
    ├── CI/CD pipelines (GitLab Runner)
    └── GitLab Pages
            └── Docusaurus site  → http://pages.lab.local/<namespace>/docs/
```

---

## Resource Requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU cores | 4 | 4 |
| RAM | 8 GB | 8 GB |
| Disk | 100 GB | 100 GB |

GitLab is memory-intensive. Puma and Sidekiq are configured to reduced worker counts in the lab `docker-compose.yml` to fit within 8 GB.

---

## Deployment (Ansible)

```bash
ansible-playbook -i ansible/inventory/lab.yml ansible/playbooks/gitlab.yml
```

Or manually on the VM:

```bash
mkdir -p /opt/gitlab/{config,logs,data}
cd /opt/gitlab
cp /path/to/infrastructure/vms/gitlab/docker/docker-compose.yml .

# Set the external URL (edit the docker-compose.yml GITLAB_OMNIBUS_CONFIG block)
nano docker-compose.yml

docker compose pull
docker compose up -d

# GitLab takes 5–10 minutes to start
docker compose logs -f
```

---

## Initial Setup

### Get the root password

```bash
docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

The file is deleted after 24 hours — change the password immediately.

### Access GitLab

- **Web UI:** `http://10.10.10.73` (or `http://gitlab.lab.local` via Nginx Proxy Manager)
- **SSH clone:** `git clone git@10.10.10.73:2222/<namespace>/<project>.git`

After changing the root password:
1. Disable new user registration (Admin Area → Settings → General → Sign-up restrictions → Disable)
2. Create your personal account
3. Create the `docs` project for the Docusaurus site

---

## Publishing the Docusaurus Site

1. **Create a project** on GitLab (e.g. `<your-name>/docs`)

2. **Push the `docusaurus-site/` directory** from this repo as the new project root:
   ```bash
   cd docusaurus-site
   git init
   git remote add origin git@10.10.10.73:2222/<your-name>/docs.git
   git add .
   git commit -m "Initial Docusaurus setup"
   git push -u origin main
   ```

3. **Update `docusaurus.config.ts`** with your GitLab URL:
   ```ts
   const config = {
     url: 'http://pages.lab.local',
     baseUrl: '/<your-name>/docs/',
   };
   ```

4. **GitLab CI** (`.gitlab-ci.yml`) triggers automatically on push to `main`, builds the site, and deploys it to GitLab Pages.

5. **Access the site** at `http://pages.lab.local/<your-name>/docs/`

---

## GitLab Runner (CI/CD)

The default shared runner used for CI is the one built into the GitLab CE container. For production-grade pipelines, register a dedicated runner:

```bash
# On a separate VM or on lab-gitlab01 itself
docker run --rm -v /opt/gitlab-runner:/etc/gitlab-runner \
  gitlab/gitlab-runner register \
  --url http://10.10.10.73 \
  --registration-token <token-from-gitlab-ui> \
  --executor docker \
  --docker-image node:22
```

Get the registration token: GitLab UI → Admin Area → CI/CD → Runners → New instance runner.

---

## Access via Nginx Proxy Manager

1. In NPM, add two Proxy Hosts:
   - `gitlab.lab.local` → `10.10.10.73:80`
   - `*.pages.lab.local` → `10.10.10.73:8090`
2. Add DNS entries on lab-dc01:
   ```powershell
   Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "gitlab" -IPv4Address "10.10.10.71"
   Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "*.pages" -IPv4Address "10.10.10.71"
   ```
