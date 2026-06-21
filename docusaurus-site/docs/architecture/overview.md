---
sidebar_position: 1
title: Architektur-Übersicht
---

# Architektur-Übersicht

## Infrastrukturdiagramm

```mermaid
graph LR
    subgraph Home-LAN [Home LAN 192.168.1.0/24]
        Router[Home Router\n192.168.1.1]
        RPi[Raspberry Pi\n192.168.1.200\nZeroTier + WoL]
        PVE[Proxmox VE\n192.168.1.100]
    end

    subgraph Lab-Netz [Lab vmbr1 10.10.10.0/24]
        DC01[lab-dc01\n10.10.10.10\nAD / DNS / DHCP]
        NAS[lab-nas01\n10.10.10.70\nTrueNAS Scale]
        NGX[lab-nginx01\n10.10.10.71\nNginx Proxy Manager]
        PPL[lab-paperless01\n10.10.10.72\nPaperless-ngx]
        GL[lab-gitlab01\n10.10.10.73\nGitLab CE]
    end

    ZeroTier((ZeroTier\n172.22.0.0/16)) --> RPi
    RPi --> PVE
    PVE --> Lab-Netz

    NGX --> NAS
    NGX --> PPL
    NGX --> GL
    GL -->|Pages| Docs[Docusaurus Site]
    PPL --> NAS
```

---

## Komponentenbeschreibung

| Komponente | Technologie | Zweck |
|---|---|---|
| Hypervisor | Proxmox VE 8.x | Führt alle VMs aus |
| Fernzugriff | ZeroTier + WoL (Raspberry Pi) | Remote-Zugang + Aufwecken des Hosts |
| NAS | TrueNAS Scale (ZFS) | Zentraler Dateispeicher, Backup-Ziel |
| Reverse Proxy | Nginx Proxy Manager (Docker) | HTTP-Routing, SSL-Terminierung |
| Dokumentenmgmt | Paperless-ngx (Docker) | OCR, Ablage, Suche |
| Source Control | GitLab CE (Docker) | Repos, CI/CD, Pages |
| Doku-Portal | Docusaurus 3 | Diese Seite |
| Domain | Windows Server 2022 AD DS | AD, DNS, DHCP für lab.local |

---

## Netzwerk

- **vmbr0** (`192.168.1.0/24`): Home LAN, Proxmox-Management
- **vmbr1** (`10.10.10.0/24`): Isoliertes Lab-Netz, alle VMs
- **ZeroTier** (`172.22.0.0/16`): Verschlüsseltes Overlay für Fernzugriff

Alle NAS/Services-VMs sitzen im selben Subnetz (vmbr1) wie die Windows-VMs. Nginx Proxy Manager ist der einzige Eintrittspunkt für HTTP-Traffic von außerhalb.

---

## Datenpfade

```
Scan → NAS consume-Share
    → Paperless (OCR + Index)
    → NAS media-Share (Archiv)

Git push
    → GitLab CE
    → GitLab CI (Docusaurus build)
    → GitLab Pages (Veröffentlichung)

VM-Backups
    → NAS backup-Share (ZFS, Snapshots)
```
