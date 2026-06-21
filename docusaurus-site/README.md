# Docusaurus Application Source

This directory contains the documentation site's source code. It remains in the repository because `lab-docusaurus01` builds its container image from these files; it is not a second infrastructure deployment.

The production target is the dedicated VM `lab-docusaurus01` (VMID 127, `10.10.10.74`) in `pool-nas-storage`. GitLab Pages is no longer the deployment target.

For VM provisioning and deployment instructions, see [`infrastructure/vms/docusaurus/README.md`](../infrastructure/vms/docusaurus/README.md).

Local development:

```bash
npm ci
npm start
```

Production build:

```bash
npm run build
```
