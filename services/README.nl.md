# Services

🇬🇧 [English](README.md) | 🇳🇱 Nederlands

Self-hosted services die in het homelab draaien. Elke service draait in een eigen LXC-container of VM met een toegewezen VLAN.

## Inhoud

| Document | Service | Status |
|----------|---------|--------|
| [01-n8n.nl.md](01-n8n.nl.md) | n8n workflowautomatisering | Draait |
| [02-uptime-kuma.nl.md](02-uptime-kuma.nl.md) | Uptime Kuma monitoring | Draait |
| [03-ntfy.nl.md](03-ntfy.nl.md) | ntfy self-hosted pushmeldingen | Draait |

## Gepland

| Service | Doel | Verwachte planning |
|---------|------|-------------------|
| Wazuh | SIEM en SOAR (gekoppeld aan n8n) | Na eJPT-certificering |
| CrowdSec | Collaborative IPS | Na Wazuh |
