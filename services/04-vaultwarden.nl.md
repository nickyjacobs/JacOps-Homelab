# Vaultwarden

🇬🇧 [English](04-vaultwarden.md) | 🇳🇱 Nederlands

Vaultwarden is de self-hosted password vault van het homelab. Alle credentials die uit een deploy komen landen hier. Het draait als Docker stack in een LXC-container achter Caddy als reverse proxy, intern bereikbaar via `vault.jacops.local`.

## Waarom self-hosted

Het homelab genereert bij elke service-deploy nieuwe credentials: API-tokens, admin-wachtwoorden, database-users, registratie-tokens. Zonder een centraal punt landen die in tekstbestanden op hosts, in shell-history of op papier. Dat schaalt niet en is niet veilig.

Vaultwarden is een lichtgewicht Rust-implementatie van de Bitwarden API. Het draait op een fractie van de resources die de officiele Bitwarden-server nodig heeft (512 MB RAM versus meerdere GB) en ondersteunt dezelfde clients: browser-extensies, desktop-apps en mobiele apps.

De keuze voor self-hosted in plaats van Bitwarden cloud is bewust beperkt tot homelab-credentials. Persoonlijke credentials (bankzaken, social media, e-mail) migreren naar Bitwarden cloud, dat een dedicated security-team en onafhankelijke audits heeft. Zie de [roadmap](../docs/roadmap.nl.md) onder "Bitwarden cloud gratis tier" voor de afweging.

## Architectuur

```
Browser/App ─── HTTPS ──► Caddy (TLS termination) ──► Vaultwarden
                          :443                        :8222
                          CA-cert                     Alleen via Docker netwerk

                LXC Container (CT 152)
                ┌─────────────────────────────┐
                │  Docker Compose             │
                │  ├─ Caddy (poort 443)       │
                │  └─ Vaultwarden (poort 8222)│
                └─────────────────────────────┘
                VLAN 40 (Apps)
```

Twee containers draaien in een enkele Docker Compose stack:

- **Vaultwarden** draait de vault-engine en web UI. Bindt op poort 8222 binnen het Docker-netwerk, niet op een host-poort. Is alleen bereikbaar via Caddy
- **Caddy** handelt TLS-terminatie af met een certificaat ondertekend door de [homelab CA](../hardware/01-yubikey.nl.md). Proxied verkeer door naar Vaultwarden en voegt de `X-Real-IP` header toe

Geen publieke tunnel, geen Cloudflare. De service is alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 152 |
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
| Tags | `docker`, `homelab`, `vaultwarden` |

## Docker images

Beide images zijn gepind op tag plus SHA256 digest. Upgrades zijn bewuste acties.

| Image | Versie |
|-------|--------|
| `vaultwarden/server` | 1.35.4 |
| `caddy` | 2.11.2-alpine |

Vaultwarden 1.35.4 bevat fixes voor drie security advisories (cipher access, collection permissions). Updaten naar nieuwere versies volgt hetzelfde patroon: digest ophalen, compose bijwerken, `docker compose up -d`.

## Security-configuratie

| Instelling | Waarde | Reden |
|------------|--------|-------|
| `SIGNUPS_ALLOWED` | `false` | Geen open registratie |
| `INVITATIONS_ALLOWED` | `false` | Geen uitnodigingen |
| `DISABLE_ICON_DOWNLOAD` | `true` | SSRF-mitigatie. Vaultwarden haalt geen favicons op van externe sites |
| `PASSWORD_ITERATIONS` | `600000` | KDF-iteraties boven de Bitwarden-aanbeveling voor extra brute-force bescherming |
| `ADMIN_TOKEN` | Argon2id hash | Het admin panel is beveiligd met een gehashte token, niet plain-text |
| `IP_HEADER` | `X-Real-IP` | Caddy stuurt het echte client-IP door |

De `docker-compose.yml` heeft `chmod 600` omdat het de Argon2 hash van het admin token bevat. De TLS private key in de Caddy certs-directory heeft dezelfde restrictie.

## Tweefactorauthenticatie

| Factor | Type | Rol |
|--------|------|-----|
| YubiKey 5C NFC | WebAuthn/Passkey | Primair |
| 2FAS Auth | TOTP | Backup |

De YubiKey is geregistreerd als passkey bij het Vaultwarden-account. 2FAS Auth op de iPhone dient als onafhankelijke backup. De TOTP-seed leeft buiten Vaultwarden, zodat er geen circulaire afhankelijkheid ontstaat.

## TLS

Caddy gebruikt een certificaat ondertekend door de `JacOps Homelab CA`. Het cert is geldig voor twee jaar en heeft `vault.jacops.local` als SAN. De CA staat als trusted root in de macOS system keychain, waardoor alle browsers het cert vertrouwen zonder exceptions.

De Caddyfile:

```
vault.jacops.local {
    tls /certs/vault.jacops.local.pem /certs/vault.jacops.local.key

    reverse_proxy vaultwarden:8222 {
        header_up X-Real-IP {remote_host}
    }
}
```

## Toegang

| Pad | Doel |
|-----|------|
| `https://vault.jacops.local` | Web vault (dagelijks gebruik) |
| `https://vault.jacops.local/admin` | Admin panel (configuratie) |

Beide zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem inclusief de Docker volumes met de SQLite database en alle vault-data.

Twee extra backup-lagen staan gepland als follow-up:

- **Dagelijks restic** naar PBS voor de `/opt/vaultwarden/data` directory
- **Wekelijks encrypted tar** via `age` naar een externe Backblaze B2 bucket

## Gerelateerd

- [roadmap](../docs/roadmap.nl.md): Vaultwarden is de tweede foundation service na PBS
- [YubiKey](../hardware/01-yubikey.nl.md): hardware 2FA setup en homelab CA
- [decisions](../docs/decisions.nl.md): "Eigen homelab CA boven self-signed certificaten"
