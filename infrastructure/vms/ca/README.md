# lab-ca01 – Enterprise Root CA (AD CS / PKI) Setup Guide

This document covers the manual and automated steps to configure `lab-ca01` (VM 104) as an **Active Directory Certificate Services (AD CS) Enterprise Root Certification Authority** for the `lab.local` domain. It provides the internal Public Key Infrastructure (PKI) that the rest of the lab relies on for trusted certificates.

| Item | Value |
|---|---|
| VM ID | 104 |
| Hostname | `LAB-CA01` |
| IP address | `10.10.10.30/24` |
| Gateway | `10.10.10.1` (lab-fw01) |
| DNS | `10.10.10.10` (lab-dc01) |
| Domain | `lab.local` (NetBIOS `LAB`) |
| Role | Enterprise Root CA, Web Enrollment |
| CA common name | `LAB-Root-CA` |

---

## Purpose – Why a Real CA Matters

A standalone test lab can limp along with self-signed certificates, but a **proper internal PKI** is what separates a toy environment from one that mirrors a real enterprise. With an Enterprise Root CA in place, the lab can **issue and automatically trust** certificates for:

- **SCCM HTTPS / PKI mode** – Configuration Manager supports HTTP, Enhanced HTTP (E-HTTP, self-signed), and full **PKI (HTTPS)** mode. Cloud-attach scenarios (Cloud Management Gateway / CMG), co-management, and internet-based client management strongly **prefer PKI client-authentication and web-server certificates**. Building the lab on PKI from the start is what makes a "professional Intune/SCCM" demo realistic.
- **IIS web server certificates** – the SCCM management point, distribution point, software update point, and any other lab web service can present a trusted TLS certificate.
- **LDAPS (secure LDAP on TCP 636)** on the domain controllers – auto-enrolled Domain Controller / Kerberos Authentication certificates enable encrypted directory binds (required by many integrations, e.g. Azure AD Connect password write-back, some app onboarding).
- **Client authentication certificates** – domain computers and users auto-enroll certs used for 802.1X, VPN, SCCM client auth, etc.
- **Code signing** – sign PowerShell scripts and internal tooling with a cert that chains to a trusted root.

Because the CA is **AD-integrated (Enterprise)**, its root certificate is published into Active Directory automatically and every domain-joined machine trusts it without any per-machine import.

---

## Enterprise Root CA vs Standalone

| | Enterprise Root CA (used here) | Standalone Root CA |
|---|---|---|
| AD integration | Yes – stores config + publishes root cert in AD | No – not AD-aware |
| Certificate templates | **Yes** (duplicate built-ins, control via ACLs) | No (manual request attributes only) |
| Auto-enrollment | **Yes** (via Group Policy) | No |
| Issuance | Can issue automatically based on template permissions | Requests are pending until an admin approves |
| Best for | Domain-joined environments (our lab) | Offline roots, non-domain / DMZ scenarios |

We deploy an **Enterprise Root CA** because the whole value proposition (templates + auto-enrollment + automatic trust) depends on AD integration. In production you would typically build a **two-tier** PKI (offline standalone root + online enterprise issuing CA); for a lab a single-tier Enterprise Root CA is the pragmatic choice.

---

## Prerequisites

Before starting, ensure:

- [ ] **lab-dc01 is running** and the `lab.local` domain is available
- [ ] DNS resolution works from this VM (`Resolve-DnsName lab.local` returns the DC)
- [ ] VM 104 has been created by Terraform (set `enable_ca = true` in `terraform.tfvars`) and Windows Server 2022 is installed
- [ ] VirtIO storage + network drivers are installed
- [ ] You can log in as a **Domain Admin / Enterprise Admin** of `lab.local` (required to configure an Enterprise CA — it writes to the AD configuration partition)

---

## Step 1 – Install Windows Server 2022

Same process as the other servers:

1. Start VM 104 from the Proxmox UI or: `qm start 104`
2. Open the console and boot from the Windows Server 2022 ISO (`local:iso/WinSrv2022_EN-US_eval.iso`)
3. Select **Windows Server 2022 Standard (Desktop Experience)**
4. Click **Load driver** and load the VirtIO SCSI controller from the `virtio-win` ISO so the disk appears
5. Complete installation; set the local Administrator password (placeholder `LabAdm1n!2024` — **change this**)
6. After first boot, install the VirtIO **NetKVM** Ethernet driver from Device Manager

---

## Step 2 – Run setup-ca.ps1 (Two Phases)

Copy `setup-ca.ps1` to the VM and run it from an **elevated** PowerShell session. The script is two-phase, just like `setup-dc.ps1`:

