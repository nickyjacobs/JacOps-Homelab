# Forgejo

🇬🇧 [English](05-forgejo.md) | 🇳🇱 Nederlands

Forgejo is de self-hosted Git-forge van het homelab. Alle code, configuratie en automatisering die bij het homelab hoort, krijgt hier een thuis. Het draait als native binary in een LXC-container achter Traefik als centraal reverse proxy, intern bereikbaar via `forgejo.jacops.local`.

## Waarom Forgejo

Het homelab genereert bij elke nieuwe service configuratiebestanden, compose files, scripts en documentatie. Zonder een eigen Git-server leven die bestanden verspreid over hosts of alleen in een publieke GitHub-repo. Een eigen forge geeft versiebeheer voor alles wat niet publiek hoort te zijn. CI/CD via Forgejo Actions draait op de [Forgejo Runner](06-forgejo-runner.nl.md) (CT 161).

Forgejo is een community-fork van Gitea, gelicenseerd onder GPL. De v11 LTS-lijn krijgt support tot juli 2026. De keuze voor Forgejo boven Gitea is de governance: Forgejo wordt beheerd door een stichting in plaats van een commercieel bedrijf, wat beter past bij een homelab dat niet afhankelijk wil zijn van licensing-wijzigingen.

## Architectuur

```
Browser ─── HTTPS ──► Traefik (CT 165)  ──► Forgejo (CT 160)
                      :443                   :3000
                      step-ca ACME certs     Alleen via Traefik
                      Security headers       (iptables firewall)

Git SSH ─── SSH ──────────────────────────► Forgejo (CT 160)
                                            :2222
                                            Direct (niet via Traefik)

                LXC Container (CT 160)
                ┌──────────────────────────────────────┐
                │  Forgejo v11.0.12 (systemd)          │
                │  ├─ HTTP :3000 (web + API)           │
                │  └─ SSH :2222 (git operaties)        │
                └──────────────────────────────────────┘
                VLAN 40 (Apps)
```

Twee luisterende poorten op de container:

- **Traefik op CT 165** handelt TLS-terminatie af en proxied naar Forgejo op poort 3000. Security headers en certificate management via step-ca ACME draaien op de Traefik-container, niet op CT 160
- **Forgejo op 3000** luistert op `0.0.0.0:3000`, maar een iptables INPUT chain beperkt toegang tot het IP van de Traefik-container. Verkeer van andere bronnen wordt gedropt
- **Forgejo SSH op 2222** is de ingebouwde Go-based SSH server voor git push/pull. SSH-verkeer gaat direct naar CT 160 zonder Traefik tussenkomst. Niet-standaard poort om een conflict met de Forgejo Runner (CT 161) te vermijden

Geen publieke tunnel, geen Cloudflare. Alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 160 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 2 cores |
| RAM | 1024 MB |
| Swap | 512 MB |
| Disk | 20 GB op SATA-directory (`local-sata`) |
| VLAN | 40 (Apps) |
| IP | Statisch, toegewezen via containerconfiguratie |
| Boot | `onboot: 1` |
| Features | `nesting=1` (vereist voor systemd 257 in unprivileged LXC) |
| Tags | `forgejo`, `homelab` |

De rootfs staat op de SATA-directory in plaats van de NVMe thin pool. Forgejo is niet I/O-intensief bij normaal gebruik en de 20 GB past beter op de bulk-storage dan op de snelle maar kleinere NVMe.

## Software

Binary install, geen Docker. Eén systemd service draait op de container:

| Component | Versie | Installatie |
|-----------|--------|-------------|
| Forgejo | 11.0.12 (v11 LTS) | Binary in `/usr/local/bin/forgejo`, SHA256-geverifieerd tegen het gepubliceerde checksum-bestand |

Forgejo v11 LTS krijgt support tot juli 2026. Upgrades zijn bewuste acties: nieuwe binary downloaden, checksum verifiëren, vervangen, service herstarten.

## Security-configuratie

### app.ini

| Instelling | Waarde | Reden |
|------------|--------|-------|
| `INSTALL_LOCK` | `true` | Blokkeert de installer-pagina |
| `DISABLE_REGISTRATION` | `true` | Geen open registratie |
| `REQUIRE_SIGNIN_VIEW` | `true` | Anonieme bezoekers zien niks |
| `ENABLE_BASIC_AUTHENTICATION` | `false` | Forceert token-based auth voor API en git |
| `MIN_PASSWORD_LENGTH` | `16` | Sterke wachtwoorden |
| `PASSWORD_COMPLEXITY` | `lower,upper,digit,spec` | Alle karakterklassen vereist |
| `DISABLE_GIT_HOOKS` | `true` | Git hooks zijn RCE-vectoren bij gecompromitteerde repos |
| `COOKIE_SECURE` | `true` | Cookies alleen via HTTPS |
| `OFFLINE_MODE` | `true` | Geen externe CDN-calls voor avatars of assets |
| `DEFAULT_KEEP_EMAIL_PRIVATE` | `true` | E-mailadressen standaard verborgen |
| `DEFAULT_ALLOW_CREATE_ORGANIZATION` | `false` | Single-user instance |

