# Design Decisions

🇬🇧 English | 🇳🇱 [Nederlands](decisions.nl.md)

This document records the non-obvious choices made during the build. Each entry explains what was decided, why, and what alternatives were considered. If I rebuild this setup a year from now, these notes should prevent me from making the same mistakes or second-guessing choices that already proved correct.

---

## Custom zones over global deny-all

**Date:** 2026-04-07
**Area:** Firewall

UniFi offers two paths to deny-by-default firewalling. The first is flipping the global Default Security Posture from "Allow All" to "Block All." The second is moving every network into a custom zone, which makes inter-zone traffic deny-by-default automatically.

I chose custom zones. The global toggle is a single switch that blocks everything at once. One missed allow rule and you lock yourself out of the gateway. Custom zones achieve the same result but let you build policies per zone pair. The mental model is cleaner: each zone pair is either explicitly allowed or silently dropped.

**Trade-off:** more initial setup (13 custom policies instead of one toggle), but safer rollout and easier to reason about later.

## Apps VLAN separated from Servers

**Date:** 2026-04-07
**Area:** Segmentation

Proxmox hypervisors sit on the Servers VLAN. Application workloads (workflow automation, monitoring) sit on a separate Apps VLAN. The hypervisors can reach the Apps subnet for container management, but not the other way around.

The reason is blast radius. If an application container gets compromised, the attacker lands in the Apps zone. From there, the zone firewall blocks lateral movement to the hypervisor management plane. Without this separation, a compromised container on the same VLAN as Proxmox could attempt API calls against the hypervisor directly.

## Tagged VLAN management for Proxmox

**Date:** 2026-04-07
**Area:** Proxmox networking

Two options existed for putting Proxmox on its own VLAN. The first was changing the switch port to a native (untagged) VLAN, which requires no changes on the Proxmox side. The second was keeping the trunk port and creating a tagged sub-interface (`vmbr0.10`) on the bridge.

I went with the tagged approach. It is consistent with how VMs and containers already get their VLAN tags, it keeps the switch port as a clean trunk, and it means the Proxmox host participates in the same VLAN-aware bridge as everything else. The untagged approach would have worked but creates an inconsistency: the host uses native VLAN while its workloads use tagged VLANs on the same bridge.

## VLAN numbering matches third octet

**Date:** 2026-04-06
**Area:** Segmentation

Every VLAN ID matches the third octet of its subnet. VLAN 10 uses `10.0.10.0/24`, VLAN 30 uses `10.0.30.0/24`, and so on. This removes one layer of mental translation when troubleshooting. If you see traffic from `10.0.20.x`, you know it is VLAN 20 without checking a table.

The original setup had inconsistent numbering (VLAN 133 on `10.0.10.0`, VLAN 5 on `10.0.5.0`). Renumbering required careful sequencing because subnets had to be freed before they could be reassigned. See [lessons-learned.md](lessons-learned.md) for the details.

## WireGuard with split and full tunnel profiles

**Date:** 2026-04-07
**Area:** Remote access

Two client profiles exist. The phone uses a full tunnel that routes all traffic through the homelab, useful on untrusted WiFi. The laptop uses a split tunnel that only routes the homelab subnet through VPN, so regular browsing stays on the local connection.

WireGuard was chosen over the built-in Teleport feature. Teleport works but is vendor-locked, does not support split tunneling, and adds latency through relay servers. WireGuard is a direct peer-to-peer connection, faster, and portable to any client platform. Teleport stays enabled as a fallback for situations where UDP 51820 is blocked.

VPN clients can reach Management, Servers and Apps zones. Access to SOC, Lab and IoT is blocked. If VPN credentials leak, the attacker can reach admin interfaces but not the intentionally vulnerable lab machines or IoT devices.

## Dynamic DNS through gateway API

**Date:** 2026-04-07
**Area:** Remote access

The ISP assigns a dynamic public IP. The VPN endpoint hostname points to this IP through dynamic DNS. Instead of running a separate DDNS client, the gateway updates the DNS record directly through the DNS provider API whenever the IP changes.

The API token is scoped to a single zone with only DNS edit permissions. If the token leaks, the worst case is someone pointing the VPN hostname elsewhere. They cannot modify other DNS records, access other API resources, or intercept traffic (WireGuard authenticates peers by public key, not by hostname).

## IPS in block mode from day one

**Date:** 2026-04-06
**Area:** Hardening

The IPS was running in notify-only mode. I switched it to notify-and-block with all signature categories at maximum sensitivity.

Running IPS in notify-only mode in a homelab makes little sense. There is no SOC team watching alerts around the clock, so notifications without automatic blocking just create a log nobody reads. In a production environment you would start with notify to avoid false positives disrupting business. In a homelab, a false positive blocking something is a learning opportunity, not a business risk.

## GeoIP blocking inbound only

**Date:** 2026-04-06
**Area:** Hardening

GeoIP rules block inbound traffic from Russia, China, North Korea and Iran. Outbound is not blocked.

Blocking outbound by country is brittle. CDNs serve content from unexpected regions, package mirrors might resolve to blocked countries, and legitimate services use infrastructure globally. The value of outbound GeoIP blocking is low compared to the troubleshooting cost when something silently breaks. Inbound blocking makes more sense because there is no reason for unsolicited connections from these regions to reach a homelab.

## Encrypted DNS with filtering

**Date:** 2026-04-06
**Area:** Hardening

DNS queries go through encrypted resolvers with built-in malware and phishing filtering. Two providers are configured for redundancy.

Plain DNS leaks every domain lookup to the ISP. Encrypted DNS with filtering adds two layers: privacy (ISP cannot see queries) and basic protection (known malicious domains are blocked at the resolver level). This is not a replacement for proper endpoint security, but it catches low-hanging fruit at the network level with zero maintenance.
