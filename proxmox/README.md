# Proxmox

🇬🇧 English | 🇳🇱 [Nederlands](README.nl.md)

Two-node Proxmox VE cluster running virtual machines and containers for the homelab. This section covers the cluster architecture and the hardening applied to the platform itself.

## Contents

| Document | Topic |
|----------|-------|
| [01-cluster-setup.md](01-cluster-setup.md) | Hardware, cluster configuration, VLAN-aware networking |
| [02-hardening.md](02-hardening.md) | Full security hardening: SSH, firewall, fail2ban, 2FA, backups |
| [03-backups.md](03-backups.md) | Proxmox Backup Server, dedup datastore, circular-dependency-safe backup strategy |
| [04-storage.md](04-storage.md) | Thin provisioning, discard and TRIM, directory storage, capacity monitoring, growth path |
| [05-networking.md](05-networking.md) | VLAN-aware bridge, tagged sub-interfaces, firewall layers, corosync traffic, troubleshooting |
| [06-vm-hygiene.md](06-vm-hygiene.md) | Naming, tags, guest agent, protection, boot order, review and deprovisioning |
| [07-monitoring.md](07-monitoring.md) | Reachability versus host metrics, alerting path, Beszel roadmap, known gaps |
| [08-yubikey.md](08-yubikey.md) | YubiKey 5C NFC as hardware 2FA, WebAuthn on PVE, homelab CA, Firefox settings |
