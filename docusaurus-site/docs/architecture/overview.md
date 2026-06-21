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
        FW[OPNsense oder pfSense\n10.10.10.1]
        DC01[lab-dc01\n10.10.10.10\nAD / DNS / DHCP]
        SCCM[lab-sccm01\n10.10.10.20\nSCCM / SQL]
        NAS[lab-nas01\n10.10.10.70\nTrueNAS Scale]
        Docs[lab-docusaurus01\n10.10.10.74\nDocusaurus]
    end

    ZeroTier((ZeroTier\n172.22.0.0/16)) --> RPi
    RPi --> PVE
    PVE --> Lab-Netz
    Docs -. optionale Archive .-> NAS
```

## Neue Infrastruktur

| Komponente | Technologie | Zweck |
|---|---|---|
| NAS | TrueNAS Scale mit ZFS | Zentraler Speicher, Shares und Backup-Ziel |
| Doku-Portal | Docusaurus 3 auf VM 127 | Eigenständige Dokumentation ohne Git-Plattform als Laufzeitabhängigkeit |
| Webserver der Doku-VM | Schlanker Nginx-Container | Auslieferung des statischen Docusaurus-Builds |

Die früheren dedizierten Nginx-Proxy-, Paperless- und GitLab-VMs gehören nicht zu diesem Branch.

## Datenpfade

```text
Repository-Update
    -> lab-docusaurus01
    -> Docker Build (Docusaurus)
    -> Nginx-Container (Veröffentlichung)

VM-Backups
    -> NAS backup-Share
    -> ZFS-Snapshots
```
