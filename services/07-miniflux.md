# Miniflux

🇬🇧 English | 🇳🇱 [Nederlands](07-miniflux.nl.md)

Miniflux is the homelab's self-hosted RSS reader. All security feeds, vendor advisories and release tracking for software running in the cluster converge here. It runs as a Docker stack in an LXC container behind Traefik as central reverse proxy, accessible internally via `miniflux.jacops.local`.

## Why self-hosted RSS

The homelab now runs ten services spread across multiple containers and a VM. Each service has an upstream that publishes releases, sometimes with security fixes that need patching within a week. On top of that, Debian security advisories, Docker updates and threat intel blogs are relevant for SOC work and eJPT preparation.

Without a central place to track those feeds, information scatters across GitHub release pages, vendor blogs and mailing lists. Miniflux brings it together in a single interface with categorization, so a five-minute daily scan is enough to stay current.

Miniflux was chosen over Changedetection.io (three recent CVEs including SSRF and auth bypass) and over heavier alternatives like FreshRSS or Tiny Tiny RSS. Miniflux is a single Go binary, light on resources, and has a clean API for future n8n integration.

## Architecture

```
Browser/App ─── HTTPS ──► Traefik (CT 165)  ──► Miniflux ──► PostgreSQL
                          :443                   :8080        :5432
                          step-ca ACME certs     Traefik      Docker net
                          Security headers       only         only

                LXC Container (CT 163)
                ┌──────────────────────────────────────┐
                │  Docker Compose                      │
                │  ├─ Miniflux (port 8080)             │
                │  └─ PostgreSQL 16 (port 5432)        │
                └──────────────────────────────────────┘
                VLAN 40 (Apps)
```

Two containers run in a single Docker Compose stack:

- **PostgreSQL 16** is the database. Runs on the internal Docker network, not reachable from outside. A healthcheck ensures Miniflux only starts once the database accepts connections
- **Miniflux** runs the feed engine, web UI and API. Binds on port 8080 and is only reachable via Traefik on CT 165. Access to port 8080 is restricted to the Traefik IP via the iptables `DOCKER-USER` chain

TLS termination and security headers are handled by Traefik on CT 165. Traefik automatically obtains certificates from the internal step-ca ACME server. See [decisions.md](../docs/decisions.md) for the reasoning behind the migration from per-LXC Caddy to central Traefik.

No public tunnel, no Cloudflare. The service is only reachable via the local network or WireGuard.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 163 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 1 core |
| RAM | 512 MB |
| Swap | 256 MB |
| Disk | 5 GB on NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container configuration |
| Boot | `onboot: 1` |
| Features | `nesting=1` (required for Docker) |
| Tags | `docker`, `homelab`, `miniflux` |

The roadmap specified 256 MB RAM and 3 GB disk. Both were increased: 512 MB because Miniflux, PostgreSQL and the Docker daemon together do not fit in 256 MB, and 5 GB because Docker images plus PostgreSQL data and Docker overlay make 3 GB tight. In practice the stack uses ~74 MB idle. See [decisions.md](../docs/decisions.md) for the reasoning.

## Docker images

All images are pinned on tag plus SHA256 digest. Upgrades are deliberate actions.

| Image | Version |
|-------|---------|
| `miniflux/miniflux` | 2.2.6 |
| `postgres` | 16-alpine |

## Feeds

19 feeds across three categories:

### Threat Intel (7 feeds)

| Feed | Source |
|------|--------|
| SANS Internet Storm Center | isc.sans.edu (full text) |
| Microsoft Security Blog | microsoft.com/security/blog |
| Unit 42 | unit42.paloaltonetworks.com |
| CrowdStrike Blog | crowdstrike.com/blog |
| Krebs on Security | krebsonsecurity.com |
| The DFIR Report | thedfirreport.com |
| BleepingComputer | bleepingcomputer.com |

Selected on signal-to-noise ratio. Rapid7 (30-35% marketing) and Cloudflare Blog (68% marketing) were removed after evaluation. CrowdStrike is re-evaluated quarterly for signal degradation.

### Advisories (2 feeds)

| Feed | Source |
|------|--------|
| Debian Security Advisories (DSA) | debian.org/security/dsa.rdf |
| PostgreSQL News | postgresql.org/news.rss |

Debian DSA is directly relevant to all LXC containers in the cluster (Debian 13). PostgreSQL covers the Miniflux database.

### Releases (10 feeds)

| Feed | Source |
|------|--------|
| Vaultwarden | GitHub releases |
| ntfy | GitHub releases |
| Uptime Kuma | GitHub releases |
| n8n | GitHub releases |
| Miniflux | GitHub releases |
| Caddy | GitHub releases |
| Forgejo | Codeberg releases |
| Docker/Moby | GitHub releases |
| Docker Compose | GitHub releases |
| WireGuard | GitHub releases |

Covers the full software stack running in the cluster. Proxmox VE and UniFi do not have public RSS feeds and are checked manually.

## ntfy integration

Miniflux forwards new entries to ntfy via the built-in integration:

| Setting | Value |
|---------|-------|
| Topic | `miniflux-alerts` |
| Endpoint | Internal IP of CT 151, port 2586 |
| Auth | Bearer token (dedicated publish token) |
| Priority | 3 (default) |

Notifications arrive on the iOS ntfy app and the Firefox web client. The n8n workflow that filters on severity (planned in the roadmap) can be added later on top of the direct integration.

## API

Miniflux exposes a REST API at `https://miniflux.jacops.local/v1/`. An API key has been created for future n8n integration. The key is stored in Vaultwarden as `homelab/miniflux-api-key`.

## TLS

TLS is handled by Traefik on CT 165 with automatic certificates from the internal step-ca ACME server. Certificates are EC P-256 with 72 hours validity and are auto-renewed via the ACME protocol. Security headers (HSTS, X-Frame-Options, nosniff) are applied globally by Traefik middleware.

Backend traffic between Traefik and Miniflux runs as HTTP on the same VLAN. Access to port 8080 on CT 163 is restricted to the Traefik IP via the iptables `DOCKER-USER` chain, so other hosts on the Apps VLAN cannot reach Miniflux directly.

## Access

| Path | Purpose |
|------|---------|
| `https://miniflux.jacops.local` | Web UI (daily use) |
| `https://miniflux.jacops.local/v1/` | REST API (n8n integration) |

Both are only reachable via the local network or WireGuard. There is no public URL.

## Backup

The container is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). This captures the full container filesystem including Docker volumes with the PostgreSQL database, all feed data and the Miniflux configuration.

## Related

- [roadmap](../docs/roadmap.md): Miniflux is the fifth foundation service in Phase 1
- [YubiKey](../hardware/01-yubikey.md): homelab CA for the TLS certificate
- [ntfy](03-ntfy.md): push notifications for new feed entries
- [decisions](../docs/decisions.md): RAM and disk deviation from the roadmap
