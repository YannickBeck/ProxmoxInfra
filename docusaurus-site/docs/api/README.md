---
title: API-Dokumentation
---

# API-Dokumentation

## Aktive Schnittstellen

| Service | Basis-URL | Authentifizierung |
|---|---|---|
| TrueNAS API | `http://10.10.10.70/api/v2.0/` | API Key |
| Proxmox API | `https://192.168.1.100:8006/api2/json` | API Token |
| WoL API (Raspberry Pi) | `http://172.22.0.1:8080/` | `X-API-Key` Header |

```bash
curl -X POST http://172.22.0.1:8080/wake \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json"
```

Implementierung: `raspberry-pi/wake-on-lan/wol-api.py`.
