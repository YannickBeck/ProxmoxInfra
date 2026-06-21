# OpenStack Lab Infrastructure

This directory contains the OpenStack target for the Windows lab currently
provisioned on Proxmox. It is a separate Terraform root module on purpose:
Proxmox and OpenStack must never share state.

The first implementation provisions the OpenStack foundation and workload VMs.
Guest configuration remains in the existing Ansible playbooks and PowerShell
scripts.

## Resource mapping

| Proxmox concept | OpenStack target |
|---|---|
| vmbr1 / 10.10.10.0/24 | Neutron network and subnet |
| vmbr0 and host NAT | Optional Neutron router with SNAT |
| VM definition and VMID | Nova instance and UUID |
| ISO CD-ROM installation | Prepared Glance image |
| local-lvm disks | Cinder boot and data volumes |
| Proxmox CPU/RAM settings | Existing OpenStack flavors |
| Proxmox API token | Application credential via clouds.yaml or OS_* variables |
| Wake-on-LAN | Nova start/stop API; WOL is not required |

At deployment_stage=all, the core machines are always created:

- lab-dc01 (10.10.10.10, 2 vCPU, 4 GB RAM, 60 GB root volume)
- lab-sccm01 (10.10.10.20, 4 vCPU, 8 GB RAM, 100 GB root and 100 GB SQL volume)
- lab-client01 (10.10.10.50, 2 vCPU, 4 GB RAM, 60 GB root volume)

CA, secondary DC, Entra Connect, a second Windows client, and Linux clients are
optional and use the same toggles as the Proxmox implementation.

## Deliberate differences

The OpenStack target boots from cloud-ready images. Windows images must contain
VirtIO drivers and Cloudbase-Init and must be generalized with Sysprep. Linux
images need cloud-init. Do not place passwords, domain credentials, or OpenStack
credentials in Terraform variables or user data: they would be stored in state.

Neutron DHCP is disabled by default so it cannot compete with the Windows DHCP
role on lab-dc01. Neutron allocation pools exclude the Windows DHCP range
10.10.10.100-200. A fixed Neutron port reserves an address but does not, on every
cloud, configure that address inside the guest. Verify static network
configuration through config-drive/Cloudbase-Init in the target cloud before
deploying Active Directory.

The MVP supports two gateway modes:

- isolated: no router and no external connectivity (default)
- native: a Neutron router owns 10.10.10.1 and provides external SNAT

pfSense/OPNsense appliances are intentionally deferred. They require a
cloud-specific transit network, two ports, and anti-spoofing/port-security
decisions; see [MIGRATION_PLAN.md](MIGRATION_PLAN.md).

## Prerequisites

Before planning, confirm:

1. Project quotas cover instances, vCPUs, RAM, ports, and Cinder storage.
2. Referenced flavors, Glance images, Cinder volume type, availability zones,
   and the optional external network exist.
   The selected Cinder volume type must be verified as encrypted at rest.
3. Windows 11 support (UEFI, TPM 2.0, Secure Boot) is available if the image
   requires it; these are operator capabilities, not portable tenant settings.
4. 10.10.10.0/24 does not overlap a routed tenant, VPN, or management network.
5. A project-scoped least-privilege application credential is available outside
   this repository.

## Usage

Authenticate either with a local clouds.yaml entry (set cloud_name or OS_CLOUD)
or standard OS_* environment variables while leaving cloud_name null. TLS
verification must remain enabled; use OS_CACERT for a private CA.

    cd infrastructure/openstack/terraform
    cp terraform.tfvars.example terraform.tfvars
    export OS_CLOUD=lab-openstack

    terraform init
    terraform fmt -check
    terraform validate
    terraform plan -out=openstack.tfplan
    terraform apply openstack.tfplan

A remote, encrypted, versioned backend with locking is mandatory before the
first non-disposable plan/apply. Backend configuration is intentionally not hard
coded because OpenStack does not define a standard Terraform state backend.
Select the organization-approved backend, commit only its non-secret backend
block, and pass credentials/configuration outside the repository. Treat any
temporary local state as a secret and delete it only after it has been migrated
to the remote backend.

Roll out with deployment_stage values foundation, identity, servers, and all.
This creates the network first, then DC01, then SCCM, and finally clients and
extensions. Perform the config-drive/fixed-IP PoC with a disposable image in
the foundation before promoting to identity. External egress is a separate
opt-in; gateway_mode native alone does not open internet egress.

Management CIDRs only create Security Group rules. They do not create a Floating
IP, VPN, route, or bastion. The management network must already be privately
routed to the lab, preferably through an approved VPN/bastion.

The existing Ansible defaults use unencrypted WinRM/5985 and must not be reused
unchanged. Configure WinRM HTTPS/5986 (or Kerberos over a trusted private path)
before using the OpenStack inventory; this Security Group deliberately does not
open 5985.

After apply, use the ansible_hosts output to update
ansible/inventory/lab.yml. Provision lab-dc01 first and do not run dependent
SCCM/domain-join playbooks until AD and DNS health checks pass.

Root and data volumes have lifecycle prevent_destroy enabled. Removing or
replacing one requires an explicit break-glass code change after a verified
backup. Extension toggles are therefore one-way until that break-glass step.
This guard does not replace Cinder backups or protect against out-of-band
deletion. Do not run terraform destroy as a routine rollback.
