# Proxmox

🇬🇧 [English](README.md) | 🇳🇱 Nederlands

Twee-node Proxmox VE cluster dat virtual machines en containers draait voor het homelab. Deze sectie behandelt de clusterarchitectuur en de hardening van het platform zelf.

## Inhoud

| Document | Onderwerp |
|----------|-----------|
| [01-cluster-setup.nl.md](01-cluster-setup.nl.md) | Hardware, clusterconfiguratie, VLAN-aware networking |
| [02-hardening.nl.md](02-hardening.nl.md) | Volledige security hardening: SSH, firewall, fail2ban, 2FA, backups |
| [03-backups.nl.md](03-backups.nl.md) | Proxmox Backup Server, dedup-datastore, circular-dependency-safe backup-strategie |
| [04-storage.nl.md](04-storage.nl.md) | Thin provisioning, discard en TRIM, directory-storage, capacity monitoring, groeipad |
| [05-networking.nl.md](05-networking.nl.md) | VLAN-aware bridge, tagged sub-interfaces, firewall-lagen, corosync-verkeer, troubleshooting |
| [06-vm-hygiene.nl.md](06-vm-hygiene.nl.md) | Naamgeving, tags, guest agent, protection, boot-order, review en deprovisioning |
| [07-monitoring.nl.md](07-monitoring.nl.md) | Reachability versus host metrics, alerting-pad, Beszel-roadmap, bekende gaten |
| [08-yubikey.nl.md](08-yubikey.nl.md) | YubiKey 5C NFC als hardware 2FA, WebAuthn bij PVE, homelab CA, Firefox-instellingen |
