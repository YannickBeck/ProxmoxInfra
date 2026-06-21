# Contributing

## Workflow

```
Idee / Feature
→ Claude Design erstellt Mockup, Screen oder Prototype
→ Export als PNG/SVG/HTML/Screenshot
→ Ablage in static/img/claude-design/
→ Beschreibung in docs/design/
→ Merge Request in GitLab
→ GitLab CI baut Docusaurus
→ GitLab Pages veröffentlicht die Seite
```

## Neue Seite hinzufügen

1. Markdown-Datei in `docs/<kategorie>/` erstellen
2. Frontmatter mit `title` und `sidebar_position` setzen
3. Bei neuen Kategorien: Eintrag in `sidebars.ts` ergänzen
4. Lokal prüfen: `npm run start`
5. Merge Request erstellen

## Lokale Entwicklung

```bash
npm install
npm run start   # Dev-Server auf http://localhost:3000
npm run build   # Production-Build nach build/
```

## Bilder / Design-Exports

- Ablage: `static/img/claude-design/YYYY-MM-DD_<feature>_v1.png`
- Referenz in Markdown: `![Alt](../../static/img/claude-design/dateiname.png)`
- Maximale Dateigröße: 2 MB pro Bild

## Markdown-Qualität

```bash
npm run lint   # markdownlint über alle docs/*.md
```

Regeln: `.markdownlint.json` im Projekt-Root (falls vorhanden).
