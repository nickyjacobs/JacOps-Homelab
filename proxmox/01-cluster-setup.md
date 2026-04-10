# Cluster setup

🇬🇧 English | 🇳🇱 [Nederlands](01-cluster-setup.nl.md)

This document describes the Proxmox VE cluster: hardware, networking and cluster configuration. The hardening steps that secure this platform are in [02-hardening.md](02-hardening.md).

## Hardware

| Role | CPU | RAM | Boot | Bulk storage | Workloads |
|------|-----|-----|------|-------------|-----------|
| Node 1 | Intel i5-9400T, 6 cores | 16 GB | 256 GB NVMe | 1 TB SATA HDD | Application containers, monitoring |
| Node 2 | Intel i5-6500, 4 cores | 16 GB | 256 GB NVMe | None | Lab VMs, Windows targets |

Node 1 handles the always-on workloads because it has more cores and a dedicated HDD for backups. Node 2 runs lab VMs that are only started when needed, so the lack of bulk storage is not a problem.

Both CPUs lack hyperthreading. The core counts above are physical cores, not threads. This limits how many CPU-intensive VMs can run simultaneously, but for a homelab with mostly idle services it works fine.

## Storage layout

Each node uses the standard Proxmox storage layout created during installation.

| Storage | Type | Location | Use |
|---------|------|----------|-----|
| local | Directory | NVMe, ext4, root partition | ISO images, LXC templates, snippets |
| local-lvm | LVM-thin | NVMe, remaining space | VM and container root disks |
| local-sata | Directory | SATA HDD (node 1 only) | Backups, large VM disks |

LVM-thin provisioning means disk space is allocated on write, not on create. A 60 GB VM disk does not consume 60 GB of NVMe until the guest actually writes that much data. This matters on a 256 GB boot drive where every gigabyte counts.

## Cluster configuration

The cluster runs Proxmox VE 9.x on Debian 13 (trixie). Both nodes form a two-node cluster with corosync for state synchronisation.

Two nodes cannot achieve proper quorum on their own. Proxmox handles this by counting both votes and continuing as long as at least one node is present. This is not real HA. If a node goes down, the remaining node keeps running but cannot migrate workloads automatically. For services that need to survive a node failure, I document manual failover steps instead of pretending the cluster handles it.

Corosync uses secure authentication (on by default since Proxmox 9.x). The transport is knet over the Servers VLAN. Both nodes see each other on their management addresses and nowhere else.

## Networking

Both nodes connect to the switch as trunk ports. The bridge on each hypervisor is VLAN-aware, meaning any VLAN can reach any VM or container by setting a tag in the container or VM configuration. No switch reconfiguration needed.

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

The hypervisors themselves live on VLAN 10 (Servers) through a tagged sub-interface (`vmbr0.10`). This is intentional. The alternative is using an untagged native VLAN on the switch port, but that creates an inconsistency: the host would use native VLAN while its workloads use tagged VLANs on the same bridge. Tagged management keeps everything consistent.

See [decisions.md](../docs/decisions.md) for the reasoning behind this choice.

## VM and container placement

| VMID | Name | Type | Node | VLAN | Purpose |
|------|------|------|------|------|---------|
| 150 | n8n | LXC | Node 1 | 40 (Apps) | Workflow automation |
| 151 | Uptime Kuma | LXC | Node 1 | 40 (Apps) | Service monitoring |
| 2000 | Windows 11 Lab | VM | Node 2 | 30 (Lab) | Offensive security practice |

Application containers sit on Node 1 in the Apps VLAN. Lab VMs sit on Node 2 in the Lab VLAN. This separation is both logical (different trust levels) and practical (lab VMs are resource-heavy and only run when needed).

Each container and VM has `onboot: 1` set where appropriate, so services recover automatically after a node reboot.

## Backup strategy

A scheduled backup job runs weekly on Sunday at 03:00. All VMs and containers are included. Backups go to the SATA HDD on Node 1 with zstd compression and a four-week retention window.

This covers accidental breakage and configuration mistakes. It does not cover hardware failure of the HDD itself. For that, the documentation in this repository serves as the rebuild runbook.
