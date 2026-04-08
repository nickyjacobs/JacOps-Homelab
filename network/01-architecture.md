# Architecture

🇬🇧 English | 🇳🇱 [Nederlands](01-architecture.nl.md)

This document describes the physical and logical foundation of the homelab. Everything in the other network docs builds on the concepts defined here.

## Goals

The homelab has to meet four goals at the same time.

1. **Learn and practice.** It doubles as a lab for offensive and defensive security work, so traffic from vulnerable machines has to stay contained.
2. **Run real services.** Workflow automation, monitoring and a handful of self-hosted tools run here and need to stay reachable.
3. **Be reproducible.** I should be able to tear it down and rebuild it from documentation without guesswork.
4. **Fail safely.** A compromised IoT device or lab VM must not reach anything that matters.

These goals drive every design choice below.

## Hardware

| Role | Device | Notes |
|------|--------|-------|
| Gateway and firewall | UniFi Cloud Gateway Ultra | Routing, zone-based firewall, IPS, VPN |
| Switch | UniFi USW-Lite-8-PoE | 8 ports, PoE for the AP |
| Access point | UniFi U6 Pro | WiFi 6, wired backhaul |
| Hypervisor node 1 | Proxmox VE 9.x, 6 core, 16 GB RAM | Runs most workloads |
| Hypervisor node 2 | Proxmox VE 9.x, 4 core, 16 GB RAM | Cluster partner, Windows lab |
| Uplink | Consumer fiber, PPPoE, dynamic public IP | DDNS covers the dynamic part |

The cluster has two nodes. That is enough to practice cluster concepts (quorum, migration, corosync) without the cost of a third machine. For services that need to stay online during node maintenance I document manual failover instead of pretending to have real HA.

## Physical topology

![Homelab network topology](diagrams/topology.svg)

Both Proxmox nodes connect as trunk ports. The bridge on each hypervisor is VLAN aware, so any VLAN can land on any VM or container without touching switch configuration.

## Logical layers

The network is split into four logical layers, each with its own purpose and trust level.

**Management.** Infrastructure itself. Gateway, switch, access point and my own admin device. Nothing else touches this.

**Servers.** The Proxmox hypervisors and their management interfaces. Treated as infrastructure, not as application workloads.

**Apps.** Application workloads that need to stay reachable from the rest of the network and, selectively, from the internet. Separated from the hypervisors so that compromise of an app does not equal compromise of the platform.

**Lab and IoT.** Untrusted by design. Lab is for offensive security practice and intentionally vulnerable targets. IoT holds smart home devices that I cannot fully trust. Both can reach the internet. Neither can reach anything else without an explicit rule.

The concrete VLAN numbering, subnets and DHCP layout live in [02-vlan-segmentation.md](02-vlan-segmentation.md).

## Design principles

Four principles shape the rest of the documentation.

**Segment by purpose, not by convenience.** Putting workloads in the same VLAN because it saves a click costs you isolation later. Every workload gets the VLAN that matches its trust level, even if that means more VLANs to maintain.

**Deny by default.** Every custom zone starts as deny-all. Allow rules open only the traffic that a service actually needs, with a short comment explaining why. If nobody remembers why a rule exists, it gets removed.

**Least privilege for remote access.** VPN users do not get the full network. They get the subset they need for the task at hand. Lab and IoT stay out of reach even when I am on the VPN.

**Document the reasoning, not just the result.** A config snippet without context is useless six months later. Every decision has a short paragraph explaining the trade-off.

## What you will find in the other docs

- [02-vlan-segmentation.md](02-vlan-segmentation.md) turns the logical layers above into actual VLANs, subnets and switchport profiles.
- [03-zone-firewall.md](03-zone-firewall.md) builds the zone model on top of the VLANs and lists every custom allow rule.
- [04-wireguard-vpn.md](04-wireguard-vpn.md) covers remote access, DDNS and the split versus full tunnel trade-off.
- [05-cybersecurity-hardening.md](05-cybersecurity-hardening.md) collects the hardening steps that do not fit in the other categories: IPS tuning, WiFi hardening, encrypted DNS, honeypots.

A visual version of the topology and the zone model lives in [diagrams/](diagrams/).
