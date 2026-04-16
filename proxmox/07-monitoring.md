# Monitoring

🇬🇧 English | 🇳🇱 [Nederlands](07-monitoring.nl.md)

This document describes how the Proxmox cluster is monitored, which layers are active today, which gaps remain, and the plan for closing them. It connects to [02-uptime-kuma.md](../services/02-uptime-kuma.md), which covers the Uptime Kuma monitoring stack itself in detail. This doc takes the Proxmox side: what you measure about the cluster, how you measure it, and what happens when something breaks.

## Starting point

Monitoring on this cluster today consists of two things: the Proxmox web UI itself, and an Uptime Kuma stack in CT 151 running reachability and keyword checks. That is a working minimum answering the question "is it running?". It does not yet answer the question "how is the host doing?", because no host metrics (CPU, RAM, disk I/O, network throughput) are collected or history-built anywhere.

Those two questions need different tools. Uptime Kuma excels at reachability and has a low barrier to entry. A metrics tool like Beszel or Prometheus excels at building host profiles and showing trends. The convention is to run both side by side, each for its strong suit, without overlap.

## Two layers

The monitoring stack is split into two layers that must not overlap.

**Layer 1: reachability.** Answers the question: is this service responding as it should? That is Uptime Kuma's job. An HTTP check against a Proxmox web UI, a TCP check against an SSH port, a keyword match in the response. Only binary outcome: up or down.

**Layer 2: host metrics.** Answers the question: how loaded is this host? That is Beszel's job, planned for Phase 1 of the roadmap (see [roadmap.md](../docs/roadmap.md)). CPU load, RAM usage, disk I/O, network throughput, history across days and weeks. Continuous values instead of binary ones.

The two deliberately do not overlap. A reachability probe cannot see that a host sits at 95 percent RAM, because the host still returns packets just fine. A host-metrics tool cannot see that a reverse proxy is serving a wrong certificate, because the certificate does not come out of the kernel stats. Both signals are needed, and they come from different places.

## What PVE provides natively

Proxmox has two built-in forms of monitoring that work without any external tooling.

**The web UI dashboards.** Per node the UI shows CPU, RAM, disk, and network in real-time graphs with a sliding time window up to one year. That is enough for ad-hoc checks on whether a node is under load, whether a disk is filling fast, or whether network traffic shows strange spikes. The data sits in `/var/lib/rrdcached/` and is maintained by `pvestatd`. No external tool is needed to see this, but it is also not alerting: you have to open the UI yourself.

**`pvestatd`** is the daemon that collects statistics every 10 seconds and writes them into the RRDs. Without this daemon the UI graphs show nothing. When graphs have issues, the first check is `systemctl status pvestatd`, not the UI itself.

On top of that, PVE has a mail notification system that can forward backup-job and replication events. That is wired up for the `weekly-backup` and `pbs-self-backup` jobs with `mailnotification failure` (see [03-backups.md](03-backups.md)). A successful backup is silent. A failed one produces a mail. That is the only path where PVE itself emits alerts. All other alerting runs outside PVE.

## What Uptime Kuma already covers

The Uptime Kuma stack in CT 151 currently monitors ten services across three labels (see [02-uptime-kuma.md](../services/02-uptime-kuma.md) for the full list). Three of them touch the Proxmox cluster directly:

| Monitor | Type | Target | Check |
|---------|------|--------|-------|
| Proxmox Node 1 | HTTPS keyword | Management IP, port 8006 | Keyword "Proxmox" in the response |
| Proxmox Node 2 | HTTPS keyword | Management IP, port 8006 | Keyword "Proxmox" in the response |
| UniFi Gateway | Ping | Gateway IP | ICMP |

The keyword match matters more than a plain TCP check. A TCP check would pass even if the web UI returned HTTP 500, which would let a broken PVE daemon slip through. The word "Proxmox" forces the login page to actually render.

Uptime Kuma does not yet have a monitor for PBS itself. That is a gap to close once the deploy has settled: an HTTPS check against `https://pbs-01.jacops.local:8007` with a keyword match on "Proxmox Backup Server". PBS fails silently for a long time without such a probe because its only output is a weekly backup job, which is visible for less than a day before data starts getting missed.

## What is missing today

Three classes of metrics are not collected, and that is a deliberate gap Phase 1 of the roadmap addresses.

