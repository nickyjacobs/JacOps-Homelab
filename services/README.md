# Services

🇬🇧 English | 🇳🇱 [Nederlands](README.nl.md)

Self-hosted services running in the homelab. Each service runs in its own LXC container or VM with a dedicated VLAN assignment.

## Contents

| Document | Service | Status |
|----------|---------|--------|
| [01-n8n.md](01-n8n.md) | n8n workflow automation | Running |
| [02-uptime-kuma.md](02-uptime-kuma.md) | Uptime Kuma monitoring | Running |
| [03-ntfy.md](03-ntfy.md) | ntfy self-hosted push notifications | Running |
| [04-vaultwarden.md](04-vaultwarden.md) | Vaultwarden password vault | Running |
| [05-forgejo.md](05-forgejo.md) | Forgejo Git forge | Running |
| [06-forgejo-runner.md](06-forgejo-runner.md) | Forgejo Runner CI/CD | Running |
| [07-miniflux.md](07-miniflux.md) | Miniflux RSS reader | Running |

## Planned

| Service | Purpose | Target timeline |
|---------|---------|-----------------|
| Wazuh | SIEM and SOAR (paired with n8n) | After eJPT certification |
| CrowdSec | Collaborative IPS | After Wazuh |
