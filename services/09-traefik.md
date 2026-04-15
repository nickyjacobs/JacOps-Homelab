# Traefik

🇬🇧 English | 🇳🇱 [Nederlands](09-traefik.nl.md)

Traefik is the homelab's central reverse proxy. All HTTPS traffic to foundation services flows through this single LXC container, which handles TLS termination, automatic certificate renewal via step-ca and global security headers. It runs as a native Go binary in an LXC container, accessible internally via `traefik.jacops.local`.

## Why a central reverse proxy

Until now, each service ran its own Caddy as reverse proxy in the same container: Vaultwarden (CT 152), Forgejo (CT 160) and Miniflux (CT 163) each had their own TLS config, their own certificate and their own set of security headers. That worked, but does not scale. Every new service meant a new Caddy configuration, a new manually generated certificate and an additional maintenance point.

Traefik centralizes this into a single point. Once configured, every new backend service gets TLS via ACME, security headers via shared middleware and routing via a single YAML file. Traefik was chosen over keeping Caddy because of the homelab's mixed setup: some services run as Docker containers, others as native binaries in LXC. Traefik's provider model handles both without plugins or workarounds. See [decisions.md](../docs/decisions.md) for the full reasoning.

## Architecture

```
Browser ─── HTTPS ──► Traefik (TLS termination) ──► Backend services
                      :443                          (HTTP, same VLAN)
                      step-ca ACME certs
                      Security headers

                LXC Container (CT 165)
                ┌──────────────────────────────────────┐
                │  Traefik v3.6.13                     │
                │  ├─ Entrypoints :80, :443            │
                │  ├─ ACME resolver (step-ca)          │
                │  ├─ File provider (dynamic/)         │
                │  └─ Global security headers          │
                └──────────────────────────────────────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
        CT 152       CT 160       CT 163
      Vaultwarden   Forgejo      Miniflux
        :8222        :3000        :8080
```

Two entrypoints:

- **web on :80** redirects all traffic to :443 via a permanent redirect. No plain HTTP content
- **websecure on :443** handles TLS termination with certificates from step-ca and applies the global security headers middleware to all routes

Backend traffic goes as unencrypted HTTP over the same VLAN. This is acceptable because the Apps VLAN (40) is isolated from other zones via the UniFi firewall, and each backend LXC has additional iptables rules that restrict the service port to Traefik's IP. An attacker on the VLAN could see the traffic, but without access to a backend host there is nothing to listen to.

No public tunnel, no Cloudflare. Only reachable via the local network or WireGuard.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 165 |
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
| Firewall | `firewall: 1` |
| Features | `nesting=1` |
| Tags | `foundation`, `reverse-proxy`, `traefik` |

## Software

Binary install, no Docker. A single systemd service runs on the container:

| Component | Version | Installation |
|-----------|---------|-------------|
| Traefik | 3.6.13 | Go binary in `/usr/local/bin/traefik`, SHA256-verified |

Traefik runs as a dedicated `traefik` user. Upgrades are deliberate actions: download new binary, verify checksum, replace, restart service.

## Static configuration

The static configuration in `/etc/traefik/traefik.yml` defines entrypoints, the ACME resolver and the file provider:

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      middlewares:
        - security-headers@file

certificatesResolvers:
  step-ca:
    acme:
      email: admin@jacops.local
      storage: /etc/traefik/acme.json
      certificatesDuration: 72
      caServer: https://step-ca.jacops.local:8443/acme/acme/directory
      tlsChallenge: {}

providers:
  file:
    directory: /etc/traefik/dynamic/
    watch: true

api:
  dashboard: true

log:
  level: WARN
```

The `certificatesDuration` of 72 hours matches step-ca's default. Traefik renews automatically before the certificate expires, without manual intervention. The `tlsChallenge` uses tls-alpn-01, which does not require port 80 on the backend and does not need DNS record changes.

## Dynamic configuration

The directory `/etc/traefik/dynamic/` contains one YAML file per service plus a shared middlewares file. Traefik watches the directory and reloads automatically on changes.

### middlewares.yml

Shared middleware applied at entrypoint level:

```yaml
http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        stsIncludeSubdomains: true
        stsSeconds: 63072000
        referrerPolicy: strict-origin-when-cross-origin
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""
```

All responses receive these headers. The `Server` and `X-Powered-By` headers are emptied to make server fingerprinting harder.

### Per-service configuration

Each YAML file in `dynamic/` defines a router, service and health check for a backend:

**svc-vaultwarden.yml**

```yaml
http:
  routers:
    vaultwarden:
      rule: "Host(`vault.jacops.local`)"
      entryPoints:
        - websecure
      service: vaultwarden
      tls:
        certResolver: step-ca
  services:
    vaultwarden:
      loadBalancer:
        servers:
          - url: "http://<ct-ip>:8222"
        healthCheck:
          path: /alive
          interval: 30s
          timeout: 5s
```

**svc-forgejo.yml**

```yaml
http:
  routers:
    forgejo:
      rule: "Host(`forgejo.jacops.local`)"
      entryPoints:
        - websecure
      service: forgejo
      tls:
        certResolver: step-ca
  services:
    forgejo:
      loadBalancer:
        servers:
          - url: "http://<ct-ip>:3000"
        healthCheck:
          path: /
          interval: 30s
          timeout: 5s