**Host metrics with history.** The web UI shows real-time CPU/RAM/disk/network, but nobody watches them at fixed intervals or has alerting on them. Beszel solves this by running agents on both PVE nodes and on the foundation CTs, sending metrics to a central hub in CT 151. The hub keeps history and can trigger notifications against thresholds.

**Disk SMART data.** The NVMes on both nodes and the SATA disk on Node 1 report their own health through SMART: write amplification, bad sectors, temperature, reallocate counts. Nothing acts on that today. A plain `smartmontools` install on each node with a daily cron that runs `smartctl -a` and pushes anomalies through ntfy is a small addition that can flag disk death early. It is on the wishlist, not urgent, because NVMe and SATA failure modes in a homelab are typically loud.

**Log aggregation.** Every node has its own journald with default retention (now capped at 500 MB per [02-hardening.md](02-hardening.md)). There is no central place combining logs from both nodes plus all containers. Post-incident analysis means SSHing to several places. A central log store is a weight class above the rest of this monitoring plan and is deliberately deferred.

## Alerting path

All alerts land on the iPhone through ntfy. See [03-ntfy.md](../services/03-ntfy.md) for how the ntfy stack does this without letting alert content leave the homelab. The summary:

```
PVE node / service / Uptime Kuma ─── HTTP POST ───┐
                                                   │
                          ┌────────────────────────┘
                          ▼
                      ntfy (CT 151)
                          │
                          ├──► Web clients (realtime)
                          │
                          └──► Upstream poll ──► ntfy.sh ──► APNs ──► iPhone
```

Uptime Kuma posts alerts to ntfy over the internal Docker network (`http://ntfy:80`). PVE mail for backup failures does not go through ntfy because PVE itself has no native ntfy output. That is a second route landing in the admin's inbox. In practice that is fine for backup failures, because they demand a considered response rather than an instant push.

Beszel will later have its own alerting path, probably also through ntfy but with different templates so that "CPU above 90 percent for 15 minutes" is clearly distinguishable from a reachability alert.

## Operational checks

Alongside passive monitoring there are manual checks performed regularly that tooling will not replace because they are too low-level to automate.

**Daily on opening the MacBook.** Glance at the Uptime Kuma status page for any red icons. That is still a manual ritual and is on the to-do to become a status widget on the iPhone lock screen.

**Weekly after the Sunday night backup.** Verify that `pvesm list pbs-main` contains the expected new backups. The first time the automatic job runs, make it explicit: verify that the four jobs (weekly-backup, pbs-self-backup, GC, prune, verify) all ran in the right order.

**Monthly.** Verify `Data%` on the thin pool (`lvs` on both nodes, see [04-storage.md](04-storage.md)) and the fill level on the SATA disk. This is the last check before a pool fills, and is done by hand because once a month is enough.

**On every deploy.** The checklist from [06-vm-hygiene.md](06-vm-hygiene.md) technically also falls under monitoring: it is a post-change verification that the new guest is hooked into the cluster correctly.

## Beszel

Beszel v0.18.7 runs as a Docker container in CT 151, alongside Uptime Kuma and ntfy. The hub collects metrics from nine agents: seven foundation LXCs via SSH mode and two PVE nodes via WebSocket mode. The UI is internally reachable at `beszel.jacops.local` behind Traefik.

The agents measure CPU, RAM, disk, disk I/O, network, load average, temperature and active services. Alerts are set at 80% thresholds (10-minute window) for CPU, memory and disk, plus status alerts on failure. Notifications route through ntfy over the internal Docker network.

Full documentation in [services/10-beszel.md](../services/10-beszel.md).

## Result

The current monitoring state:

1. **Reachability is covered** by Uptime Kuma with ten monitors, three of them directly on PVE/UniFi and seven on applications and network hardware.
2. **Real-time host insight is manual** through the PVE web UI dashboards and `pvestatd`, without alerting.
3. **Backup alerting runs through mail** for failures, with an automatic weekly `verify-new` check on the PBS datastore.
4. **Push notifications reach the iPhone** through self-hosted ntfy, without alert content leaving the homelab.

The known gaps:

1. ~~No history for host metrics~~ Solved by Beszel, see above.
2. **No SMART monitoring** for the disks themselves, to be solved by a small smartmontools cron when that gets built.
3. **No central log aggregation**, deliberately deferred until after the foundation layer because the complexity is out of proportion with the value at this scale.

The three gaps are documented and each has a known fix. That is what monitoring is supposed to deliver: not perfect insight, but predictable coverage with explicit edges.
