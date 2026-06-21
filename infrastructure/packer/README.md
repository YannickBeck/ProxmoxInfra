# Packer Golden-Image Templates

Packer templates are an optional `pool-core-access` roadmap component. The intended IDs are VMID 9000 for Windows Server and VMID 9001 for Windows 11. These high IDs are reserved for templates and do not conflict with lab workload VMs.

No executable Packer template is committed yet. Until one is added, install Windows from ISO as described in the VM guides. A future implementation should:

- use the Proxmox builder and API credentials supplied outside version control;
- inject VirtIO storage/network drivers and unattended setup files;
- patch and generalize Windows with Sysprep;
- publish stopped Proxmox templates into `pool-core-access`;
- let Terraform clone workloads from those templates instead of attaching installer ISOs.

Do not run `packer build` in this directory until the corresponding HCL template and unattended assets have been implemented and reviewed.
