---
title: API-Dokumentation
---

# API-Dokumentation

Dokumentation der APIs und Schnittstellen im Lab.

---

## Interne APIs

| Service | Basis-URL | Authentifizierung |
|---|---|---|
| GitLab REST API | `http://10.10.10.73/api/v4/` | Personal Access Token |
| Paperless REST API | `http://10.10.10.72:8000/api/` | Token Auth |
| TrueNAS API | `http://10.10.10.70/api/v2.0/` | API Key |
| Nginx Proxy Manager API | `http://10.10.10.71:81/api/` | Bearer Token |
| WoL API (Raspberry Pi) | `http://172.22.0.1:8080/` | X-API-Key Header |

---

## WoL API

Weckt den Proxmox-Host über einen Magic Packet von der Raspberry Pi:

```bash
# Proxmox aufwecken
curl -X POST http://172.22.0.1:8080/wake \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json"
```

Implementierung: `raspberry-pi/wake-on-lan/wol-api.py`

---

## OpenAPI / Swagger

_Für eigene APIs wird hier die OpenAPI-Spec eingebunden._

```yaml
# Beispiel: openapi.yaml in static/api/ ablegen und hier referenzieren
```
