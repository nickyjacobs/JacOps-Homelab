# jacops-homelab

🇬🇧 [English](README.md) | 🇳🇱 Nederlands

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-in%20progress-orange)
![Made with](https://img.shields.io/badge/built%20with-Proxmox%20%7C%20UniFi%20%7C%20WireGuard-blueviolet)

> Security-first homelab van JacOps. Portfolio en runbook in één.

## Over deze repo

Deze repository beschrijft het ontwerp en de bouw van een gesegmenteerd homelab-netwerk. Het dient twee doelen. Eerst als portfoliostuk dat laat zien hoe ik netwerksecurity, segmentatie en remote access aanpak. Daarnaast als persoonlijk runbook zodat ik dezelfde opzet vanaf nul kan herbouwen wanneer dat nodig is.

Het homelab draait op een Proxmox cluster achter een UniFi Cloud Gateway, met zone-based firewalling, VLAN segmentatie en WireGuard voor remote access. Elke ontwerpkeuze staat gedocumenteerd inclusief de redenering erachter.

Deze eerste release dekt de netwerklaag volledig. Documentatie van het Proxmox cluster en de self-hosted services volgt in latere iteraties.

## Navigatie

| Sectie | Beschrijving |
|--------|--------------|
| [network/](network/) | Architectuur, VLANs, zone-based firewall, WireGuard VPN, hardening |

## Tech stack

- **Gateway:** UniFi Cloud Gateway Ultra
- **Switching:** UniFi USW-Lite-8-PoE
- **WiFi:** UniFi U6 Pro
- **Hypervisor:** Proxmox VE 9.x cluster (2 nodes)
- **VPN:** WireGuard met dynamic DNS
- **Monitoring en security:** gepland (Wazuh, Uptime Kuma)

## Status

| Onderdeel | Staat |
|-----------|-------|
| Netwerkarchitectuur gedocumenteerd | Klaar |
| VLAN-segmentatie gedocumenteerd | Klaar |
| Zone-based firewall gedocumenteerd | Klaar |
| WireGuard remote access gedocumenteerd | Klaar |
| Cybersecurity hardening gedocumenteerd | Klaar |
| Proxmox cluster documentatie | Gepland |
| Self-hosted services documentatie | Gepland |

## Over JacOps

JacOps is het freelance merk van [Nicky Jacobs](https://www.linkedin.com/in/N-O-Jacobs), SOC analyst en security engineer uit Nederland. Focusgebieden zijn detection engineering, netwerksecurity en security automation.

## Licentie

[MIT](LICENSE)
