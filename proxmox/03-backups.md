# Backups

🇬🇧 English | 🇳🇱 [Nederlands](03-backups.nl.md)

This document describes the backup infrastructure for the Proxmox cluster. The weekly vzdump job from [02-hardening.md](02-hardening.md) was replaced with a Proxmox Backup Server (PBS) setup that adds deduplication, integrity verification, and a circular-dependency-safe fallback path.

## Starting point

After the hardening session there was a scheduled weekly vzdump job that had never actually run. The first maintenance window fell on the Sunday after setup. The risk was silent: a scheduled job without a first manual test run provides no guarantee that the schedule works, that the backup storage is writable, that the correct target is selected, or that container snapshots fall back to snapshot mode as they should.

A second shortcoming was the storage choice. The job wrote to the SATA directory storage on Node 1 as plain tar.zst archives. That works for configuration recovery but misses everything that makes backup infrastructure worth the effort: deduplication across VMs, integrity verification of stored chunks, incremental-forever backups that only write changes since the previous run, and encryption on disk.

A third shortcoming was the absence of a restore test. A backup without a restore test is not a backup.

The goal of this session was to address all three at once: run a manual test backup plus restore test on the old vzdump flow, deploy PBS as a replacement, and lock down the retention policy before the first automatic run.

## Choice: PBS as a VM on the hypervisor

PBS is designed to run on dedicated hardware. The official recommendation is that the backup target should be physically separated from the PVE cluster it protects. The principle is solid: a hardware failure taking out both hosts also takes out the backups.

In this homelab that second physical host does not exist. The options were:

1. Skip PBS and keep using vzdump
2. Run PBS as a virtual machine on one of the PVE nodes
3. Run PBS on an external VPS with backup traffic through WireGuard

