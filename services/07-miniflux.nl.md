# Miniflux

🇬🇧 [English](07-miniflux.md) | 🇳🇱 Nederlands

Miniflux is de self-hosted RSS reader van het homelab. Alle security-feeds, vendor advisories en release-tracking van de software die in het cluster draait komen hier samen. Het draait als Docker stack in een LXC-container achter Caddy als reverse proxy, intern bereikbaar via `miniflux.jacops.local`.

## Waarom self-hosted RSS

Het homelab draait inmiddels tien services verspreid over meerdere containers en een VM. Elke service heeft een upstream die releases publiceert, soms met security fixes die binnen een week gepatcht moeten worden. Daarnaast zijn er Debian security advisories, Docker updates en threat intel blogs die relevant zijn voor SOC-werk en eJPT-voorbereiding.

Zonder een centraal punt om die feeds bij te houden verspreid de informatie zich over GitHub release pages, vendor blogs en mailing lists. Miniflux brengt dat samen in een enkele interface met categorisering, zodat een dagelijkse scan van vijf minuten volstaat om bij te blijven.

Miniflux is gekozen boven Changedetection.io (drie recente CVEs, waaronder SSRF en auth bypass) en boven zwaardere alternatieven zoals FreshRSS of Tiny Tiny RSS. Miniflux is een enkele Go binary, licht op resources, en heeft een schone API voor toekomstige n8n-integratie.

## Architectuur

```
Browser/App ─── HTTPS ──► Caddy (TLS termination) ──► Miniflux ──► PostgreSQL
                          :443                        :8080         :5432
                          CA-cert                     Alleen via    Alleen via
                                                      Docker net    Docker net

                LXC Container (CT 163)
                ┌──────────────────────────────────────┐
                │  Docker Compose                      │
                │  ├─ Caddy (poort 443)                │
                │  ├─ Miniflux (poort 8080)            │
                │  └─ PostgreSQL 16 (poort 5432)       │
                └──────────────────────────────────────┘
                VLAN 40 (Apps)
```

Drie containers draaien in een enkele Docker Compose stack:

- **PostgreSQL 16** is de database. Draait op het interne Docker netwerk, niet bereikbaar van buitenaf. Een healthcheck zorgt dat Miniflux pas start als de database verbindingen accepteert
- **Miniflux** draait de feed-engine, web UI en API. Bindt op poort 8080 binnen het Docker-netwerk, alleen bereikbaar via Caddy
- **Caddy** handelt TLS-terminatie af met een certificaat ondertekend door de [homelab CA](../hardware/01-yubikey.nl.md). Proxied verkeer door naar Miniflux en voegt de `X-Real-IP` header toe

Geen publieke tunnel, geen Cloudflare. De service is alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 163 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 1 core |
| RAM | 512 MB |
| Swap | 256 MB |
| Disk | 5 GB op NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |
| Features | `nesting=1` (vereist voor Docker) |
| Tags | `docker`, `homelab`, `miniflux` |

De roadmap specificeerde 256 MB RAM en 3 GB disk. Beiden zijn opgehoogd: 512 MB omdat Miniflux, PostgreSQL, Caddy en de Docker daemon samen niet in 256 MB passen, en 5 GB omdat Docker images (~400-500 MB) plus PostgreSQL data en Docker overlay 3 GB krap maken. In de praktijk gebruikt de stack ~74 MB idle. Zie [decisions.nl.md](../docs/decisions.nl.md) voor de onderbouwing.

## Docker images

Alle images zijn gepind op tag plus SHA256 digest. Upgrades zijn bewuste acties.

| Image | Versie |
|-------|--------|
| `miniflux/miniflux` | 2.2.6 |
| `postgres` | 16-alpine |
| `caddy` | 2.11.2-alpine |

## Feeds

19 feeds verdeeld over drie categorieen:

### Threat Intel (7 feeds)

| Feed | Bron |
|------|------|
| SANS Internet Storm Center | isc.sans.edu (full text) |
| Microsoft Security Blog | microsoft.com/security/blog |
| Unit 42 | unit42.paloaltonetworks.com |
| CrowdStrike Blog | crowdstrike.com/blog |
| Krebs on Security | krebsonsecurity.com |
| The DFIR Report | thedfirreport.com |
| BleepingComputer | bleepingcomputer.com |

Geselecteerd op signaal-ruisverhouding. Rapid7 (30-35% marketing) en Cloudflare Blog (68% marketing) zijn na evaluatie verwijderd. CrowdStrike wordt per kwartaal geevalueerd op signaalverlies.

### Advisories (2 feeds)

| Feed | Bron |
|------|------|
| Debian Security Advisories (DSA) | debian.org/security/dsa.rdf |
| PostgreSQL News | postgresql.org/news.rss |

Debian DSA is direct relevant voor alle LXC-containers in het cluster (Debian 13). PostgreSQL dekt de Miniflux database.

### Releases (10 feeds)

| Feed | Bron |
|------|------|
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

Dekt de volledige software stack die in het cluster draait. Proxmox VE en UniFi hebben geen publieke RSS feeds en worden handmatig gecheckt.

## ntfy integratie

Miniflux stuurt nieuwe entries door naar ntfy via de ingebouwde integratie:

| Instelling | Waarde |
|------------|--------|
| Topic | `miniflux-alerts` |
| Endpoint | Intern IP van CT 151, poort 2586 |
| Auth | Bearer token (dedicated publish-token) |
| Prioriteit | 3 (default) |

De notificaties komen binnen op de iOS ntfy app en in de Firefox webclient. De n8n-workflow die op severity filtert (gepland in de roadmap) kan later als aanvulling bovenop de directe integratie komen.

## API

Miniflux heeft een REST API op `https://miniflux.jacops.local/v1/`. Een API key is aangemaakt voor toekomstige n8n-integratie. De key staat in Vaultwarden als `homelab/miniflux-api-key`.

## TLS

Caddy gebruikt een certificaat ondertekend door de `JacOps Homelab CA`. Het cert is geldig voor twee jaar (tot april 2028) en heeft `miniflux.jacops.local` als SAN. De CA staat als trusted root in de macOS system keychain, waardoor alle browsers het cert vertrouwen zonder exceptions.

De Caddyfile:

```
miniflux.jacops.local {
    tls /certs/miniflux.jacops.local.pem /certs/miniflux.jacops.local.key

    reverse_proxy miniflux:8080 {
        header_up X-Real-IP {remote_host}
    }
}
```

## Toegang

| Pad | Doel |
|-----|------|
| `https://miniflux.jacops.local` | Web UI (dagelijks gebruik) |
| `https://miniflux.jacops.local/v1/` | REST API (n8n-integratie) |

Beide zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem inclusief de Docker volumes met de PostgreSQL database, alle feed-data en de Miniflux configuratie.

## Gerelateerd

- [roadmap](../docs/roadmap.nl.md): Miniflux is de vijfde foundation service in Fase 1
- [YubiKey](../hardware/01-yubikey.nl.md): homelab CA voor het TLS certificaat
- [ntfy](03-ntfy.nl.md): push-notificaties voor nieuwe feed entries
- [decisions](../docs/decisions.nl.md): RAM en disk afwijking van de roadmap
