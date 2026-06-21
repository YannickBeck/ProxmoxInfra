# lab-docusaurus01 – Dedicated Documentation VM

`lab-docusaurus01` is the standalone Docusaurus runtime in the NAS/storage environment. Terraform creates VMID 127 in `pool-nas-storage`; the site is served at `http://10.10.10.74`.

## Design

- Ubuntu Server VM with Docker and the Compose plugin
- Docusaurus built from the repository's `docusaurus-site/` source
- Static output served by an Nginx container
- No runtime dependency on GitLab or GitLab Pages
- Optional TrueNAS SCALE share for repository mirrors and build backups

The source remains under `docusaurus-site/` so changes are versioned together with the infrastructure documentation. The VM is the deployment target, not the source of truth.

## Provision

Set the toggle and apply Terraform:

```hcl
enable_nas        = true
enable_docusaurus = true
```

```bash
cd infrastructure/proxmox/terraform
terraform apply
```

Install Ubuntu Server on VM 127, assign static address `10.10.10.74/24`, DNS `10.10.10.10`, and gateway `10.10.10.1`. Install Docker Engine plus the Docker Compose plugin, then clone or copy this repository to the VM.

## Deploy

From the repository root on `lab-docusaurus01`:

```bash
docker compose \
  -f infrastructure/vms/docusaurus/docker/docker-compose.yml \
  up -d --build
```

Verify:

```bash
curl http://127.0.0.1/healthz
curl http://10.10.10.74/
```

For optional NAS-backed build retention, mount a TrueNAS dataset such as `10.10.10.70:/mnt/tank/docusaurus` on the VM and copy release archives or repository mirrors there. The running static site should remain available even when the NAS share is temporarily offline.
