---
sidebar_position: 3
title: User Stories
---

# User Stories

## Zentraler Speicher

Als Home-Lab-Nutzer möchte ich Dateien und Backups auf einem zentralen NAS speichern, damit sie von den Lab-Systemen kontrolliert erreichbar und per ZFS geschützt sind.

- [ ] TrueNAS ist unter `http://10.10.10.70` erreichbar
- [ ] SMB- und optionale NFS-Shares sind eingerichtet
- [ ] Periodische ZFS-Snapshots sind aktiv

## Eigenständige Dokumentation

Als Betreiber möchte ich versionierte Markdown-Dateien auf eine dedizierte Dokumentations-VM deployen, damit die Dokumentation unabhängig von einer Git-Plattform verfügbar ist.

- [ ] Docusaurus-Build läuft fehlerfrei
- [ ] Container läuft auf `lab-docusaurus01`
- [ ] Seite ist unter `http://10.10.10.74/` erreichbar
- [ ] Das NAS ist keine Runtime-Abhängigkeit
