# JacOps Homelab

🇬🇧 English | 🇳🇱 [Nederlands](README.nl.md)

![JacOps Homelab & Infrastructure](assets/hero.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-in%20progress-orange)
![Made with](https://img.shields.io/badge/built%20with-Proxmox%20%7C%20UniFi%20%7C%20WireGuard-blueviolet)

> Security-first homelab by JacOps. Portfolio and runbook in one.

## About

This repository documents the design and build of a segmented homelab network. It serves two purposes. First as a portfolio piece that shows how I approach network security, segmentation and remote access. Second as a personal runbook so I can rebuild the same setup from scratch when needed.

The homelab runs on a Proxmox cluster behind a UniFi Cloud Gateway, with zone-based firewalling, VLAN segmentation and WireGuard for remote access. Every design decision is documented with the reasoning behind it.

This first release covers the network layer end to end. Proxmox cluster and self-hosted services documentation follow in later iterations.

## Navigation

| Section | Description |
|---------|-------------|
| [network/](network/) | Architecture, VLANs, zone-based firewall, WireGuard VPN, hardening |
| [proxmox/](proxmox/) | Cluster setup, hardening, backups, storage, networking, VM hygiene, monitoring |
| [hardware/](hardware/) | Physical equipment: YubiKey hardware 2FA |
| [services/](services/) | Self-hosted services: n8n, Uptime Kuma, ntfy, Vaultwarden, Forgejo, Forgejo Runner, Miniflux, step-ca, Traefik |
| [docs/](docs/) | Design decisions and lessons learned |

## Tech stack

- **Gateway:** UniFi Cloud Gateway Ultra
- **Switching:** UniFi USW-Lite-8-PoE
- **WiFi:** UniFi U6 Pro
- **Hypervisor:** Proxmox VE 9.x cluster (2 nodes)
- **VPN:** WireGuard with dynamic DNS
- **Reverse proxy:** Traefik v3.6 central with automatic ACME certificates
- **PKI:** step-ca as internal ACME server with two-tier PKI
- **Monitoring:** Uptime Kuma with self-hosted ntfy for alerts
- **Backups:** Proxmox Backup Server with dedup and verify
- **Automation:** n8n
- **Security tooling:** Wazuh (planned after eJPT)

## Status

| Area | State |
|------|-------|
| Network architecture documented | Done |
| VLAN segmentation documented | Done |
| Zone-based firewall documented | Done |
| WireGuard remote access documented | Done |
| Cybersecurity hardening documented | Done |
| Design decisions documented | Done |
| Lessons learned documented | Done |
| Proxmox cluster setup documented | Done |
| Proxmox hardening documented | Done |
| Proxmox Backup Server documented | Done |
| Proxmox storage documented | Done |
| Proxmox networking documented | Done |
| Proxmox VM and container hygiene documented | Done |
| Proxmox monitoring documented | Done |
| YubiKey hardware 2FA documented | Done |
| n8n service documented | Done |
| Uptime Kuma service documented | Done |
| ntfy service documented | Done |
| Vaultwarden password vault documented | Done |
| Forgejo Git forge documented | Done |
| Forgejo Runner CI/CD documented | Done |
| Miniflux RSS reader documented | Done |
| step-ca internal ACME server documented | Done |
| Traefik central reverse proxy documented | Done |

## About JacOps

JacOps is the freelance brand of [Nicky Jacobs](https://www.linkedin.com/in/N-O-Jacobs), a SOC analyst and security engineer based in the Netherlands. Focus areas are detection engineering, network security and security automation.

## License

[MIT](LICENSE)
