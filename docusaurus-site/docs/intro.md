---
sidebar_position: 1
title: Einführung
---

# Lab Docs

Willkommen im Dokumentationsportal des **ProxmoxInfra Home Lab**.

Diese Knowledge Base läuft als eigenständiger Docker-Stack auf `lab-docusaurus01` (VM 127) in `pool-nas-storage`. Der statische Build wird innerhalb dieser VM von einem kleinen Nginx-Container ausgeliefert; GitLab Pages oder andere Service-VMs werden dafür nicht benötigt.

## Schnellzugriff

| Service | URL | Beschreibung |
|---|---|---|
| Lab Docs | http://10.10.10.74 | Eigenständiges Dokumentationsportal |
| TrueNAS | http://10.10.10.70 | NAS, ZFS und Shares |
| Proxmox | https://192.168.1.100:8006 | Hypervisor |

## Dokumentationsstruktur

- **Produkt** — Vision, Roadmap und User Stories
- **Design** — Designsystem und Prototypen
- **Architektur** — Übersicht und Architecture Decision Records
- **API** — Aktive Schnittstellen
- **Runbooks** — Betriebliche Anleitungen und Checklisten
