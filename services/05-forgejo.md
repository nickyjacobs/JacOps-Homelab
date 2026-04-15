# Forgejo

🇬🇧 English | 🇳🇱 [Nederlands](05-forgejo.nl.md)

Forgejo is the self-hosted Git forge for the homelab. All code, configuration and automation related to the homelab lives here. It runs as a native binary in an LXC container behind Traefik as central reverse proxy, accessible internally via `forgejo.jacops.local`.

## Why Forgejo

The homelab generates configuration files, compose files, scripts and documentation with every new service. Without a dedicated Git server, those files live scattered across hosts or only in a public GitHub repo. A self-hosted forge provides version control for everything that should not be public. CI/CD via Forgejo Actions runs on the [Forgejo Runner](06-forgejo-runner.md) (CT 161).

Forgejo is a community fork of Gitea, licensed under GPL. The v11 LTS line is supported until July 2026. Forgejo was chosen over Gitea for its governance model: it is managed by a foundation rather than a commercial entity, which better fits a homelab that wants to avoid dependency on licensing changes.

## Architecture

```
Browser ─── HTTPS ──► Traefik (CT 165)  ──► Forgejo (CT 160)
                      :443                   :3000
                      step-ca ACME certs     Traefik only
                      Security headers       (iptables firewall)

Git SSH ─── SSH ──────────────────────────► Forgejo (CT 160)
                                            :2222
                                            Direct (not through Traefik)

                LXC Container (CT 160)
                ┌──────────────────────────────────────┐
                │  Forgejo v11.0.12 (systemd)          │
                │  ├─ HTTP :3000 (web + API)           │
                │  └─ SSH :2222 (git operations)       │
                └──────────────────────────────────────┘
                VLAN 40 (Apps)
```

Two listening ports on the container:

- **Traefik on CT 165** handles TLS termination and proxies to Forgejo on port 3000. Security headers and certificate management via step-ca ACME run on the Traefik container, not on CT 160
- **Forgejo on 3000** listens on `0.0.0.0:3000`, but an iptables INPUT chain restricts access to the Traefik container IP. Traffic from other sources is dropped
- **Forgejo SSH on 2222** is the built-in Go-based SSH server for git push/pull. SSH traffic goes directly to CT 160 without passing through Traefik. Non-standard port to avoid a conflict with the Forgejo Runner (CT 161)

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

Binary install, no Docker. One systemd service runs on the container:

| Component | Version | Installation |
|-----------|---------|-------------|
| Forgejo | 11.0.12 (v11 LTS) | Binary in `/usr/local/bin/forgejo`, SHA256-verified against the published checksum file |

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

TLS certificates are no longer managed locally on CT 160. Traefik on CT 165 handles all certificates via step-ca ACME.

## Security headers

Traefik on CT 165 applies the following headers via a global entrypoint-level middleware. The same headers that were previously in the Caddy config are now handled centrally for all services behind Traefik:

| Header | Value |
|--------|-------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Server` | Removed (header strip) |
| `X-Powered-By` | Removed (header strip) |

## Two-factor authentication

| Factor | Type | Role |
|--------|------|------|
| YubiKey 5C NFC | WebAuthn/Passkey | Primary |
| 2FAS Auth | TOTP | Backup |

Same pattern as Vaultwarden and PVE: hardware key as primary factor, TOTP as independent backup.

## TLS

Traefik on CT 165 automatically requests certificates from the internal step-ca ACME server. Certificates are EC P-256 with 72 hours validity and are renewed automatically before expiry. Forgejo itself no longer has any TLS configuration; all TLS termination happens at Traefik. The step-ca root CA is installed as a trusted root in the macOS system keychain, so all browsers trust the cert without exceptions.

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
