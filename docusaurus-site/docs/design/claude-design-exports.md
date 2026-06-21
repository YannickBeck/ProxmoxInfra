---
sidebar_position: 1
title: Claude Design Exports
---

# Claude Design Exports

Diese Seite archiviert Design-Entwürfe, Mockups und Prototypen, die mit **Claude Design** erstellt wurden.

## Workflow

```
Claude Design erstellt Mockup / Screen / Prototype
    → Export als PNG / SVG / HTML / Screenshot
    → Ablage in static/img/claude-design/
    → Beschreibung hier eintragen
    → Merge Request in GitLab
    → GitLab CI baut Docusaurus
    → GitLab Pages veröffentlicht die Seite
```

---

## Exports

_Noch keine Exports vorhanden. Füge hier deinen ersten Design-Export hinzu._

### Vorlage für einen neuen Export

```markdown
### [Feature-Name] — v1.0

**Erstellt:** YYYY-MM-DD  
**Status:** Entwurf / Review / Freigegeben  
**Datei:** [screenshot.png](../../static/img/claude-design/screenshot.png)

![Feature Mockup](../../static/img/claude-design/screenshot.png)

**Beschreibung:**  
Kurze Beschreibung was dieser Screen zeigt und welche Designentscheidungen getroffen wurden.

**Offene Punkte:**
- [ ] ...
```

---

## Namenskonvention für Dateien

```
static/img/claude-design/
├─ YYYY-MM-DD_<feature>_v1.png
├─ YYYY-MM-DD_<feature>_v1_dark.png
└─ YYYY-MM-DD_<feature>_v2.png
```
