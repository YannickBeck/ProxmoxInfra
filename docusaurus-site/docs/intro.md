---
sidebar_position: 1
title: Einführung
---

# Lab Docs

Willkommen im Dokumentationsportal des **ProxmoxInfra Home Lab**.

Diese Seite dient als Knowledge Base, Projektdokumentation und Designarchiv. Sie wird automatisch aus dem GitLab-Repository gebaut und über GitLab Pages veröffentlicht.

---

## Lab-Infrastruktur

```mermaid
graph TD
    Internet((Internet)) --> RPi[Raspberry Pi\n172.22.0.1\nZeroTier + WoL]
    RPi -->|Wake-on-LAN| PVE[Proxmox VE\n192.168.1.100]

    PVE --> vmbr1[vmbr1\n10.10.10.0/24]

    vmbr1 --> DC01[lab-dc01\n10.10.10.10\nAD / DNS / DHCP]
    vmbr1 --> NAS[lab-nas01\n10.10.10.70\nTrueNAS Scale]
    vmbr1 --> NGX[lab-nginx01\n10.10.10.71\nNginx Proxy Manager]
    vmbr1 --> PPL[lab-paperless01\n10.10.10.72\nPaperless-ngx]
    vmbr1 --> GL[lab-gitlab01\n10.10.10.73\nGitLab CE]

    GL -->|GitLab Pages\nCI/CD| Docs[Lab Docs\ndocusaurus-site/]
```

---

## Schnellzugriff

| Service | URL | Beschreibung |
|---|---|---|
| GitLab | http://10.10.10.73 | Quellcode, Issues, CI/CD |
| Paperless | http://10.10.10.72:8000 | Dokumentenmanagement |
| TrueNAS | http://10.10.10.70 | NAS, ZFS, Shares |
| Nginx | http://10.10.10.71:81 | Reverse Proxy Admin |
| Proxmox | https://192.168.1.100:8006 | Hypervisor |

---

## Dokumentationsstruktur

- **Produkt** — Vision, Roadmap, User Stories
- **Design** — Claude Design Exports, Designsystem, Prototypen
- **Architektur** — Übersicht, Architecture Decision Records (ADRs)
- **API** — API-Dokumentation
- **Runbooks** — Betriebliche Anleitungen und Checklisten
