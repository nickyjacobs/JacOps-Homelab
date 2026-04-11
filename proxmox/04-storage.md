# Storage

🇬🇧 English | 🇳🇱 [Nederlands](04-storage.nl.md)

This document deepens the storage layer of the Proxmox cluster. The base table in [01-cluster-setup.md](01-cluster-setup.md) describes which storage exists and where it runs. This doc explains how those layers work together, how space is measured, and what operational discipline is needed to stop a thin-provisioned cluster from quietly running out of room.

## Starting point

The cluster runs on two nodes with a deliberately asymmetric storage setup. Node 1 has an extra SATA disk that Node 2 does not, and that difference dictates which workloads land on which node. The always-on application containers and the backup infrastructure live on Node 1, while Node 2 stays free for lab VMs that do not run continuously.

The Proxmox installer creates three storage entries by default: `local` (directory), `local-lvm` (LVM-thin pool), and optionally extra directory storage for extra disks. That layout is kept here with one addition: the SATA disk on Node 1 was manually registered as directory storage `local-sata` after installation.

## Disk layout

The actual usable space differs from the marketing capacity on the disks. The table below reflects the measured situation, not the labels on the hardware.

| Node | Disk | Total | `pve-root` | `local-lvm` thin pool | Directory storage |
|------|------|-------|------------|------------------------|-------------------|
| Node 1 | NVMe | 238 GB | 69 GB | 141 GB | — |
| Node 1 | SATA | 953 GB | — | — | 953 GB (`local-sata`) |
| Node 2 | NVMe | 238 GB | 69 GB | 141 GB | — |

`pve-root` holds the Debian install plus the Proxmox binaries, ISO uploads, and LXC templates. The rest of the NVMe goes into the thin pool from which VM and container disks are carved. The SATA disk on Node 1 is dedicated to bulk storage: the PBS datastore (as a qcow2 file) and the self-backup of PBS itself.

## Storage entries and what lives where

The Proxmox storage configuration in `/etc/pve/storage.cfg` maps physical locations to logical storage entries. Each entry has a content type that decides what is allowed inside.

| Entry | Type | Location | Content | Shared | Use |
|-------|------|----------|---------|--------|-----|
| `local` | Directory | `/var/lib/vz` on `pve-root` | `iso`, `vztmpl`, `snippets`, `backup` | No | ISO uploads, LXC templates, cloud-init snippets |
| `local-lvm` | LVM-thin | `pve/data` thin pool | `images`, `rootdir` | No | VM disks and container rootfs |
| `local-sata` | Directory | `/mnt/pve/local-sata` on HDD | `images`, `rootdir`, `backup`, `iso`, `vztmpl` | No | PBS datastore qcow2, PBS self-backup, large throwaway VMs |
| `pbs-main` | Proxmox Backup Server | VM 180 `pbs-01` | `backup` | No | Weekly backup target for Job 1 (see [03-backups.md](03-backups.md)) |

Content types are the guardrail that keeps ISOs out of a thin pool and stops backups landing on a storage that is not large enough to hold them. A storage entry refuses content that is not listed in its `content` field.

None of the entries are `shared`. Two-node clusters with local storage cannot live-migrate, and live migration over shared storage requires infrastructure (NFS or Ceph) that does not exist in this cluster. Migration between nodes uses `qm migrate` with the `--with-local-disks` flag, which copies disk contents over the network. That is slower than live migration but works for planned moves like a node reboot.

## Thin provisioning in practice

LVM-thin provisioning is the default for VM and container disks on this cluster. The mechanism is simple: a VM with a 60 GB disk does not reserve 60 GB up front in the thin pool. The pool tracks how many blocks have actually been written and hands those out to the VM.

That has three consequences that matter on every deploy.

**Overcommit is possible, and dangerous.** You can create ten VMs each with a 60 GB disk on a 141 GB pool as long as those VMs do not collectively write more than 141 GB. On the eleventh write that fills the pool, things start breaking: VM filesystems go read-only or corrupt. The pool has no soft limit, it has a hard boundary.