### SSRF-oppervlak beperkt

| Feature | Status | Reden |
|---------|--------|-------|
| Webhooks | `ALLOWED_HOST_LIST = private` | Alleen interne hosts |
| Migrations | `ALLOWED_DOMAINS` leeg, `ALLOW_LOCAL_NETWORKS = false` | Geen repo-import van externe bronnen |
| Mirrors | `ENABLED = false` | Geen outbound mirror-traffic |
| Packages | `ENABLED = false` | Geen package registry nodig |
| Mailer | `ENABLED = false` | Geen e-mail versturing |
| LFS | `LFS_START_SERVER = false` | Geen Large File Storage nodig |
| Update checker | `ENABLED = false` | Geen outbound calls naar Forgejo servers |

### systemd hardening

De Forgejo service unit bevat sandbox directives die de blast radius bij een compromis beperken:

| Directive | Effect |
|-----------|--------|
| `NoNewPrivileges=true` | Voorkomt privilege escalation via setuid |
| `ProtectSystem=strict` | Filesystem read-only behalve expliciet toegestane paden |
| `ProtectHome=true` | Geen toegang tot /home |
| `PrivateTmp=true` | Eigen /tmp namespace |
| `PrivateDevices=true` | Geen hardware device access |
| `ProtectKernelTunables=true` | Geen /proc/sys schrijfrechten |
| `ProtectKernelModules=true` | Geen kernel module loading |
| `ProtectControlGroups=true` | Geen cgroup schrijfrechten |
| `ReadWritePaths` | Alleen `/var/lib/forgejo` en `/etc/forgejo` |

### Bestandspermissies

| Bestand | Eigenaar | Rechten | Reden |
|---------|----------|---------|-------|
| `app.ini` | `root:git` | `640` | Bevat `SECRET_KEY`, `INTERNAL_TOKEN` en `JWT_SECRET`. Alleen leesbaar voor de git user |

TLS-certificaten worden niet meer lokaal beheerd op CT 160. Traefik op CT 165 handelt alle certificaten af via step-ca ACME.

## Security headers

Traefik op CT 165 past de volgende headers toe via een globale middleware op entrypoint-niveau. Dezelfde headers die eerder in de Caddy-config stonden, worden nu centraal afgehandeld voor alle services achter Traefik:

| Header | Waarde |
|--------|--------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Server` | Verwijderd (header strip) |
| `X-Powered-By` | Verwijderd (header strip) |

## Tweefactorauthenticatie

| Factor | Type | Rol |
|--------|------|-----|
| YubiKey 5C NFC | WebAuthn/Passkey | Primair |
| 2FAS Auth | TOTP | Backup |

Zelfde patroon als bij Vaultwarden en PVE: hardware key als primaire factor, TOTP als onafhankelijke backup.

## TLS

Traefik op CT 165 vraagt automatisch certificaten aan bij de interne step-ca ACME server. De certificaten zijn EC P-256 met een geldigheid van 72 uur en worden automatisch vernieuwd voor ze verlopen. Forgejo zelf heeft geen TLS-configuratie meer; alle TLS-terminatie gebeurt op Traefik. De step-ca root CA staat als trusted root in de macOS system keychain, waardoor alle browsers het cert vertrouwen zonder exceptions.

## Toegang

| Pad | Doel |
|-----|------|
| `https://forgejo.jacops.local` | Web UI (dagelijks gebruik) |
| `ssh://forgejo.jacops.local:2222` | Git SSH (push/pull) |
| `https://forgejo.jacops.local/api/v1` | REST API (token-based) |

Alle paden zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem inclusief de SQLite database, repositories en configuratie.

## Gerelateerd

- [Roadmap](../docs/roadmap.nl.md): Forgejo is de derde foundation service na PBS en Vaultwarden
- [YubiKey](../hardware/01-yubikey.nl.md): hardware 2FA setup en homelab CA
- [Vaultwarden](04-vaultwarden.nl.md): credentials van deze deploy staan in de vault
- [Decisions](../docs/decisions.nl.md): "Eigen homelab CA boven self-signed certificaten"
