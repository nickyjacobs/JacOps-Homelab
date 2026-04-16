# Beszel

🇬🇧 English | 🇳🇱 [Nederlands](10-beszel.nl.md)

Beszel is the homelab's host metrics platform. Lightweight agents on every LXC container and both Proxmox nodes report CPU, RAM, disk, network and temperature data to a central hub. It runs as a Docker container in CT 151 alongside Uptime Kuma, ntfy and cloudflared, accessible internally via `beszel.jacops.local`.

## Why Beszel

Uptime Kuma answers the question "is this service reachable?" but says nothing about resource usage on the hosts themselves. A container can pass its health check while the disk fills up or memory pressure causes swapping. Beszel fills that gap. Its agents use under 10 MB RAM each, the hub adds roughly 30 MB, and the total footprint across nine agents and one hub stays below 120 MB.

Beszel was chosen over Prometheus plus Grafana because the monitoring stack would add 500+ MB RAM for a result that does not improve the answer at this scale. When Wazuh arrives after the eJPT certification, Prometheus becomes worthwhile as a single pane over multiple data sources. Until then, Beszel covers host metrics and Uptime Kuma covers reachability. The two do not overlap.

## Architecture

```
Agents (SSH mode, VLAN 40)          Agents (WebSocket mode, VLAN 10)
CT 151, 152, 160, 161,             PVE Node 1, PVE Node 2
163, 164, 165                       │
│                                   │ ws connect to hub
│ hub connects via SSH              │ http://<ct-ip>:8090
▼                                   ▼
┌──────────────────────────────────────────────────┐
│  LXC Container (CT 151)                          │
│  Docker Compose (/opt/monitoring/)               │
│  ├─ Uptime Kuma                                  │
│  ├─ ntfy                                         │
│  ├─ cloudflared                                  │
│  └─ Beszel hub (port 8090)                       │
└──────────────────────────────────────────────────┘
         │
         ▼
    Traefik (CT 165) ──► beszel.jacops.local
    ACME cert via step-ca
```

Nine agents connect to the hub through two different modes:

- **SSH mode** for the seven containers on VLAN 40 (CT 151, 152, 160, 161, 163, 164, 165). The hub initiates the connection to each agent over SSH, using a dedicated key pair per system
- **WebSocket mode** for the two Proxmox nodes on VLAN 10. The agents initiate outbound connections to the hub. This avoids opening SSH from the Apps VLAN to the Servers VLAN, which would violate the zone-based firewall architecture

The hub stores metrics in an embedded PocketBase database. No external database needed.

No public tunnel, no Cloudflare. The service is only reachable via the local network or WireGuard.

## Container specs

The hub shares CT 151 with Uptime Kuma, ntfy and cloudflared.

| Setting | Value |
|---------|-------|
| VMID | 151 |
| Type | LXC (unprivileged) |
| Node | Node 1 |
| OS | Debian 13 (Trixie) |
| CPU | 1 core |
| RAM | 512 MB |
| Swap | 256 MB |
| Disk | 8 GB on NVMe thin pool (`local-lvm`) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container configuration |
| Boot | `onboot: 1` |
| Features | `nesting=1` (required for Docker) |
| Tags | `docker`, `homelab`, `monitoring` |

## Docker Compose

The hub is added to the existing monitoring stack at `/opt/monitoring/docker-compose.yml`. The image is pinned on tag plus SHA256 digest.

```yaml
beszel:
  image: henrygd/beszel:0.18.7@sha256:<digest>
  container_name: beszel
  restart: unless-stopped
  ports:
    - "8090:8090"
  volumes:
    - ./beszel-data:/beszel_data
```

Port 8090 serves both the web UI and the API. The data directory holds the PocketBase database, SSH keys and alert configuration.

## Agent installation

All agents run Beszel v0.18.7 as a Go binary, installed via the official `get.beszel.dev` script.

| Setting | Value |
|---------|-------|
| Binary | `/usr/local/bin/beszel-agent` |
| Version | v0.18.7 |
| User | `beszel` (dedicated service user) |
| Groups | `disk` (all agents), `docker` (Docker-based CTs only) |
| Port | 45876 |
| Service | `beszel-agent.service` |

The `disk` group membership allows the agent to read disk I/O stats. On containers running Docker (CT 151, 152, 163), the `beszel` user also gets `docker` group membership so the agent can report container-level metrics.

### systemd hardening

The agent's systemd unit includes sandbox directives:

| Directive | Effect |
|-----------|--------|
| `User=beszel` | Dedicated service user, no root |
| `NoNewPrivileges=true` | Prevents privilege escalation via setuid |
| `ProtectSystem=strict` | Filesystem read-only except explicitly allowed paths |
| `ProtectHome=true` | No access to /home |
| `PrivateTmp=true` | Own /tmp namespace |
| `PrivateDevices=true` | No hardware device access |

### Agent deployment overview

| System | VMID | VLAN | Connection mode | Docker group |
|--------|------|------|-----------------|--------------|
| Monitoring stack | CT 151 | 40 | SSH | Yes |
| Vaultwarden | CT 152 | 40 | SSH | Yes |
| Forgejo | CT 160 | 40 | SSH | No |
| Forgejo Runner | CT 161 | 40 | SSH | No |
| Miniflux | CT 163 | 40 | SSH | Yes |
| step-ca | CT 164 | 40 | SSH | No |
| Traefik | CT 165 | 40 | SSH | No |
| PVE Node 1 | - | 10 | WebSocket | No |
| PVE Node 2 | - | 10 | WebSocket | No |

## Connection modes

### SSH mode (VLAN 40 containers)

The hub connects to each agent on port 45876 via SSH. During system registration, the hub generates an SSH key pair per system. The public key is added to the agent configuration. No separate SSH server is needed on the agent side; the Beszel agent handles the SSH transport itself.