**Monitor the pool fill, not the sum of disk sizes.** `pvesm status` shows how much GB the pool has in total, not how much VMs have collectively allocated on paper. The relevant numbers come from `lvs -o +data_percent`:

```
# lvs -o +data_percent pve
  LV              VG  Attr       LSize    Data%
  data            pve twi-aotz-- 141.43g  42.67
  root            pve -wi-ao---- 69.37g
```

The `Data%` column on the `data` LV is the only value that matters. If it climbs above eighty percent, it is time to either clean up disks or move growing workloads to directory storage.

**Trimming is needed to return freed space to the pool.** A VM that deletes a file sees free space return immediately in its own filesystem. The thin pool underneath notices nothing, unless the guest issues a TRIM command. Without TRIM, the `Data%` percentage climbs monotonically, even as workloads discard data.

## Discard and TRIM

Discard is off by default on VM disks created by the installer or via `qm create`. Every VM on the thin pool should have it on. The configuration lives in the VM config:

```
scsi0: local-lvm:vm-180-disk-0,discard=on,iothread=1,ssd=1
```

Three flags work together:

- `discard=on` tells Proxmox that the VM is allowed to send TRIM commands to the thin pool. Without it they are silently dropped.
- `ssd=1` advertises the disk as SSD to the guest, which causes modern Linux distros to enable their periodic `fstrim.timer`.
- `iothread=1` moves storage I/O onto its own thread instead of the QEMU main loop, improving throughput with parallel workloads.

Inside the guest, `fstrim` has to run. On Debian and Ubuntu that is the default via `fstrim.timer`, which walks all mounted filesystems once a week. You can verify it directly:

```
# systemctl status fstrim.timer
● fstrim.timer - Discard unused filesystem blocks once a week
     Loaded: loaded
     Active: active (waiting)
    Trigger: Mon 2026-04-13 00:04:03 CEST
```

Containers behave slightly differently. LXC containers share the host kernel and have no block device of their own. The thin pool sees every write directly, and on `pct destroy` the container volume is returned to the pool. No TRIM step is needed: the pool already knows which blocks are free.

## Directory storage on the SATA disk

`local-sata` is not an LVM-thin pool but a plain directory on an ext4 filesystem. The choice is deliberate for two reasons.

The first is that the SATA disk mainly holds large files with a single writer: the PBS datastore as a qcow2 and the vzdump archives from the PBS self-backup. For that pattern, LVM-thin adds nothing and only introduces extra layers that can fail.

The second is that directory storage allows the qcow2 wrapper the PBS setup needs. The datastore lives as one big qcow2 file on the filesystem, and PBS itself is the only writer. During recovery, that qcow2 can be accessed through normal file operations, without first activating an LVM logical volume.

```
# ls -lh /mnt/pve/local-sata/images/180/
total 12G
-rw-r----- 1 root root 500G Apr 11 17:45 vm-180-disk-1.qcow2
```

The `500G` in the listing is the *virtual* size. The qcow2 file grows along with the data PBS writes into it thanks to sparse allocation. After two backups the actual usage was 12 GB, as shown above.

## Capacity monitoring

Three commands give a full picture of storage state on a node:

```
# pvesm status
Name             Type     Status           Total            Used       Available        %
local             dir     active        73095180         6821756        62534268    9.33%
local-lvm     lvmthin     active       148298752        63280180        85018572   42.67%
local-sata        dir     active       976284752        12288000       914496752    1.26%
```

`pvesm status` is the fastest check. It lists all registered storages with their total, usage, and percentage. For directory storages this is accurate. For the thin pool it shows *allocated* versus *free*, which is useful as a first signal but not the same as the `Data%` value from `lvs`.

```
# lvs
  LV     VG  Attr       LSize    Pool Origin Data% Meta%
  data   pve twi-aotz-- 141.43g              42.67  2.14
  root   pve -wi-ao---- 69.37g
  ...
```

