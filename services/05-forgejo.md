# Forgejo

🇬🇧 English | 🇳🇱 [Nederlands](05-forgejo.nl.md)

Forgejo is the self-hosted Git forge for the homelab. All code, configuration and automation related to the homelab lives here. It runs as a native binary in an LXC container behind Caddy as reverse proxy, accessible internally via `forgejo.jacops.local`.

## Why Forgejo

The homelab generates configuration files, compose files, scripts and documentation with every new service. Without a dedicated Git server, those files live scattered across hosts or only in a public GitHub repo. A self-hosted forge provides version control for everything that should not be public. CI/CD via Forgejo Actions follows once the runner (CT 161) is deployed.

Forgejo is a community fork of Gitea, licensed under GPL. The v11 LTS line is supported until July 2026. Forgejo was chosen over Gitea for its governance model: it is managed by a foundation rather than a commercial entity, which better fits a homelab that wants to avoid dependency on licensing changes.

## Architecture

```
Browser ─── HTTPS ──► Caddy (TLS termination) ──► Forgejo
                      :443                        :3000 (localhost only)
                      CA cert + security headers   Web UI + API

Git SSH ─── TCP ──► Forgejo built-in SSH
                    :2222
                    Key-based auth

            LXC Container (CT 160)
            ┌──────────────────────────────────┐
            │  Caddy (systemd, port 443)       │
            │  Forgejo (systemd, port 3000)    │
            │  Forgejo SSH (port 2222)         │
            └──────────────────────────────────┘
            VLAN 40 (Apps)
```

Three listening ports on the container:

- **Caddy on 443** handles TLS termination and proxies to Forgejo. Adds security headers and hides the server identifier
- **Forgejo on 3000** listens only on `127.0.0.1`, not on the network. Only reachable through Caddy
- **Forgejo SSH on 2222** is the built-in Go-based SSH server for git push/pull. Non-standard port to avoid a conflict with the Forgejo Runner (CT 161)

No public tunnel, no Cloudflare. Only reachable via the local network or WireGuard.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 160 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 2 cores |
| RAM | 1024 MB |
| Swap | 512 MB |
| Disk | 20 GB on SATA directory (`local-sata`) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container configuration |
| Boot | `onboot: 1` |
| Features | `nesting=1` (required for systemd 257 in unprivileged LXC) |
| Tags | `forgejo`, `homelab` |

The rootfs lives on the SATA directory rather than the NVMe thin pool. Forgejo is not I/O-intensive under normal use and the 20 GB fits better on the bulk storage than on the faster but smaller NVMe.

## Software

Binary install, no Docker. Two systemd services run on the container:

| Component | Version | Installation |
|-----------|---------|-------------|
| Forgejo | 11.0.12 (v11 LTS) | Binary in `/usr/local/bin/forgejo`, SHA256-verified against the published checksum file |
| Caddy | 2.11.2 | Via the official Caddy APT repository |

Forgejo v11 LTS is supported until July 2026. Upgrades are deliberate actions: download new binary, verify checksum, replace, restart service.

## Security configuration

### app.ini

| Setting | Value | Reason |
|---------|-------|--------|
| `INSTALL_LOCK` | `true` | Blocks the installer page |
| `DISABLE_REGISTRATION` | `true` | No open registration |
| `REQUIRE_SIGNIN_VIEW` | `true` | Anonymous visitors see nothing |
| `ENABLE_BASIC_AUTHENTICATION` | `false` | Forces token-based auth for API and git |
| `MIN_PASSWORD_LENGTH` | `16` | Strong passwords |
| `PASSWORD_COMPLEXITY` | `lower,upper,digit,spec` | All character classes required |
| `DISABLE_GIT_HOOKS` | `true` | Git hooks are RCE vectors in compromised repos |
| `COOKIE_SECURE` | `true` | Cookies only via HTTPS |
| `OFFLINE_MODE` | `true` | No external CDN calls for avatars or assets |
| `DEFAULT_KEEP_EMAIL_PRIVATE` | `true` | Email addresses hidden by default |
| `DEFAULT_ALLOW_CREATE_ORGANIZATION` | `false` | Single-user instance |

### SSRF surface restricted

| Feature | Status | Reason |
|---------|--------|--------|
| Webhooks | `ALLOWED_HOST_LIST = private` | Internal hosts only |
| Migrations | `ALLOWED_DOMAINS` empty, `ALLOW_LOCAL_NETWORKS = false` | No repo import from external sources |
| Mirrors | `ENABLED = false` | No outbound mirror traffic |
| Packages | `ENABLED = false` | No package registry needed |
| Mailer | `ENABLED = false` | No email sending |
| LFS | `LFS_START_SERVER = false` | No Large File Storage needed |
| Update checker | `ENABLED = false` | No outbound calls to Forgejo servers |

### systemd hardening

The Forgejo service unit includes sandbox directives that limit the blast radius in case of a compromise:

| Directive | Effect |
|-----------|--------|
| `NoNewPrivileges=true` | Prevents privilege escalation via setuid |
| `ProtectSystem=strict` | Filesystem read-only except explicitly allowed paths |
| `ProtectHome=true` | No access to /home |
| `PrivateTmp=true` | Own /tmp namespace |
| `PrivateDevices=true` | No hardware device access |
| `ProtectKernelTunables=true` | No /proc/sys write access |
| `ProtectKernelModules=true` | No kernel module loading |
| `ProtectControlGroups=true` | No cgroup write access |
| `ReadWritePaths` | Only `/var/lib/forgejo` and `/etc/forgejo` |

### File permissions

| File | Owner | Mode | Reason |
|------|-------|------|--------|
| `app.ini` | `root:git` | `640` | Contains `SECRET_KEY`, `INTERNAL_TOKEN` and `JWT_SECRET`. Only readable by the git user |
| TLS private key | `root:caddy` | `640` | Only readable by Caddy |

## Caddy security headers

Caddy adds the following headers to all responses:

| Header | Value |
|--------|-------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Server` | Removed |

## Two-factor authentication

| Factor | Type | Role |
|--------|------|------|
| YubiKey 5C NFC | WebAuthn/Passkey | Primary |
| 2FAS Auth | TOTP | Backup |

Same pattern as Vaultwarden and PVE: hardware key as primary factor, TOTP as independent backup.

## TLS

Caddy uses a certificate signed by the `JacOps Homelab CA`. The cert is valid for two years and has `forgejo.jacops.local` as SAN. The CA is installed as a trusted root in the macOS system keychain, so all browsers trust the cert without exceptions.

## Access

| Path | Purpose |
|------|---------|
| `https://forgejo.jacops.local` | Web UI (daily use) |
| `ssh://forgejo.jacops.local:2222` | Git SSH (push/pull) |
| `https://forgejo.jacops.local/api/v1` | REST API (token-based) |

All paths are only reachable via the local network or WireGuard. There is no public URL.

## Backup

The container is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). This captures the full container filesystem including the SQLite database, repositories and configuration.

## Related

- [Roadmap](../docs/roadmap.md): Forgejo is the third foundation service after PBS and Vaultwarden
- [YubiKey](../hardware/01-yubikey.md): hardware 2FA setup and homelab CA
- [Vaultwarden](04-vaultwarden.md): credentials from this deploy are stored in the vault
- [Decisions](../docs/decisions.md): "Own homelab CA over self-signed certificates"