### Phase 1 – Rename, IP, Domain Join

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-ca.ps1 -DomainJoinCredential (Get-Credential)
```

Phase 1 (runs when the computer is not yet named `LAB-CA01` or not yet domain-joined):

1. Renames the computer to `LAB-CA01`
2. Sets the static IP `10.10.10.30/24`, gateway `10.10.10.1`, DNS `10.10.10.10`
3. Joins the `lab.local` domain (placing the computer in `OU=Servers`)
4. **Reboots**

### Phase 2 – Install and Configure AD CS

After the reboot, log back in **as a Domain Admin** and run the same script again (no credential needed):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-ca.ps1
```

Phase 2 (runs once the computer is named `LAB-CA01` **and** domain-joined):

1. Installs the `ADCS-Cert-Authority`, `ADCS-Web-Enrollment`, and `RSAT-ADCS-Mgmt` features
2. Configures an **Enterprise Root CA** named `LAB-Root-CA` (4096-bit RSA key, SHA256, 10-year validity)
3. Configures the **Web Enrollment** role service (`https://lab-ca01.lab.local/certsrv`)
4. (Enterprise CA) the root certificate is published to AD automatically
5. Prints the manual next steps for certificate templates and the auto-enrollment GPO

Every step is **idempotent** — re-running the script skips work already done.

> **Ansible alternative:** `ansible-playbook -i inventory/lab.yml playbooks/ca.yml` performs the rename / IP / join / feature install / CA configuration. Template + GPO configuration remain manual (see below).

---

## Step 3 – Certificate Templates

Templates are best created with the **Certificate Templates console** (`certtmpl.msc`) on `LAB-CA01`. The pattern is always: **duplicate a built-in template**, adjust settings, set enrollment **permissions**, then **publish** it for issuance on the CA (`certsrv.msc → Certificate Templates → New → Certificate Template to Issue`).

Create the following templates:

| New template name | Duplicate from | Purpose / key settings | Enrollment permissions |
|---|---|---|---|
| **Workstation Authentication** (built-in, just publish) | n/a (already exists) | Client authentication for domain computers | Grant `Domain Computers`: **Enroll + Autoenroll** |
| **Web Server** (built-in, just publish) | n/a (already exists) | TLS server certs (subject supplied in request) | Grant specific server accounts: **Enroll** (Web Server has no autoenroll because subject is manual) |
| **ConfigMgr Web Server Certificate** | Web Server | SCCM site-system HTTPS (MP/DP/SUP). On the **Subject Name** tab: *Supply in the request*. Validity 2 years. | Grant the SCCM computer (`LAB\LAB-SCCM01$`) and any site-system servers: **Read + Enroll** |
| **ConfigMgr Client Distribution Point Certificate** | Workstation Authentication | Client-auth cert used by clients to access HTTPS distribution points | Grant `Domain Computers`: **Read + Enroll + Autoenroll** |

Notes:

- To set permissions: in `certtmpl.msc`, right-click the template → **Properties → Security** tab → add the principal → tick **Enroll** and (where supported) **Autoenroll**.
- After creating/duplicating, **publish** each template: open `certsrv.msc` → expand `LAB-Root-CA` → right-click **Certificate Templates → New → Certificate Template to Issue** → select the templates. Only published templates can be issued.
- The "Workstation Authentication" and "Web Server" templates already exist in AD; you only need to **issue** (publish) them. The two ConfigMgr templates must be **duplicated** first so you can scope their permissions without affecting the originals.

The bundled `setup-ca.ps1` includes an **optional PSPKI block**: if the `PSPKI` PowerShell module is installed (`Install-Module PSPKI`), it will duplicate the Web Server template and grant `Domain Computers` autoenroll automatically. If PSPKI is absent, the script prints the manual `certtmpl.msc` instructions instead.

---

## Step 4 – Auto-Enrollment GPO

Auto-enrollment is what makes templates issue **without any user action**. Configure it once in a GPO linked at the **domain root**:

1. On the DC (or a machine with RSAT GPMC), open **Group Policy Management** (`gpmc.msc`)
2. Right-click `lab.local` → **Create a GPO in this domain, and Link it here** → name it e.g. `PKI - Certificate Autoenrollment`
3. Edit the GPO and enable auto-enrollment in **both** Computer and User scopes:
   - **Computer Configuration → Policies → Windows Settings → Security Settings → Public Key Policies → Certificate Services Client - Auto-Enrollment** → set to **Enabled**
   - Tick **Renew expired certificates, update pending certificates, and remove revoked certificates**
   - Tick **Update certificates that use certificate templates**
   - Repeat under **User Configuration → Policies → Windows Settings → Security Settings → Public Key Policies**
4. On target machines run `gpupdate /force`, then check `certlm.msc` (computer) / `certmgr.msc` (user) → **Personal → Certificates** to confirm certs were enrolled

---

## Step 5 – LDAPS on the Domain Controllers

Once the Enterprise CA exists **and** the DCs can auto-enroll, each DC automatically requests a **Domain Controller** / **Kerberos Authentication** certificate (these templates auto-enroll to the `Domain Controllers` group by default). The presence of a valid DC certificate enables **LDAPS on TCP 636** — no extra configuration is needed on the DC.

