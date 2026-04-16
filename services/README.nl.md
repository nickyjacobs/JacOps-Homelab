# Services

🇬🇧 [English](README.md) | 🇳🇱 Nederlands

Self-hosted services die in het homelab draaien. Elke service draait in een eigen LXC-container of VM met een toegewezen VLAN.

## Inhoud

| Document | Service | Status |
|----------|---------|--------|
| [01-n8n.nl.md](01-n8n.nl.md) | n8n workflowautomatisering | Draait |
| [02-uptime-kuma.nl.md](02-uptime-kuma.nl.md) | Uptime Kuma monitoring | Draait |
| [03-ntfy.nl.md](03-ntfy.nl.md) | ntfy self-hosted pushmeldingen | Draait |
| [04-vaultwarden.nl.md](04-vaultwarden.nl.md) | Vaultwarden password vault | Draait |
| [05-forgejo.nl.md](05-forgejo.nl.md) | Forgejo Git forge | Draait |
| [06-forgejo-runner.nl.md](06-forgejo-runner.nl.md) | Forgejo Runner CI/CD | Draait |
| [07-miniflux.nl.md](07-miniflux.nl.md) | Miniflux RSS reader | Draait |
| [08-step-ca.nl.md](08-step-ca.nl.md) | step-ca interne ACME server | Draait |
| [09-traefik.nl.md](09-traefik.nl.md) | Traefik centraal reverse proxy | Draait |
| [10-beszel.nl.md](10-beszel.nl.md) | Beszel host-metrics monitoring | Draait |

## Gepland

| Service | Doel | Verwachte planning |
|---------|------|-------------------|
| Wazuh | SIEM en SOAR (gekoppeld aan n8n) | Na eJPT-certificering |
| CrowdSec | Collaborative IPS | Na Wazuh |
