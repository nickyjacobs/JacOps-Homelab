# Cluster setup

🇬🇧 [English](01-cluster-setup.md) | 🇳🇱 Nederlands

Dit document beschrijft het Proxmox VE cluster: hardware, netwerk en clusterconfiguratie. De hardeningstappen die dit platform beveiligen staan in [02-hardening.nl.md](02-hardening.nl.md).

## Hardware

| Rol | CPU | RAM | Boot | Bulkopslag | Workloads |
|-----|-----|-----|------|-----------|-----------|
| Node 1 | Intel i5-9400T, 6 cores | 16 GB | 256 GB NVMe | 1 TB SATA HDD | Applicatiecontainers, monitoring |
| Node 2 | Intel i5-6500, 4 cores | 16 GB | 256 GB NVMe | Geen | Lab VMs, Windows targets |

Node 1 draait de always-on workloads vanwege de extra cores en een aparte HDD voor backups. Node 2 draait lab-VMs die alleen gestart worden wanneer nodig, dus het ontbreken van bulkopslag is geen probleem.

Beide CPUs missen hyperthreading. De aantallen hierboven zijn fysieke cores, geen threads. Dit beperkt hoeveel CPU-intensieve VMs tegelijk kunnen draaien, maar voor een homelab met voornamelijk idle services werkt het prima.

## Storage layout

Elke node gebruikt de standaard Proxmox storage layout die tijdens installatie wordt aangemaakt.

| Storage | Type | Locatie | Gebruik |
|---------|------|---------|---------|
| local | Directory | NVMe, ext4, rootpartitie | ISO images, LXC templates, snippets |
| local-lvm | LVM-thin | NVMe, resterende ruimte | VM- en container rootdisks |
| local-sata | Directory | SATA HDD (alleen node 1) | Backups, grote VM-disks |

LVM-thin provisioning betekent dat schijfruimte wordt toegewezen bij schrijfacties, niet bij aanmaak. Een 60 GB VM-disk verbruikt pas 60 GB NVMe wanneer de guest die hoeveelheid data daadwerkelijk schrijft. Dit is van belang op een 256 GB bootdrive waar elke gigabyte telt.

## Clusterconfiguratie

Het cluster draait Proxmox VE 9.x op Debian 13 (trixie). Beide nodes vormen een twee-node cluster met corosync voor state-synchronisatie.

Twee nodes kunnen geen correct quorum bereiken op eigen kracht. Proxmox lost dit op door beide stemmen te tellen en door te draaien zolang minimaal een node beschikbaar is. Dit is geen echte HA. Als een node uitvalt, blijft de overige node draaien maar kan geen workloads automatisch migreren. Voor services die een nodefailure moeten overleven documenteer ik handmatige failover in plaats van te doen alsof het cluster dit afhandelt.

Corosync gebruikt secure authentication (standaard aan sinds Proxmox 9.x). Het transport is knet over het Servers VLAN. Beide nodes zien elkaar op hun management-adressen en nergens anders.

## Networking

Beide nodes zijn aangesloten op de switch als trunk ports. De bridge op elke hypervisor is VLAN-aware, wat betekent dat elk VLAN elke VM of container kan bereiken door een tag in te stellen in de configuratie. Geen switchconfiguratie nodig.

```
auto vmbr0
iface vmbr0 inet manual
        bridge-ports nic0
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094

auto vmbr0.10
iface vmbr0.10 inet static
        address 10.0.10.x/24
        gateway 10.0.10.1
```

De hypervisors zelf staan op VLAN 10 (Servers) via een tagged sub-interface (`vmbr0.10`). Dit is een bewuste keuze. Het alternatief is een untagged native VLAN op de switchport, maar dat creëert een inconsistentie: de host zou native VLAN gebruiken terwijl de workloads tagged VLANs gebruiken op dezelfde bridge. Tagged management houdt alles consistent.

Zie [decisions.nl.md](../docs/decisions.nl.md) voor de redenering achter deze keuze.

## VM- en containerplaatsing

| VMID | Naam | Type | Node | VLAN | Doel |
|------|------|------|------|------|------|
| 150 | n8n | LXC | Node 1 | 40 (Apps) | Workflowautomatisering |
| 151 | Uptime Kuma | LXC | Node 1 | 40 (Apps) | Servicemonitoring |
| 2000 | Windows 11 Lab | VM | Node 2 | 30 (Lab) | Offensive security oefeningen |

Applicatiecontainers staan op Node 1 in het Apps VLAN. Lab-VMs staan op Node 2 in het Lab VLAN. Deze scheiding is zowel logisch (verschillende trustniveaus) als praktisch (lab-VMs zijn resource-intensief en draaien alleen wanneer nodig).

Elke container en VM heeft `onboot: 1` ingesteld waar van toepassing, zodat services automatisch herstellen na een node-reboot.

## Backupstrategie

Een geplande backupjob draait wekelijks op zondag om 03:00. Alle VMs en containers worden meegenomen. Backups gaan naar de SATA HDD op Node 1 met zstd-compressie en een retentie van vier weken.

Dit dekt accidentele schade en configuratiefouten. Het dekt geen hardwarefailure van de HDD zelf. Daarvoor dient de documentatie in deze repository als rebuild runbook.
