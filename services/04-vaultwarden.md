# Vaultwarden

🇬🇧 English | 🇳🇱 [Nederlands](04-vaultwarden.nl.md)

Vaultwarden is the self-hosted password vault of the homelab. All credentials generated during a deploy end up here. It runs as a Docker stack in an LXC container behind Caddy as reverse proxy, accessible internally via `vault.jacops.local`.

## Why self-hosted

The homelab generates new credentials with every service deploy: API tokens, admin passwords, database users, registration tokens. Without a central store, those end up in text files on hosts, in shell history or on paper. That does not scale and is not secure.

Vaultwarden is a lightweight Rust implementation of the Bitwarden API. It runs on a fraction of the resources the official Bitwarden server requires (512 MB RAM versus several GB) and supports the same clients: browser extensions, desktop apps and mobile apps.

The choice for self-hosted over Bitwarden cloud is deliberately limited to homelab credentials. Personal credentials (banking, social media, email) migrate to Bitwarden cloud, which has a dedicated security team and independent audits. See the [roadmap](../docs/roadmap.md) under "Bitwarden cloud free tier" for the rationale.

## Architecture

```
Browser/App ─── HTTPS ──► Caddy (TLS termination) ──► Vaultwarden
                          :443                        :8222
                          CA cert                     Docker network only

                LXC Container (CT 152)
                ┌─────────────────────────────┐
                │  Docker Compose             │
                │  ├─ Caddy (port 443)        │
                │  └─ Vaultwarden (port 8222) │
                └─────────────────────────────┘
                VLAN 40 (Apps)
```

Two containers run in a single Docker Compose stack:

- **Vaultwarden** runs the vault engine and web UI. Binds on port 8222 within the Docker network, not on a host port. Only reachable via Caddy
- **Caddy** handles TLS termination with a certificate signed by the [homelab CA](../hardware/01-yubikey.md). Proxies traffic to Vaultwarden and adds the `X-Real-IP` header

No public tunnel, no Cloudflare. The service is only reachable via the local network or WireGuard.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 152 |
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
| Tags | `docker`, `homelab`, `vaultwarden` |

## Docker images

Both images are pinned to tag plus SHA256 digest. Upgrades are deliberate actions.

| Image | Version |
|-------|---------|
| `vaultwarden/server` | 1.35.4 |
| `caddy` | 2.11.2-alpine |

Vaultwarden 1.35.4 includes fixes for three security advisories (cipher access, collection permissions). Updating to newer versions follows the same pattern: fetch digest, update compose, `docker compose up -d`.

## Security configuration

| Setting | Value | Reason |
|---------|-------|--------|
| `SIGNUPS_ALLOWED` | `false` | No open registration |
| `INVITATIONS_ALLOWED` | `false` | No invitations |
| `DISABLE_ICON_DOWNLOAD` | `true` | SSRF mitigation. Vaultwarden does not fetch favicons from external sites |
| `PASSWORD_ITERATIONS` | `600000` | KDF iterations above the Bitwarden recommendation for extra brute-force protection |
| `ADMIN_TOKEN` | Argon2id hash | The admin panel is secured with a hashed token, not plain text |
| `IP_HEADER` | `X-Real-IP` | Caddy forwards the real client IP |

The `docker-compose.yml` has `chmod 600` because it contains the Argon2 hash of the admin token. The TLS private key in the Caddy certs directory has the same restriction.

## Two-factor authentication

| Factor | Type | Role |
|--------|------|------|
| YubiKey 5C NFC | WebAuthn/Passkey | Primary |
| 2FAS Auth | TOTP | Backup |

The YubiKey is registered as a passkey on the Vaultwarden account. 2FAS Auth on the iPhone serves as an independent backup. The TOTP seed lives outside Vaultwarden, avoiding a circular dependency.

## TLS

Caddy uses a certificate signed by the `JacOps Homelab CA`. The cert is valid for two years and has `vault.jacops.local` as SAN. The CA is installed as a trusted root in the macOS system keychain, so all browsers trust the cert without exceptions.

The Caddyfile:

```
vault.jacops.local {
    tls /certs/vault.jacops.local.pem /certs/vault.jacops.local.key

    reverse_proxy vaultwarden:8222 {
        header_up X-Real-IP {remote_host}
    }
}
```

## Access

| Path | Purpose |
|------|---------|
| `https://vault.jacops.local` | Web vault (daily use) |
| `https://vault.jacops.local/admin` | Admin panel (configuration) |

Both are only reachable via the local network or WireGuard. There is no public URL.

## Backup

The container is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). This captures the entire container filesystem including the Docker volumes with the SQLite database and all vault data.

Two additional backup layers are planned as follow-up:

- **Daily restic** to PBS for the `/opt/vaultwarden/data` directory
- **Weekly encrypted tar** via `age` to an external Backblaze B2 bucket

## Related

- [roadmap](../docs/roadmap.md): Vaultwarden is the second foundation service after PBS
- [YubiKey](../hardware/01-yubikey.md): hardware 2FA setup and homelab CA
- [decisions](../docs/decisions.md): "Homelab CA over self-signed certificates"
