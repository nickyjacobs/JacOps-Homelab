# Network

🇬🇧 English | 🇳🇱 [Nederlands](README.nl.md)



Documentation of the network layer of the homelab. Built around three principles: segment by purpose, deny by default, verify what you allow.

## Contents

| Document | Topic |
|----------|-------|
| [01-architecture.md](01-architecture.md) | Hardware, physical topology, design principles |
| [02-vlan-segmentation.md](02-vlan-segmentation.md) | VLAN layout, subnets, DHCP ranges, switchport profiles |
| [03-zone-firewall.md](03-zone-firewall.md) | Zone-based firewall, custom zones, allow policies |
| [04-wireguard-vpn.md](04-wireguard-vpn.md) | WireGuard server, DDNS, split versus full tunnel |
| [05-cybersecurity-hardening.md](05-cybersecurity-hardening.md) | IPS, GeoIP, encrypted DNS, WiFi hardening |

## Diagrams

Editable source files and SVG exports live in [diagrams/](diagrams/).

### Topology

![Network topology](diagrams/topology.svg)

### Zone-based firewall matrix

![Zone matrix](diagrams/zone-matrix.svg)

### WireGuard routing: split vs full tunnel

![WireGuard routing](diagrams/wireguard-routing.svg)

Source files (`.excalidraw`) can be opened and edited on [excalidraw.com](https://excalidraw.com).
