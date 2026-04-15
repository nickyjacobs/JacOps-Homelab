# Traefik

🇬🇧 [English](09-traefik.md) | 🇳🇱 Nederlands

Traefik is de centrale reverse proxy van het homelab. Alle HTTPS-verkeer naar foundation services loopt via deze ene LXC-container, die TLS-terminatie, automatische certificaatvernieuwing via step-ca en globale security headers afhandelt. Het draait als native Go binary in een LXC-container, intern bereikbaar via `traefik.jacops.local`.

## Waarom een centrale reverse proxy

Tot nu toe draaide elke service zijn eigen Caddy als reverse proxy in dezelfde container: Vaultwarden (CT 152), Forgejo (CT 160) en Miniflux (CT 163) hadden elk een eigen TLS-config, eigen certificaat en eigen set security headers. Dat werkte, maar schaalt niet. Elke nieuwe service betekende een nieuwe Caddy-configuratie, een nieuw handmatig gegenereerd certificaat en een extra onderhoudspunt.

Traefik centraliseert dat in een enkel punt. Eenmaal geconfigureerd, krijgt elke nieuwe backend-service TLS via ACME, security headers via gedeelde middleware en routing via een enkel YAML-bestand. De keuze voor Traefik boven het behouden van Caddy is de mixed setup van het homelab: sommige services draaien als Docker containers, andere als native binaries in LXC. Traefik's provider-model handelt beide af zonder plugins of workarounds. Zie [decisions.nl.md](../docs/decisions.nl.md) voor de volledige afweging.

## Architectuur

```
Browser ─── HTTPS ──► Traefik (TLS termination) ──► Backend services
                      :443                          (HTTP, zelfde VLAN)
                      step-ca ACME certs
                      Security headers

                LXC Container (CT 165)
                ┌──────────────────────────────────────┐
                │  Traefik v3.6.13                     │
                │  ├─ Entrypoints :80, :443            │
                │  ├─ ACME resolver (step-ca)          │
                │  ├─ File provider (dynamic/)         │
                │  └─ Globale security headers         │
                └──────────────────────────────────────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
        CT 152       CT 160       CT 163
      Vaultwarden   Forgejo      Miniflux
        :8222        :3000        :8080
```

Twee entrypoints:

- **web op :80** stuurt al het verkeer via een permanente redirect door naar :443. Geen plain HTTP content
- **websecure op :443** handelt TLS-terminatie af met certificaten van step-ca en past de globale security headers middleware toe op alle routes

Backend-verkeer gaat als onversleuteld HTTP over hetzelfde VLAN. Dat is acceptabel omdat het Apps VLAN (40) geisoleerd is van andere zones via de UniFi firewall, en elke backend-LXC aanvullend iptables-regels heeft die de servicepoort beperken tot het IP van Traefik. Een aanvaller op het VLAN kan het verkeer zien, maar zonder toegang tot een backend-host is er niks om naar te luisteren.

Geen publieke tunnel, geen Cloudflare. Alleen bereikbaar via het lokale netwerk of WireGuard.

## Container specs

| Instelling | Waarde |
|------------|--------|
| VMID | 165 |
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
| Firewall | `firewall: 1` |
| Features | `nesting=1` |
| Tags | `foundation`, `reverse-proxy`, `traefik` |

## Software

Binary install, geen Docker. Een systemd service draait op de container:

| Component | Versie | Installatie |
|-----------|--------|-------------|
| Traefik | 3.6.13 | Go binary in `/usr/local/bin/traefik`, SHA256-geverifieerd |

Traefik draait als een dedicated `traefik` user. Upgrades zijn bewuste acties: nieuwe binary downloaden, checksum verifiëren, vervangen, service herstarten.

## Statische configuratie

De statische configuratie in `/etc/traefik/traefik.yml` definieert entrypoints, de ACME resolver en de file provider:

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

De `certificatesDuration` van 72 uur matcht de default van step-ca. Traefik vernieuwt automatisch voordat het certificaat verloopt, zonder handmatige tussenkomst. De `tlsChallenge` gebruikt tls-alpn-01, wat geen poort 80 vereist op de backend en geen DNS-records hoeft aan te passen.

## Dynamische configuratie

De map `/etc/traefik/dynamic/` bevat een YAML-bestand per service plus een gedeeld middlewares-bestand. Traefik watched de directory en herlaadt automatisch bij wijzigingen.

### middlewares.yml

Gedeelde middleware die op entrypoint-niveau wordt toegepast:

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

Alle responses krijgen deze headers. De `Server` en `X-Powered-By` headers worden leeg gezet om server-fingerprinting te bemoeilijken.

### Per-service configuratie

Elk YAML-bestand in `dynamic/` definieert een router, service en health check voor een backend:

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

## Dashboard-beveiliging

Het Traefik dashboard is beveiligd met twee lagen:

- **basicAuth** met credentials in `/etc/traefik/dashboard-users` (bcrypt hash, `chmod 600`). Het wachtwoord staat in Vaultwarden als `homelab/traefik-dashboard-password`
- **ipAllowList** beperkt de toegang tot interne netwerken (`10.120.0.0/16`). Verzoeken van buiten dit bereik worden geweigerd, ongeacht geldige credentials

## TLS en ACME

Traefik vraagt certificaten aan bij step-ca via het standaard ACME protocol, exact zoals het dat bij Let's Encrypt zou doen. Het verschil is dat step-ca een interne ACME server is die kortstondige certificaten uitgeeft.

| Instelling | Waarde |
|------------|--------|
| ACME server | `https://step-ca.jacops.local:8443/acme/acme/directory` |
| Challenge type | tls-alpn-01 |
| Certificaatduur | 72 uur |
| Vernieuwing | Automatisch door Traefik |
| Storage | `/etc/traefik/acme.json` (`chmod 600`) |

De step-ca root CA staat als trusted root in de macOS system keychain, waardoor alle browsers de door Traefik gepresenteerde certificaten vertrouwen zonder exceptions.

Service DNS-records (`vault.jacops.local`, `forgejo.jacops.local`, `miniflux.jacops.local`, `traefik.jacops.local`) wijzen allemaal naar het IP van Traefik via UniFi DNS-policies. TLS-terminatie vindt plaats op Traefik, niet op de backends.

## Backend-firewall

Backend-verkeer gaat als HTTP over het VLAN. Om te voorkomen dat andere hosts op hetzelfde VLAN de backend-poorten direct kunnen bereiken, heeft elke backend-LXC aanvullende iptables-regels die de servicepoort beperken tot het IP van Traefik.

### Docker-based services (Vaultwarden, Miniflux)

Docker publiceert poorten via de DOCKER-USER chain. Regels in die chain gelden voor al het verkeer dat Docker forward:

```
iptables -I DOCKER-USER -p tcp --dport <service-port> ! -s <traefik-ip> -j DROP
```

### Native services (Forgejo)

Forgejo luistert als systemd service, niet via Docker. De restrictie gaat via de INPUT chain:

```
iptables -A INPUT -p tcp --dport 3000 -s <traefik-ip> -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -j DROP
```

Het resultaat is dat de backend-poorten alleen bereikbaar zijn vanaf Traefik. Directe toegang via IP en poort wordt gedropt.

## systemd hardening

De Traefik service unit bevat sandbox directives en capability-beperkingen:

| Directive | Effect |
|-----------|--------|
| `User=traefik` | Dedicated service-user, geen root |
| `AmbientCapabilities=CAP_NET_BIND_SERVICE` | Mag binden op poort 80 en 443 zonder root |
| `NoNewPrivileges=true` | Voorkomt privilege escalation via setuid |
| `ProtectSystem=strict` | Filesystem read-only behalve expliciet toegestane paden |
| `ProtectHome=true` | Geen toegang tot /home |
| `PrivateTmp=true` | Eigen /tmp namespace |
| `PrivateDevices=true` | Geen hardware device access |
| `ProtectKernelTunables=true` | Geen /proc/sys schrijfrechten |
| `ProtectKernelModules=true` | Geen kernel module loading |
| `ProtectControlGroups=true` | Geen cgroup schrijfrechten |
| `ReadWritePaths` | Alleen `/etc/traefik` |

`AmbientCapabilities=CAP_NET_BIND_SERVICE` maakt het mogelijk om als niet-root user op privileged poorten te luisteren. Geen `setcap` op de binary nodig.

## Toegang

| Pad | Doel |
|-----|------|
| `https://traefik.jacops.local` | Dashboard (configuratie-overzicht) |
| `https://vault.jacops.local` | Vaultwarden (via Traefik) |
| `https://forgejo.jacops.local` | Forgejo (via Traefik) |
| `https://miniflux.jacops.local` | Miniflux (via Traefik) |

Alle paden zijn alleen bereikbaar via het lokale netwerk of WireGuard. Er is geen publieke URL. De DNS-records worden beheerd via UniFi DNS-policies en wijzen naar het IP van de Traefik-container.

## Backup

De container is opgenomen in de wekelijkse PBS backup job (zondag 03:00, vier weken retentie). Dit vangt het volledige container-bestandssysteem inclusief de Traefik-configuratie, dynamische service-bestanden en het `acme.json`-bestand met de ACME account key.

## Gerelateerd

- [Roadmap](../docs/roadmap.nl.md): Traefik vervangt per-service Caddy als onderdeel van de Fase 1 foundation
- [Decisions](../docs/decisions.nl.md): "Traefik als standaard reverse proxy, Caddy vervangen"
- [Vaultwarden](04-vaultwarden.nl.md): backend op CT 152, dashboard-credentials in de vault
- [Forgejo](05-forgejo.nl.md): backend op CT 160
- [Miniflux](07-miniflux.nl.md): backend op CT 163