```

**svc-miniflux.yml**

```yaml
http:
  routers:
    miniflux:
      rule: "Host(`miniflux.jacops.local`)"
      entryPoints:
        - websecure
      service: miniflux
      tls:
        certResolver: step-ca
  services:
    miniflux:
      loadBalancer:
        servers:
          - url: "http://<ct-ip>:8080"
        healthCheck:
          path: /healthcheck
          interval: 30s
          timeout: 5s
```

**svc-dashboard.yml**

```yaml
http:
  routers:
    dashboard:
      rule: "Host(`traefik.jacops.local`)"
      entryPoints:
        - websecure
      service: api@internal
      tls:
        certResolver: step-ca
      middlewares:
        - dashboard-auth
        - dashboard-ipallow
  middlewares:
    dashboard-auth:
      basicAuth:
        usersFile: /etc/traefik/dashboard-users
    dashboard-ipallow:
      ipAllowList:
        sourceRange:
          - "10.120.0.0/16"
```

## Dashboard security

The Traefik dashboard is secured with two layers:

- **basicAuth** with credentials in `/etc/traefik/dashboard-users` (bcrypt hash, `chmod 600`). The password is stored in Vaultwarden as `homelab/traefik-dashboard-password`
- **ipAllowList** restricts access to internal networks (`10.120.0.0/16`). Requests from outside this range are rejected regardless of valid credentials

## TLS and ACME

Traefik requests certificates from step-ca via the standard ACME protocol, exactly as it would from Let's Encrypt. The difference is that step-ca is an internal ACME server that issues short-lived certificates.

| Setting | Value |
|---------|-------|
| ACME server | `https://step-ca.jacops.local:8443/acme/acme/directory` |
| Challenge type | tls-alpn-01 |
| Certificate duration | 72 hours |
| Renewal | Automatic by Traefik |
| Storage | `/etc/traefik/acme.json` (`chmod 600`) |

The step-ca root CA is installed as a trusted root in the macOS system keychain, so all browsers trust the certificates presented by Traefik without exceptions.

Service DNS records (`vault.jacops.local`, `forgejo.jacops.local`, `miniflux.jacops.local`, `traefik.jacops.local`) all point to Traefik's IP via UniFi DNS policies. TLS termination happens at Traefik, not at the backends.

## Backend firewall

Backend traffic goes as HTTP over the VLAN. To prevent other hosts on the same VLAN from reaching backend ports directly, each backend LXC has additional iptables rules that restrict the service port to Traefik's IP.

### Docker-based services (Vaultwarden, Miniflux)

Docker publishes ports via the DOCKER-USER chain. Rules in that chain apply to all traffic Docker forwards:

```
iptables -I DOCKER-USER -p tcp --dport <service-port> ! -s <traefik-ip> -j DROP
```

### Native services (Forgejo)

Forgejo listens as a systemd service, not via Docker. The restriction goes through the INPUT chain:

```
iptables -A INPUT -p tcp --dport 3000 -s <traefik-ip> -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -j DROP
```

The result is that backend ports are only reachable from Traefik. Direct access via IP and port is dropped.

## systemd hardening

The Traefik service unit includes sandbox directives and capability restrictions:

| Directive | Effect |
|-----------|--------|
| `User=traefik` | Dedicated service user, no root |
| `AmbientCapabilities=CAP_NET_BIND_SERVICE` | Allowed to bind on port 80 and 443 without root |
| `NoNewPrivileges=true` | Prevents privilege escalation via setuid |
| `ProtectSystem=strict` | Filesystem read-only except explicitly allowed paths |
| `ProtectHome=true` | No access to /home |
| `PrivateTmp=true` | Own /tmp namespace |
| `PrivateDevices=true` | No hardware device access |
| `ProtectKernelTunables=true` | No /proc/sys write access |
| `ProtectKernelModules=true` | No kernel module loading |
| `ProtectControlGroups=true` | No cgroup write access |
| `ReadWritePaths` | Only `/etc/traefik` |

`AmbientCapabilities=CAP_NET_BIND_SERVICE` allows a non-root user to listen on privileged ports. No `setcap` on the binary needed.

## Access

| Path | Purpose |
|------|---------|
| `https://traefik.jacops.local` | Dashboard (configuration overview) |
| `https://vault.jacops.local` | Vaultwarden (via Traefik) |
| `https://forgejo.jacops.local` | Forgejo (via Traefik) |
| `https://miniflux.jacops.local` | Miniflux (via Traefik) |

All paths are only reachable via the local network or WireGuard. There is no public URL. DNS records are managed via UniFi DNS policies and point to the Traefik container's IP.

## Backup

The container is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). This captures the full container filesystem including the Traefik configuration, dynamic service files and the `acme.json` file with the ACME account key.

## Related

- [Roadmap](../docs/roadmap.md): Traefik replaces per-service Caddy as part of the Phase 1 foundation
- [Decisions](../docs/decisions.md): "Traefik as default reverse proxy, replacing Caddy"
- [Vaultwarden](04-vaultwarden.md): backend on CT 152, dashboard credentials in the vault
- [Forgejo](05-forgejo.md): backend on CT 160
- [Miniflux](07-miniflux.md): backend on CT 163