Option 1 gives up all the dedupe and verify benefits. Option 3 moves the backup data outside the local network, adding bandwidth cost and complexity without proportional security gain for this scale. Option 2 became the choice, with an explicit solution for the circular dependency it introduces (see [Backup strategy](#backup-strategy) below).

PBS now runs as VM 180 (`pbs-01`) on Node 1, with its OS disk on the NVMe thin pool and its datastore on the SATA directory as a qcow2 file. The datastore gets thin provisioning plus room to grow without committing the full 500 GB up front.

## VM specifications

| Resource | Value | Reason |
|----------|-------|--------|
| vCPU | 2 (host type) | PBS is I/O-bound, not CPU-bound. Two cores cover chunking plus the verify job in parallel. |
| RAM | 4 GB, ballooning off | Official minimum plus margin for filesystem cache on the datastore. Ballooning off because fluctuations in available memory slow down chunk hashing. |
| OS disk | 32 GB on NVMe thin pool | Minimum for Debian plus PBS plus journald headroom. Fast disk for OS operations. |
| Datastore disk | 500 GB qcow2 on SATA directory | Thin-provisioned growth to 500 GB. The qcow2 wrapper gives a clean file that can itself be backed up via vzdump without copying the datastore contents. |
| Network | vmbr0 tagged VLAN 10 | Servers zone alongside the PVE hosts. No extra firewall rules needed for inter-node backup traffic. |
| Boot | `scsi0` only | After installation, the ISO is detached and the boot order adjusted. Otherwise reboots land in the installer again. |
| Guest agent | Active | PVE can read VM status and IP addresses without logging in. |
| onboot | 1 | Starts automatically with Node 1, keeping backups available after a host reboot. |

## Datastore: ext4 on qcow2

PBS asks during setup which filesystem to use for the datastore. Two options are reasonable on this hardware:

**ext4** is the simpler choice. No extra tuning, no RAM overhead for caches, no extra configuration for snapshots. All the datastore has to do is provide disk space to PBS, which handles its own deduplication and chunk management.

**ZFS** offers native compression, bitrot detection through scrubs, and snapshots. On a single-disk setup the biggest ZFS advantage disappears: there is no redundancy between disks, so checksums can detect corruption but cannot heal it. The ARC cache asks for roughly 1 GB extra RAM by default, which adds no value for this profile.

The choice became ext4. The redundancy layer sits one level up: the qcow2 file that houses the datastore is covered by the `pbs-self-backup` job (see below), and PVE-level qcow2 snapshots are the fallback for filesystem issues.

The filesystem is mounted at `/mnt/datastore/main` and created via `proxmox-backup-manager disk fs create` in a single step that also registers it as PBS datastore `main`.

## PVE integration

Tokens, not passwords. PVE reaches PBS with an API token tied to a dedicated service account, not with `root@pam` plus a password. That buys three things:

1. The service account password never needs to be used and can remain a random generated value in PBS that nobody knows or remembers.
2. Revocation is specific: if a token leaks, you revoke that one token. The rest of the authentication remains functional.
3. The ACL is scoped. The token only has `DatastoreBackup` rights on `/datastore/main`, nothing else.

The setup in PBS:

```
proxmox-backup-manager user create pve-sync@pbs --password <random>
proxmox-backup-manager acl update /datastore/main DatastoreBackup --auth-id pve-sync@pbs
proxmox-backup-manager acl update / Audit --auth-id pve-sync@pbs
proxmox-backup-manager user generate-token pve-sync@pbs pve-backup
proxmox-backup-manager acl update /datastore/main DatastoreBackup \
    --auth-id 'pve-sync@pbs!pve-backup'
```

The `Audit` role on `/` gives the token read-only access to fingerprint information, not to the contents of other datastores. The `DatastoreBackup` role on `/datastore/main` is set explicitly on both the user and the token, which is required: tokens do not inherit all permissions from their user automatically.

On the PVE side, PBS is added as cluster-wide storage:

```
pvesm add pbs pbs-main \
    --server 10.0.10.<pbs-ip> \
    --datastore main \
    --username 'pve-sync@pbs!pve-backup' \
    --password <token-secret> \
    --fingerprint <sha256> \
    --content backup
```

The fingerprint replaces certificate verification against a public CA. PBS ships with a self-signed certificate on install, which is the right choice on an internal network. The fingerprint pins the connection: PVE refuses to connect if the certificate on the other side does not match this exact SHA256 hash.

## Backup strategy

The core of the setup is two jobs that together resolve the circular dependency.

**Job 1: `weekly-backup`**

This job covers everything except PBS itself. Sunday 03:00, snapshot mode, zstd compression. Target: PBS. Scope: all VMs and containers with VM 180 explicitly excluded. Retention is not enforced by this job but by the PBS-side prune job (see Datastore maintenance), so that the `pve-sync@pbs` service account only needs `DatastoreBackup` permissions and not `Datastore.Prune`.

```
vzdump: weekly-backup
    schedule sun 03:00
    compress zstd
    enabled 1
    exclude 180
    mailnotification failure
    mode snapshot
    notes-template {{guestname}}
    storage pbs-main
    all 1
```

**Job 2: `pbs-self-backup`**

This job exists purely to break the circular dependency. Monday 04:00, same snapshot mode, fixed scope: VM 180 only. Target: the old SATA directory storage, the same bulk disk that Job 1 used to write to.

```
vzdump: pbs-self-backup
    schedule mon 04:00
    compress zstd
    enabled 1
    mailnotification failure
    mode snapshot
    notes-template {{guestname}} (pbs-self)
    prune-backups keep-weekly=2
    storage local-sata
    vmid 180
```

The reasoning is that a PBS VM backing itself up to PBS has no recovery path if the PBS datastore becomes unreachable. With this second job, there is a plain vzdump of the PBS VM on a different storage every week. In a catastrophic scenario the recovery path is: restore VM 180 from `local-sata`, start it up, and the datastore (which lives as a separate qcow2 file on the same SATA disk) remains untouched because it is not inside the VM backup.

Retention on Job 2 is deliberately shorter (two weeks instead of four). The configuration of PBS rarely changes, so old snapshots are less valuable than for production VMs and containers.

## Datastore maintenance

Three recurring jobs on the PBS side keep the datastore healthy. All three fall into the same Sunday window shortly after the weekly backup run, so they only act once the new backup data is in.

| Job | Schedule | Task |
|-----|----------|------|
| Garbage collection | Sunday 05:00 | Cleans up dedupe chunks that are no longer referenced by any snapshot |
| Prune | Sunday 05:30 | Enforces retention: keep-last 2, keep-weekly 4, keep-monthly 3 |
| Verify | Sunday 06:00 | Reads chunks back and checks their checksums against the index |

In addition, `verify-new=true` is set on the datastore, which means PBS verifies each new backup right after upload. That catches corruption before it disappears into the retention windows.

The GC job uses PBS's own two-phase algorithm: it first marks all chunks still in use, then removes the unmarked ones. The job can run while backups are in progress. It is a safe operation that does not need to coordinate with the Job 1 / Job 2 run schedules.

Retention is handled entirely by this PBS-side prune job, not by the PVE backup job. The `pve-sync@pbs` service account only has `DatastoreBackup` permissions and no `Datastore.Prune`. This follows the principle of least privilege: the backup client can write data, but retention decisions are made by PBS itself. The combination `keep-last 2, keep-weekly 4, keep-monthly 3` ensures recent backups stick around longer and monthly backups provide a longer timeline. The layers together barely cost any extra disk because most older monthly backups dedupe almost completely against the newer ones.

## First test run

After configuration, CT 150 and CT 151 were manually backed up to PBS to verify the flow end-to-end.

| Target | Data | Compressed | Duration | Throughput |
|--------|------|------------|----------|------------|
| CT 151 (monitoring stack) | 4.01 GiB | 2.03 GiB | 33 s | 126 MiB/s |
| CT 150 (n8n stack) | 4.09 GiB | 1.72 GiB | 42 s | 99 MiB/s |

Both backups succeeded on the first attempt. The `verify-new=true` setting means PBS checked the chunks right after upload, and `pbs-main` showed both new snapshots with their volume IDs in `pvesm list pbs-main`. Datastore occupancy stood at roughly 0.8% of 500 GB after two backups, which matches the expected compression ratio.

The first automatic run of Job 1 is scheduled for the next Sunday night. Mail notification on failure is enabled, so silent failure is not an option.

## Result

The backup infrastructure sits on three layers:

1. **PBS datastore** for the production VMs and CTs with deduplication, integrity checks and incremental-forever storage
2. **SATA directory** as the recovery path for the PBS VM itself, separate from the datastore it manages
3. **Weekly maintenance jobs** that run garbage collection, retention and verification in that order within a Sunday maintenance window

This setup provides everything a modern backup infrastructure should deliver without requiring the second physical host that the official recommendation suggests. The price is the complexity of a second backup job and a piece of operational discipline: the recovery procedure for PBS itself runs through the old vzdump flow, not through PBS. That procedure is documented and stays visible as long as Job 2 runs successfully every Monday morning.
