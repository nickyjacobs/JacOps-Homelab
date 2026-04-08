# VLAN segmentation

🇬🇧 English | 🇳🇱 [Nederlands](02-vlan-segmentation.nl.md)

This document turns the logical layers from [01-architecture.md](01-architecture.md) into real VLANs, subnets and switchport profiles.

## Naming and numbering rules

Two rules keep the VLAN layout readable a year from now.

**The third octet of the subnet matches the VLAN ID.** If you see `10.0.20.0/24`, you know it runs on VLAN 20 without looking it up. The rule breaks down once you go past 255, but for a home network that is fine.

**Names describe the role, not the technology.** `Servers` is better than `Proxmox_VLAN`. If I replace Proxmox with something else next year, I do not want to rename the VLAN.

## Layout

| VLAN ID | Name | Subnet | Purpose |
|---------|------|--------|---------|
| 1 | Management | 10.0.1.0/24 | Gateway, switch, access point, admin device |
| 10 | Servers | 10.0.10.0/24 | Proxmox hypervisor management interfaces |
| 20 | Blue Team | 10.0.20.0/24 | Defensive tooling (Wazuh, MISP, DFIR) |
| 30 | Lab | 10.0.30.0/24 | Offensive practice, vulnerable targets |
| 40 | Apps | 10.0.40.0/24 | Application workloads (automation, dashboards) |
| 50 | Guest | 10.0.50.0/24 | Visitors, isolated from everything |
| 100 | IoT | 10.0.100.0/24 | Smart home devices, untrusted by default |

The Management VLAN stays on the default VLAN 1 on purpose. Some UniFi features assume management traffic runs untagged, and fighting that gives more downside than upside.

## Why Servers and Apps are split

The hypervisors and the application workloads run on different VLANs even though both are trusted infrastructure. The reason is blast radius.

If an app gets popped (through an exposed webhook, a vulnerable dependency, a misconfigured reverse proxy), the attacker should not have direct network access to the Proxmox API on the host that runs the container. Separating Apps from Servers means compromise of an app does not equal compromise of the platform.

The cost is a handful of extra firewall rules to allow the management traffic that actually has to cross the line. That is a fair trade.

## Why Lab and IoT look similar but stay separate

Both VLANs are untrusted. Both can reach the internet. Neither can reach anything else without an explicit rule. They still get their own VLAN for two reasons.

First, they have different content. Lab holds short-lived machines that I actively try to break. IoT holds long-lived devices that I want to keep working. Mixing them in one VLAN means every time I snapshot or reset a lab VM, I risk touching a device that my partner uses.

Second, they have different remote access rules. Lab is never reachable over the VPN. IoT is reachable from the management device because I want to control smart home devices from my phone. Putting them in the same VLAN would force one of those rules to bend.

## Switchport profiles

Three profiles cover every port on the switch.

**Management access.** Untagged Management, no tagged VLANs. Used for the admin device and anything that does not need to see other networks.

**IoT access.** Untagged IoT, no tagged VLANs. Used for hardwired smart home devices.

**Trunk.** Untagged Management, every other VLAN tagged. Used for the Proxmox nodes and the access point. This is where the VLAN-aware bridge on the hypervisor can pick any VLAN per VM.

A fourth profile exists on paper for Lab-only ports, but in practice every lab machine is virtual and lives on the Proxmox trunk.

## DHCP and DNS

Every VLAN runs its own DHCP scope from the gateway. Ranges are sized so that the first 20 addresses stay reserved for static assignments (infrastructure, honeypots, printers). Everything above uses dynamic leases.

DNS is handled by the gateway, which forwards to an encrypted upstream. The [hardening document](05-cybersecurity-hardening.md) covers that part.

## WiFi mapping

The access point broadcasts three SSIDs. Each SSID maps to a single VLAN to keep things predictable.

| SSID | VLAN | Security |
|------|------|----------|
| M | Management | WPA2/WPA3 mixed, protected management frames |
| IoT | IoT | WPA2 only (some devices do not support WPA3), 2.4 GHz only |
| Guest | Guest | WPA2/WPA3 mixed, client isolation on |

The Lab VLAN has no WiFi SSID on purpose. Lab traffic is wired only, which makes it harder to accidentally land a phone or laptop in the wrong network.

## What comes next

With the VLAN layout in place, the [zone firewall document](03-zone-firewall.md) groups these VLANs into zones and lists the allow rules that let the zones talk to each other.