`lvs` is the second layer. `Data%` is the hard thin-pool fill, and `Meta%` is the metadata pool that thin provisioning maintains for itself. If `Meta%` creeps toward one hundred, the pool loses track of its own administration before the data side fills up. That is rare but fatal.

```
# df -h /var/lib/vz /mnt/pve/local-sata
Filesystem                Size  Used Avail Use% Mounted on
/dev/mapper/pve-root       69G  6.5G   60G  10% /
/dev/sdb1                 932G   12G  873G   2% /mnt/pve/local-sata
```

`df -h` gives the filesystem truth on the directory storages. For `local` that is the same disk as `pve-root` (sharing the NVMe), for `local-sata` it is the separate SATA disk.

An eighty percent threshold on `local-lvm` is the moment to act: prune, force TRIM, or move disks. Eighty percent on `pve-root` usually means logs or templates have been sitting around too long. Eighty percent on `local-sata` means the PBS datastore is closing in on its limit and retention needs to tighten.

## Backup flow and storage coupling

The backup infrastructure from [03-backups.md](03-backups.md) touches all three storage types and uses them in a specific way.

```
            VM disks on local-lvm                    PBS self-backup
         (Node 1 + Node 2, thin-provisioned)        (vm-180 to vzdump archive)
                    │                                       │
                    │ Job 1: weekly-backup                   │ Job 2: pbs-self-backup
                    ▼                                       ▼
    ┌─────────────────────────┐                ┌─────────────────────────┐
    │  PBS datastore          │                │  local-sata directory   │
    │  (qcow2 on local-sata)  │                │  (vzdump tar.zst)       │
    └─────────────────────────┘                └─────────────────────────┘
                    │                                       │
                    └──────────────── both on the same SATA disk ─────┘
```

The only disk that holds backup data is the SATA disk on Node 1. Physical loss of that disk means losing both the PBS datastore and the vzdump fallback for PBS itself. That is an accepted risk within this homelab: a second physical host or an off-site target is not available, and the documentation in this repo serves as the rebuild runbook for the rest.

Vaultwarden gets an additional external backup layer on top of this (see future services documentation). Only the vault goes off-site, because losing credentials is the worst hangover while also being the smallest data set to transmit.

## Growth path

The cluster has three realistic expansion paths once the current disks fill up.

**Second SATA disk in Node 2.** Node 2 currently has no bulk storage. Adding a second SATA disk there creates a second directory storage (`local-sata-n2`) that can serve as a secondary backup target. That provides a path to physically separate Job 1 and Job 2 backups: Job 1 to the Node 1 SATA, Job 2 to the Node 2 SATA. Right now they share the same disk.

**NVMe upgrade.** The 238 GB NVMe drives are the bottleneck for the thin pool. Upgrading to 512 GB or 1 TB immediately provides more room for VM disks without changing any structure. The migration steps are: add the new disk, `pvcreate` and `vgextend pve`, then `lvextend` on the thin pool. No downtime is needed for the pool extension itself, only for the hardware swap.

**Directory storage for large throwaway VMs.** The Windows 10 lab VM from [Phase 2 of the roadmap](../docs/roadmap.md) will get a 60 GB disk on `local-sata` instead of `local-lvm`. Large practice VMs that only run during sessions belong on slow bulk storage, not on the NVMe shared by the 24/7 containers.

None of the three is urgent now. The NVMe pools sit at 42 percent, the SATA disk at 2 percent. The plan is to act when either hits eighty percent, and not before.

## Result

The storage layer delivers three things:

1. **Fast root disks** for VMs and containers through the LVM-thin pool on NVMe, with discard and iothread on so the pool stays clean.
2. **Bulk storage** on the SATA directory on Node 1 for backup data and large throwaway VMs, deliberately separated from the primary workloads.
3. **Predictable monitoring** through `pvesm status` plus `lvs`, with eighty percent as the action threshold and the two-phase backup setup as the fallback if a disk fails anyway.

The asymmetry between Node 1 and Node 2 is not a shortcoming but a placement rule: always-on workloads on Node 1, lab VMs on Node 2. Every new deploy follows that rule unless there is an explicit reason to deviate.