This mode works well for containers on the same VLAN as the hub, because the hub can reach all agents directly.

### WebSocket mode (VLAN 10 nodes)

The two Proxmox nodes sit on VLAN 10 (Servers). The zone-based firewall blocks traffic from VLAN 40 (Apps) to VLAN 10 by default, which means the hub cannot initiate SSH connections to the nodes.

WebSocket mode flips the direction. Each agent initiates an outbound HTTP connection to the hub at `http://<ct-ip>:8090`. The agent authenticates with a per-system token generated during registration. The connection upgrades to WebSocket and stays open for metrics transport.

This approach requires two firewall exceptions: a UniFi zone policy that allows only the two PVE nodes to reach CT 151 on port 8090, and iptables rules on CT 151 that accept traffic from the node IPs. Both are scoped to the minimum: two source devices, one destination IP, one port.

## Traefik route

The route configuration lives at `/etc/traefik/dynamic/svc-beszel.yml` on CT 165:

```yaml
http:
  routers:
    beszel:
      rule: "Host(`beszel.jacops.local`)"
      entryPoints:
        - websecure
      service: beszel
      tls:
        certResolver: step-ca
  services:
    beszel:
      loadBalancer:
        servers:
          - url: "http://<ct-ip>:8090"
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 5s
```

TLS termination happens at Traefik. The certificate is EC P-256 with 72-hour lifetime, auto-renewed via the step-ca ACME provisioner using tls-alpn-01. Security headers (HSTS, nosniff, frameDeny) are applied by Traefik's global middleware.

The DNS record for `beszel.jacops.local` points to the Traefik IP via a UniFi DNS policy.

## Backend firewall

Port 8090 on CT 151 serves two purposes: the web UI (via Traefik) and the WebSocket endpoint (from PVE nodes). The iptables rules in the `DOCKER-USER` chain reflect both:

```
iptables -I DOCKER-USER -p tcp --dport 8090 -s <node1-ip> -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 8090 -s <node2-ip> -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 8090 ! -s <traefik-ip> -j DROP
```

The rules are evaluated in order. Traffic from the two PVE nodes is accepted first. Then all remaining traffic that does not come from the Traefik IP is dropped. This means only three source IPs can reach port 8090: the two PVE nodes (for WebSocket agent connections) and Traefik (for the web UI).

`iptables-persistent` is installed to preserve the rules across reboots.

### UniFi zone firewall policy

A device-based policy allows traffic from the Servers zone (VLAN 10) to the Apps zone (VLAN 40), scoped to only the two PVE nodes as source, CT 151's IP as destination, and TCP port 8090. All other cross-VLAN traffic from Servers to Apps remains blocked.

## Alerting

Alerts go to ntfy via the Shoutrrr integration. Because both Beszel and ntfy run as Docker containers in the same Compose stack, the alert URL uses the internal Docker network:

```
ntfy://:tk_<token>@ntfy:80/beszel-alerts?scheme=http
```

The ntfy publish token is stored in Vaultwarden as `homelab/beszel-ntfy-token`.

Four alert rules apply to all nine systems:

| Metric | Threshold | Duration |
|--------|-----------|----------|
| CPU | 80% | 10 minutes |
| Memory | 80% | 10 minutes |
| Disk | 80% | 10 minutes |
| Status | Down | Immediate |

The ten-minute duration window prevents single spikes from triggering alerts. Status alerts fire immediately because a down agent usually indicates a real problem.

## Security

### Manual per-system registration

Each agent is registered individually in the hub UI. The hub generates a unique SSH key pair (for SSH mode) or a unique token (for WebSocket mode) per system. There is no shared secret or universal registration token.

The alternative was Beszel's universal token feature, which allows any agent to auto-register by presenting a shared secret. That was rejected because a leaked universal token would let an attacker register rogue agents, polluting metrics and potentially gaining visibility into the hub's network topology.

### Cross-VLAN access

The firewall rule for WebSocket mode is scoped to the minimum viable surface:

- **Source**: two specific device IPs (PVE Node 1, PVE Node 2)
- **Destination**: one IP (CT 151), one port (8090), one protocol (TCP)
- **Direction**: Servers to Apps only

No broad VLAN-to-VLAN allow. No wildcard port ranges.

### Credentials

| Secret | Vaultwarden path |
|--------|------------------|
| Beszel admin account | `homelab/beszel-admin` |
| ntfy publish token | `homelab/beszel-ntfy-token` |

## Metrics collected

| Category | Metrics |
|----------|---------|
| CPU | Usage percentage, load average |
| Memory | Usage, available, swap |
| Disk | Usage, I/O read/write |
| Network | Bandwidth in/out |
| System | Uptime, temperature |
| Services | Docker container count and status (Docker CTs only) |

## Monitoring

Uptime Kuma monitors Beszel via an HTTPS check on `https://beszel.jacops.local` with TLS verification enabled. This confirms both that Traefik serves a valid step-ca certificate and that the Beszel hub responds.

## Backup

CT 151 is included in the weekly PBS backup job (Sunday 03:00, four weeks retention). This captures the full container filesystem including Docker volumes with the PocketBase database, SSH key pairs, agent configuration and alert rules.

## Related

- [Roadmap](../docs/roadmap.md): Beszel is the eighth foundation service in Phase 1
- [Decisions](../docs/decisions.md): "Prometheus postponed" covers why Beszel fills the gap
- [Uptime Kuma](02-uptime-kuma.md): reachability monitoring, complementary to Beszel's host metrics
- [ntfy](03-ntfy.md): push notifications for Beszel alerts
- [Traefik](09-traefik.md): TLS termination and routing
- [step-ca](08-step-ca.md): certificate authority for the ACME cert
