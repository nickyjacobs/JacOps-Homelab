# Cybersecurity hardening

🇬🇧 English | 🇳🇱 [Nederlands](05-cybersecurity-hardening.nl.md)

The previous documents describe the structural controls: [VLAN segmentation](02-vlan-segmentation.md), [zone-based firewall rules](03-zone-firewall.md) and the [WireGuard VPN](04-wireguard-vpn.md) for remote access. This document covers the defensive layers on top. Each layer is cheap on its own and pointless in isolation. Stacked together they raise the cost of a successful intrusion past what a typical opportunistic attacker is willing to spend.

## Threat model

Hardening without a threat model turns into cargo culting. The homelab defends against three categories:

1. **Opportunistic internet scans.** Mass scanners hitting the WAN, looking for exposed admin panels, default credentials and known CVEs.
2. **Compromised IoT or lab machines.** Devices on untrusted VLANs that get popped and try to pivot internally or beacon out to a C2.
3. **Credential theft on endpoints.** A stolen laptop or phished password that an attacker uses to dial in.

Nation-state adversaries and targeted APTs are explicitly out of scope. The controls below do not stop a motivated attacker with time and budget. They do stop the background noise of the internet and raise the bar for the middle tier.

## Intrusion prevention

UniFi ships with an IPS engine based on Suricata. It runs on the gateway and inspects traffic between zones and between zones and the internet.

| Setting | Value | Reason |
|---------|-------|--------|
| Mode | Detect and block | Blocking is the whole point |
| Rule categories | Critical, high, medium | Low-severity rules generate noise without value |
| Direction | WAN in, WAN out, internal | Catches inbound scans and outbound beacons |
| Suppression list | A handful of known-good rules | Prevents Smart TV traffic from flooding the log |

IPS is the single control that catches outbound activity from the IoT and Lab zones. The firewall rules in [03](03-zone-firewall.md) say IoT can reach the internet, but they say nothing about what IoT is saying. IPS fills that gap.

The suppression list grows as false positives show up. Every suppression gets a comment explaining which device triggered it and why it is safe to ignore. Blind suppression is how you end up with an IPS that detects nothing.

## GeoIP filtering

Most inbound scan traffic originates from a small number of source countries. Blocking those regions at the WAN is free throughput back and a massive reduction in log noise.

The homelab blocks inbound traffic from every country except the Netherlands and a short allow list of neighbours. Outbound GeoIP is off. Users need to reach services hosted anywhere in the world, and blocking outbound destinations by country breaks more than it fixes.

The WireGuard endpoint is the one exception that matters. When travelling outside the allow list, the client cannot reach `vpn.example.com`. Two options handle this:

1. Temporarily add the current country to the allow list from a trusted device before travel.
2. Accept the limitation and plan remote work around it.

Option one is the practical choice. A short note in the travel checklist reminds me to update the allow list before boarding.

## Encrypted DNS

Plaintext DNS leaks every hostname a device looks up. That leak is visible to the ISP and to anything in between. Encrypted DNS removes the ISP from the picture and makes passive monitoring significantly harder.

The gateway runs DNS over HTTPS to an upstream resolver. All VLANs use the gateway as their DNS server. Clients that try to bypass the gateway and talk directly to `8.8.8.8` or `1.1.1.1` get redirected to the local resolver by a NAT rule. The outbound DoH request is the only DNS traffic that actually leaves the network.

A single upstream resolver is a single point of observation. The homelab rotates between two providers with different logging policies. Neither is perfect, but the combination is better than either alone.

## WiFi hardening

Wireless is the easiest way into a home network. The hardening here focuses on making the wireless trust model explicit.

- **Separate SSIDs per trust level.** One SSID for trusted devices, one for IoT, one for guests. No shared PSK across trust levels.
- **WPA3 where supported, WPA2 as fallback.** Mixed mode only on the IoT SSID because smart bulbs refuse to join WPA3.
- **PMF (802.11w) required on WPA3 SSIDs.** Blocks deauth and disassoc spoofing.
- **Client isolation on guest and IoT SSIDs.** Devices cannot talk to each other, only to the gateway.
- **Hidden SSIDs are off.** Hiding the SSID adds no security and breaks auto-join on some clients.
- **Rogue AP detection on.** The controller flags unknown APs broadcasting nearby.

The WPA2 fallback on the IoT SSID is a known weakness. Smart home devices have lifecycles measured in years, and half of them will never get a firmware update that adds WPA3 support. The IoT VLAN in [02](02-vlan-segmentation.md) exists specifically to contain that weakness.

## Honeypots

A honeypot is a service that should never receive traffic. Any connection attempt is automatically suspicious, which makes honeypots an extremely high-signal detection source.

The homelab runs a small set of honeypots in the Lab zone:

- **SSH honeypot.** Cowrie, logging credential attempts and post-auth commands.
- **HTTP honeypot.** A fake login page that records credentials and user agents.
- **SMB honeypot.** Listens for Windows-style lateral movement attempts.

None of these services are mapped to the WAN. They only exist to catch internal lateral movement from a compromised device. If the SMB honeypot ever logs a connection, it means something on the network is scanning for file shares, and that is a reason to take it offline and investigate.

Honeypot logs ship to the SOC zone, where the blue team tooling picks them up.

## Logging and retention

None of the controls above matter without logs. The gateway, the IPS, the wireless controller and the honeypots all ship logs to a central collector in the SOC zone. Retention is 30 days on fast storage and 90 days on archive.

Thirty days is long enough to investigate most incidents that are discovered late. Ninety days on archive is a compromise between storage cost and the reality that some intrusions take months to surface.

## What this does not cover

The controls in this document harden the network layer. They do not replace:

- Endpoint protection on the devices themselves
- Patch management on Proxmox, containers and applications
- Backup and recovery for the workloads in the Servers zone
- Regular review of the firewall and IPS rules

Those belong in separate documents under `proxmox/` and `services/` and are listed in the repository README.

## What comes next

This is the last document in the `network/` series. The next layer up is the Proxmox cluster itself, covered in [proxmox/](../proxmox/). From there, individual services live in [services/](../services/), and the overarching decisions and lessons are in [docs/](../docs/).