Verify LDAPS:

1. Force enrollment / GPO on the DC: `gpupdate /force`, then confirm in `certlm.msc → Personal → Certificates` that a cert with **Intended Purpose = Server/Client Authentication** issued by `LAB-Root-CA` is present
2. Test the secure bind with **ldp.exe** (built-in):
   - Run `ldp.exe` → **Connection → Connect** → Server: `lab-dc01.lab.local`, Port: **636**, tick **SSL** → OK
   - A successful connect prints the `supportedCapabilities` / `defaultNamingContext` RootDSE attributes (no certificate error)
3. Or from PowerShell:
   ```powershell
   $c = New-Object System.DirectoryServices.Protocols.LdapConnection("lab-dc01.lab.local:636")
   $c.SessionOptions.SecureSocketLayer = $true
   $c.Bind()   # no exception == LDAPS works
   ```

---

## Step 6 – Publish / Trust the Root CA Certificate

For an **Enterprise CA** the root certificate is published **automatically** into Active Directory at configuration time, into:

- `CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration,DC=lab,DC=local` (Trusted Root)
- `CN=NTAuthCertificates,…` (NTAuth – allows the CA to issue authentication certs)

Domain-joined machines pull these into their **Trusted Root Certification Authorities** store via Group Policy autoenrollment — no manual import required.

To (re)publish manually, e.g. after re-keying the CA, export the root cert and run:

```powershell
# Export the CA cert, then publish it into AD
certutil -ca.cert C:\LAB-Root-CA.cer
certutil -dspublish -f C:\LAB-Root-CA.cer RootCA
certutil -dspublish -f C:\LAB-Root-CA.cer NTAuthCA
gpupdate /force   # on clients to pull the updated root
```

For **non-domain** clients (e.g. a workgroup test box), distribute `LAB-Root-CA.cer` and import it into **Local Computer → Trusted Root Certification Authorities**, or push it via a GPO (`Computer Configuration → Policies → Windows Settings → Security Settings → Public Key Policies → Trusted Root Certification Authorities → Import`).

---

## Verification

Run these on `LAB-CA01` (and the DCs / clients where noted):

| Command / tool | What it checks |
|---|---|
| `pkiview.msc` | Enterprise PKI health — CA, AIA, and CDP locations should all be **OK (green)** |
| `certutil -ping` | The CA service (`certsvc`) responds |
| `certutil -pingadmin` | The CA **admin** interface responds (needed for issuance management) |
| `certutil -CAInfo` | CA name, type (Enterprise Root), and validity |
| `certsrv.msc` → **Issued Certificates** | Confirms certificates are actually being issued to clients/DCs |
| `certlm.msc` → **Personal** (on a client/DC) | Confirms auto-enrolled certs landed in the machine store |
| `ldp.exe` → connect `<dc>:636` SSL | Confirms LDAPS works on the DCs |
| `gpresult /r` (on a client) | Confirms the autoenrollment GPO is applied |

---

## Which Lab Service Consumes Which Certificate

| Lab service / host | Certificate (template) | Used for |
|---|---|---|
| lab-sccm01 (MP/DP/SUP, IIS) | ConfigMgr Web Server Certificate (from Web Server) | SCCM site-system **HTTPS / PKI mode**, CMG / cloud-attach |
| lab-client01 + domain computers | Workstation Authentication / ConfigMgr Client Distribution Point Certificate | SCCM **client authentication**, HTTPS DP access, 802.1X/VPN |
| lab-dc01 / lab-dc02 | Domain Controller / Kerberos Authentication (auto-enrolled) | **LDAPS** (636), secure replication, smart-card logon |
| Any lab IIS / web app | Web Server | Trusted **TLS** for internal web services |
| lab-aadc01 (Azure AD Connect) | Domain Controller cert on the DCs (LDAPS) | Secure LDAP binds for password write-back / sync |
| Admin scripts / tooling | Code Signing (duplicate of built-in) | Signing internal PowerShell / executables |

---

## Troubleshooting

- **`Install-AdcsCertificationAuthority` says a CA already exists** – the role is already configured; the script guards against this and skips. To start over you must uninstall the CA role first.
- **pkiview.msc shows CDP/AIA errors** – expected in an isolated lab if the default HTTP CDP URL is unreachable; for a single-tier lab CA this can be ignored, or remove the unreachable CDP/AIA URLs in `certsrv.msc → CA Properties → Extensions`.
- **Clients don't get certs** – confirm the template is **published** on the CA, the principal has **Enroll + Autoenroll**, the autoenrollment **GPO** is applied (`gpresult /r`), then `gpupdate /force`.
- **LDAPS won't connect on 636** – ensure the DC actually enrolled a Domain Controller/Kerberos Authentication cert (`certlm.msc`), then restart `NTDS` or reboot the DC so it binds the new cert.
