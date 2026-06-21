---
sidebar_position: 3
title: User Stories
---

# User Stories

## Format

```
Als <Rolle>
möchte ich <Aktion / Feature>
damit <Nutzen / Ergebnis>.

Akzeptanzkriterien:
- [ ] ...
```

---

## NAS / Speicher

**US-001 — Zentraler Dateispeicher**

Als Home-Lab-Nutzer  
möchte ich alle Dateien auf einem zentralen NAS speichern  
damit sie von allen VMs im Lab erreichbar sind.

Akzeptanzkriterien:
- [ ] TrueNAS Scale ist über `http://10.10.10.70` erreichbar
- [ ] SMB-Share `data` ist von Windows-VMs einbindbar
- [ ] NFS-Share `media` ist von Linux-VMs einbindbar

---

## Paperless

**US-002 — Dokument scannen und ablegen**

Als Nutzer  
möchte ich ein gescanntes PDF in einen Ordner legen  
damit es automatisch OCR-verarbeitet und im Web-UI findbar ist.

Akzeptanzkriterien:
- [ ] PDF im Consume-Ordner löst automatisch OCR aus
- [ ] Dokument ist unter `http://paperless.lab.local` durchsuchbar
- [ ] Korrespondent und Dokumententyp werden erkannt

---

## GitLab / Docs

**US-003 — Dokumentation pushen und veröffentlichen**

Als Entwickler  
möchte ich Markdown-Dateien in GitLab pushen  
damit die Dokumentation automatisch auf GitLab Pages erscheint.

Akzeptanzkriterien:
- [ ] `git push` auf `main` triggert GitLab CI
- [ ] Docusaurus Build läuft fehlerfrei durch
- [ ] Seite ist unter `http://pages.lab.local/lab/docs/` erreichbar
