# Uptime Kuma

🇬🇧 English | 🇳🇱 [Nederlands](02-uptime-kuma.nl.md)

Uptime Kuma is the heart of the homelab monitoring stack. It checks every service and infrastructure component on a 60-second interval, sends alerts through ntfy, and exposes a public status page for transparency.

## Why Uptime Kuma

The homelab needed a way to know when something goes down without manually checking each service. Uptime Kuma fills this role with minimal overhead. It uses around 100 MB of RAM, supports HTTP, TCP, ping, DNS and keyword monitoring out of the box, and has a clean dashboard.

The alternative was a Prometheus and Grafana stack, which provides deeper metrics (CPU, memory, disk per service) but costs 800+ MB of RAM and requires exporters on every monitored host. For a homelab with around ten monitors, that level of detail is overkill. Uptime Kuma answers the one question that matters first: is it up or not?

If the homelab grows past twenty services or needs performance metrics alongside availability data, Prometheus can be added alongside Uptime Kuma rather than replacing it. Uptime Kuma exposes a native `/metrics` endpoint that a Prometheus scrape job can consume directly.

## Architecture

Uptime Kuma no longer runs as a single container. It is the primary service in a three-container monitoring stack:

```
Internet ─── CDN Tunnel ─── Cloudflared ─────────┐
                                                 │
                LXC Container (CT 151)           │
                ┌────────────────────────────────┤
                │  Docker Compose                │
                │  ├─ Uptime Kuma (port 3001)    │
                │  ├─ ntfy (port 80 → 2586)      │
                │  └─ Cloudflared ───────────────┘
                └────────────────────────────────
                VLAN 40 (Apps)
```

All three containers share a single Docker network. Uptime Kuma reaches ntfy over that network by container name (`http://ntfy:80`), which is faster and more robust than going through the public URL. The cloudflared container routes two public hostnames to the internal services:

- `uptime.example.com` → `http://uptime-kuma:3001`
- `ntfy.example.com` → `http://ntfy:80`

One tunnel with multiple hostnames is simpler than one tunnel per service. Both services share the same failure domain anyway (the LXC), so separating them into two tunnels would not improve resilience. See [docs/decisions.md](../docs/decisions.md) for the full reasoning.

The ntfy service is documented separately in [03-ntfy.md](03-ntfy.md).

## Docker Compose

The full compose file for the monitoring stack:

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma:/app/data

  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy
    restart: always
    command: serve
    ports:
      - "2586:80"
    volumes:
      - ntfy-cache:/var/cache/ntfy
      - ntfy-etc:/etc/ntfy
    environment:
      - TZ=Europe/Amsterdam
      - NTFY_BASE_URL=https://ntfy.example.com
      - NTFY_AUTH_DEFAULT_ACCESS=deny-all
      - NTFY_BEHIND_PROXY=true

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}

volumes:
  uptime-kuma:
    external: true
  ntfy-cache:
  ntfy-etc:
```

The Uptime Kuma volume is marked `external: true` because the data volume already existed from a previous standalone container. Keeping it external prevents the data from being recreated when the stack is recreated.

The `CF_TUNNEL_TOKEN` comes from the Cloudflare Zero Trust dashboard when you create the tunnel. Store it outside the compose file (environment variable or `.env`) and never commit the real value.

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 151 |
| Type | LXC (unprivileged, nesting enabled) |
| Node | Node 1 |
| CPU | 1 core |
| RAM | 1024 MB |
| Disk | 8 GB (LVM-thin) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container config |
| Boot | `onboot: 1` |

The RAM is higher than the original 512 MB because three containers share the LXC now. With idle usage around 400-500 MB, 1 GB leaves enough headroom for peaks.

## Monitors

Ten monitors split across three labels:

| Name | Type | Target | Label |
|------|------|--------|-------|
| n8n | HTTP | Public tunnel URL | Apps |
| Uptime Kuma (local) | HTTP | `http://<container-ip>:3001` | Apps |
| Uptime Kuma (public) | HTTP | `https://uptime.example.com` | Apps |
| ntfy (local) | HTTP | `http://ntfy:80/v1/health` | Apps |
| ntfy (public) | HTTP | `https://ntfy.example.com/v1/health` | Apps |
| Proxmox Node 1 | HTTPS keyword | Management IP, port 8006, keyword "Proxmox" | Infrastructure |
| Proxmox Node 2 | HTTPS keyword | Management IP, port 8006, keyword "Proxmox" | Infrastructure |
| UniFi Gateway | Ping | Gateway IP | Network |
| UniFi Switch | Ping | Switch IP | Network |
| UniFi Access Point | Ping | AP IP | Network |
| DNS Resolution | DNS | Public domain via 9.9.9.9 | Network |

The public and local variants for Uptime Kuma and ntfy are deliberate. Local checks (over the internal Docker network) confirm the service itself is running. Public checks go through the full tunnel path and confirm the Cloudflare routing, TLS certificate, and reverse proxy headers all work. If the local check passes but the public check fails, the problem is somewhere between the CDN edge and the container, not the container itself.

