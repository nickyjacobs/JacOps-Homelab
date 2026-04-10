# Uptime Kuma

🇬🇧 English | 🇳🇱 [Nederlands](02-uptime-kuma.nl.md)

Uptime Kuma monitors the availability of every service and infrastructure component in the homelab. It checks each target on a 60-second interval and provides a dashboard with uptime history.

## Why Uptime Kuma

The homelab needed a way to know when something goes down without manually checking each service. Uptime Kuma fills this role with minimal overhead. It uses around 100 MB of RAM, runs in a single Docker container, and supports HTTP, TCP, ping and keyword monitoring out of the box.

The alternative was a Prometheus and Grafana stack, which provides deeper metrics (CPU, memory, disk per service) but costs 800+ MB of RAM and requires exporters on every monitored host. For a homelab with five services, that level of detail is overkill. Uptime Kuma answers the one question that matters: is it up or not?

If the homelab grows past ten services or needs performance metrics, Prometheus can be added alongside Uptime Kuma rather than replacing it.

## Architecture

Uptime Kuma runs as a single Docker container inside an LXC container on the Apps VLAN. It stores its data in a Docker volume backed by SQLite.

```
LXC Container (CT 151)
┌──────────────────────────┐
│  Docker                  │
│  └─ Uptime Kuma (:3001)  │
│     └─ SQLite volume     │
└──────────────────────────┘
VLAN 40 (Apps)
```

## Container specs

| Setting | Value |
|---------|-------|
| VMID | 151 |
| Type | LXC (unprivileged, nesting enabled) |
| Node | Node 1 |
| CPU | 1 core |
| RAM | 512 MB |
| Disk | 8 GB (LVM-thin) |
| VLAN | 40 (Apps) |
| IP | Static, assigned via container config |
| Boot | `onboot: 1` |

## Monitors

| Name | Type | Target | Interval |
|------|------|--------|----------|
| n8n | HTTP | Public tunnel URL | 60s |
| Proxmox Node 1 | HTTPS keyword | Management IP, port 8006, keyword "Proxmox" | 60s |
| Proxmox Node 2 | HTTPS keyword | Management IP, port 8006, keyword "Proxmox" | 60s |
| UniFi Gateway | Ping | Gateway IP | 60s |
| Uptime Kuma | HTTP | Localhost, port 3001 | 60s |

The Proxmox monitors use keyword matching on the HTTPS response because a simple TCP port check would pass even if the web UI returned an error page. The keyword "Proxmox" confirms the login page actually renders.

TLS verification is disabled for the Proxmox monitors because the nodes use self-signed certificates.

## Network requirements

Uptime Kuma sits on the Apps VLAN and needs to reach targets on other VLANs. Two firewall rules make this possible:

1. **Network firewall:** Apps zone to Servers zone, TCP 8006 (monitoring policy)
2. **Proxmox firewall:** Apps VLAN source, TCP 8006 and ICMP allowed

Without these rules, the monitoring probes time out because both the zone-based firewall and the host-level firewall block Apps-to-Servers traffic by default.

## Access

The dashboard is available at `http://<container-ip>:3001` from the Management VLAN. There is no public URL. Monitoring data stays internal.

## Backup

The container is included in the weekly cluster backup job. The SQLite database and all monitor configuration are captured in the container filesystem snapshot.
