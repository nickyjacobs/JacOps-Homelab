# Zone-based firewall

🇬🇧 English | 🇳🇱 [Nederlands](03-zone-firewall.nl.md)

This document describes how the VLANs from [02-vlan-segmentation.md](02-vlan-segmentation.md) are grouped into zones, and which traffic is allowed to cross zone boundaries.

## Why zones instead of per-VLAN rules

Rule-based firewalls become unreadable fast. Ten VLANs means up to a hundred directional rule pairs, and every new VLAN multiplies the work. Zones flip the model around. You group VLANs by trust level and purpose, then write rules between zones instead of between VLANs. Adding a new VLAN means dropping it in the right zone and inheriting the existing rules.

Modern UniFi supports zone-based firewalling natively. Custom zones are deny-all by default between each other, which is exactly what I want.

## Zone layout

| Zone | Contains | Trust level |
|------|----------|-------------|
| Mgmt | Management VLAN | High, only my admin device |
| Servers | Servers VLAN | High, hypervisor management |
| Apps | Apps VLAN | Medium, application workloads |
| SOC | Blue Team VLAN | High, defensive tooling |
| Lab | Lab VLAN | Untrusted by design |
| IoT | IoT VLAN | Untrusted, long-lived devices |
| Hotspot (built-in) | Guest VLAN | Untrusted, visitors |
| External (built-in) | Internet | Untrusted |
| VPN (built-in) | Remote clients | High when authenticated |

Every custom zone is deny-all to every other custom zone by default. That is the whole point of splitting them out of the default `Internal` zone.

## Allow rules

The rules below open only what a service actually needs. Every rule has a reason column so that a future me can decide whether the rule is still load bearing.

### From Mgmt

| To | Protocol and port | Reason |
|----|-------------------|--------|
| Servers | TCP 8006 | Proxmox web UI |
| Servers | TCP 22, ICMP | SSH and ping for troubleshooting |
| Apps | Any | Full access for admin work |
| SOC | Any | Full access for defensive tooling |
| Lab | Any | Full access to manage lab machines |
| IoT | Any | Smart home control from the admin device |
| External | Any | Regular internet access |

### From Servers

| To | Protocol and port | Reason |
|----|-------------------|--------|
| Apps | Any | Container management talking to app containers |
| External | Any | Package updates, image pulls, NTP |

### From Apps

| To | Protocol and port | Reason |
|----|-------------------|--------|
| External | Any | Outbound webhooks and API calls |

### From SOC

| To | Protocol and port | Reason |
|----|-------------------|--------|
| External | Any | Threat feeds, updates |

### From Lab

| To | Protocol and port | Reason |
|----|-------------------|--------|
| External | TCP 443 | HTTPS for package downloads and browsing |
| External | UDP 53 | DNS |

Notice what Lab does **not** get: no ICMP to the outside, no arbitrary outbound ports, no access to any internal zone. That is the whole point of the Lab zone.

### From IoT

| To | Protocol and port | Reason |
|----|-------------------|--------|
| External | Any | Cloud services that smart devices depend on |

### From VPN

| To | Protocol and port | Reason |
|----|-------------------|--------|
| Mgmt | Any | Admin work from remote |
| Servers | Any | Hypervisor management from remote |
| Apps | Any | App management from remote |
| External | Any | Full tunnel clients route all traffic out |

VPN clients get a deliberate subset. No access to SOC, Lab or IoT. If a VPN credential leaks, the blast radius stays limited to the zones an admin touches during normal work.

## What the rules explicitly do not do

**No rule from Lab to any internal zone.** Lab is a one-way street. Traffic initiated from a lab machine cannot reach Mgmt, Servers, Apps or SOC. Stateful return traffic from an admin session initiated from Mgmt is still allowed, because the built-in return-traffic rule handles that.

**No rule from IoT to any internal zone.** Same pattern. IoT devices talk to their vendor cloud, and that is all.

**No rule from Servers or Apps to Mgmt.** The Proxmox hosts and their workloads do not need to initiate connections back into the management network. If they did, I would investigate what is making them reach out before adding a rule.

## Testing the model

After applying the rules, a short test list confirms the model works.

- Admin device can open the Proxmox web UI: allowed.
- Admin device can open a random website: allowed.
- Lab machine can open a website over HTTPS: allowed.
- Lab machine can ping the Proxmox host: blocked.
- Lab machine can open the Proxmox web UI: blocked.
- IoT device can reach its cloud service: allowed.
- IoT device can reach the admin device directly: blocked.

The last two are the honest test of the model. If any of the `blocked` entries work, something is wrong with the zone assignments or the rule order.

## What comes next

With traffic between zones under control, the [WireGuard document](04-wireguard-vpn.md) adds a secure remote path into the high-trust zones without opening anything to the public internet.