The Proxmox monitors use keyword matching on the HTTPS response because a simple TCP port check would pass even if the web UI returned an error page. The keyword "Proxmox" confirms the login page actually renders. TLS verification is disabled for these monitors because the nodes use self-signed certificates.

n8n has only a public monitor because the n8n container does not publish its port to the LXC host. The port is only reachable from inside n8n's own Docker network. The public URL is the only path.

## Labels

Three labels organise the monitors and drive the status page grouping:

| Label | Colour | Used for |
|-------|--------|----------|
| Infrastructure | Red | Hypervisors, storage, anything at the foundation |
| Network | Blue | Gateway, switch, access point, DNS |
| Apps | Green | Application-level services (n8n, ntfy, Uptime Kuma itself) |

Labels double as filters on the dashboard. With ten monitors it is already useful; with thirty monitors it becomes necessary.

## Notifications

All alerts route to self-hosted ntfy. The Uptime Kuma notification is configured with:

- **Type:** ntfy
- **Server URL:** `http://ntfy:80` (internal Docker network, not the public URL)
- **Topic:** `homelab-alerts`
- **Authentication:** username and password

Using the internal Docker network for the notification endpoint avoids a round trip through the Cloudflare tunnel every time an alert fires. It is faster and it keeps working even if the tunnel is temporarily down, which is exactly when you want alerts to go out.

Custom notification templates format the push on iOS to be readable at a glance:

- **Title:** `{{ name }} is {{ status }}`
- **Message:** `{{ hostnameOrURL }} - {{ msg }}`

This produces alerts like `Proxmox Node 1 is DOWN` with body `10.0.10.x:8006 - Connection timeout`. Everything you need in the lock screen, nothing you need to unlock the phone for.

See [03-ntfy.md](03-ntfy.md) for the ntfy setup, including the user and token that Uptime Kuma uses to publish.

## Status pages

One public status page lives at `https://uptime.example.com/status/public`. It shows only the services that are meant to be public:

- n8n (via its public URL)
- ntfy (the public endpoint)
- Uptime Kuma itself (the public endpoint)

The internal infrastructure (Proxmox nodes, UniFi hardware, DNS, local container checks) is deliberately hidden from the public page. A status page that lists internal IPs or hardware brands is a free OSINT sheet for anyone poking around. The public version stays focused on services an outside visitor actually cares about.

There is no separate password-protected status page. Uptime Kuma 2.x removed the status page password feature that existed in v1.x. For internal viewing, the admin panel at `https://uptime.example.com` shows everything and is protected by login and 2FA.

## Security

The admin panel is exposed through the public tunnel but protected in layers:

- **2FA (TOTP)** is enabled on the admin account
- **Strong password** on the single user
- **API key** is scoped to the `/metrics` endpoint only and has a three-month expiry
- **Trust Proxy** is set to `Yes` because Uptime Kuma sits behind the Cloudflare tunnel and needs to honor the forwarded headers for correct client IP logging
- **Base URL** is pinned to the public hostname so webhooks and redirects use the tunnel URL instead of the local IP

The built-in cloudflared tunnel support inside Uptime Kuma is intentionally unused. Running a standalone cloudflared container alongside Uptime Kuma is cleaner: one tunnel configuration routes both Uptime Kuma and ntfy, and the tunnel lifecycle is managed by Docker instead of the Uptime Kuma process.

## Network requirements

Uptime Kuma sits on the Apps VLAN and needs to reach targets on multiple other zones. Three firewall rules make this possible:

1. **Apps to Servers, TCP 8006** on the network firewall, for the Proxmox web UI keyword checks
2. **Apps to Mgmt, ICMP echo request** on the network firewall, for the ping probes against the switch and access point
3. **Apps VLAN source allowed** in the Proxmox host firewall on TCP 8006 and ICMP, so the host-level firewall does not drop the probes before they reach the web UI

Without any of these, the probes time out silently. The zone-based firewall blocks unmatched traffic by default, and the host-level firewall adds a second layer that needs to agree.

## Access

The dashboard is available at `https://uptime.example.com`, protected by username, password and TOTP. Local access through `http://<container-ip>:3001` still works from the Management VLAN for emergencies when DNS or the tunnel is broken.

The public status page at `https://uptime.example.com/status/public` needs no authentication.

## Backup

The container is included in the weekly cluster backup job (Sunday 03:00, zstd, four-week retention). This captures the full container filesystem, which includes the three Docker volumes (`uptime-kuma`, `ntfy-cache`, `ntfy-etc`) with all monitor configuration, the ntfy user database, and the server config files.

For extra safety, the Uptime Kuma monitor configuration can be exported as JSON from the admin UI (Settings → Backup → Export). Keep a copy outside the homelab to cover the scenario where both nodes lose their disks at the same time.
