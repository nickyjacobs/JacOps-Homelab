# VM and container hygiene

🇬🇧 English | 🇳🇱 [Nederlands](06-vm-hygiene.nl.md)

This document describes the conventions every VM and container on this cluster follows. It is not about how to create a VM, `qm create` and the Proxmox installer already handle that. It is about the settings and conventions that keep a guest snapshot-safe ten months later, findable in the UI, and able to restart correctly after a host reboot.

## Starting point

A fresh Proxmox install produces guests with defaults that work but are not optimal for a homelab lasting longer than a week. The most-missed settings are the qemu-guest-agent (PVE does not know VM state without it), the protection flag (`qm destroy` is one typo away) and consistent tag use (search becomes guesswork as the cluster grows). This document captures the conventions that hold the different deploys from [roadmap.md](../docs/roadmap.md) together.

Not all conventions are equally strict. Some are hard rules (guest agent, onboot), others are conventions that produce consistency (hostname scheme, tags). The text below marks the difference.

## Naming and VMIDs

Every guest gets a VMID following a fixed scheme, and a hostname that makes that VMID visible in every terminal.

**VMIDs by category.** Numbering is grouped so `pct list` and `qm list` sort naturally:

| Range | Category | Examples |
|-------|----------|----------|
| 100-149 | Reserved | Default Proxmox install ISOs, optional helper CTs |
| 150-159 | Application containers | CT 150 n8n, CT 151 monitoring stack |
| 160-169 | Foundation LXC services | CT 160 Forgejo, CT 161 runner, CT 162 Vaultwarden, CT 163 Miniflux |
| 170-179 | Lab containers | CT 170 Docker host for DVWA and Metasploitable 2 |
| 180-189 | Infrastructure VMs | VM 180 `pbs-01` |
| 2000+ | Lab VMs | VM 2000 Windows 10 Evaluation |

The three container ranges (150/160/170) separate production applications from foundation and from lab. That boundary runs parallel to the VLAN assignment from [05-networking.md](05-networking.md). A VMID between 160 and 169 belongs on the Servers VLAN. One between 170 and 179 on the Lab VLAN. That makes misplacement easy to spot during an audit.

**Hostnames.** Foundation services get a hostname of the form `<service>-<nn>` (for example `pbs-01`, `vault-01`, `forgejo-01`). Container stacks hosting multiple services get a hostname describing the stack (`monitoring-stack` on CT 151). The hostname is separate from the DNS CNAME used publicly or internally. `vault.jacops.local` points to CT 162, but the container calls itself `vault-01` from the shell.

## Tags

Tags are lightweight metadata at the Proxmox level. They appear in the UI next to every VM and container, and they are searchable. Without tags, every change means scrolling through the list again to spot which guests play which role. With tags, every guest gets a small label set saying where it belongs.

Three tag categories are in use:

**Role.** What this guest is. Examples: `application`, `infrastructure`, `backup`, `foundation`, `lab`, `monitoring`, `automation`.

**Lifecycle.** How the guest is treated. Examples: `production`, `scratch`, `onboarding`, `deprecated`.

**Criticality.** How severe an outage is. Examples: `critical`, `important`, `normal`.

A typical foundation service has three tags: `infrastructure;foundation;critical`. A lab container gets `lab;scratch;normal`. The benefit comes from search: `Tags: critical` filters in one click every guest whose outage needs attention.

Tags are not a replacement for documentation and should not be maintained for every small change. They serve as operational shortcuts, nothing more.

## Required VM settings

The settings below should be enabled on every VM, regardless of workload.

| Setting | Value | Reason |
|---------|-------|--------|
| `agent` | `1` | PVE reads VM state and IP addresses via the qemu-guest-agent once it runs in the guest |
| `onboot` | `1` | VM starts automatically on host reboot, so services do not need manual restart |
| `protection` | `1` for production VMs | Blocks `qm destroy` without first explicitly turning protection off |
| `machine` | `q35` | More modern chipset emulation, required for PCIe passthrough and newer guests |
| `bios` | `seabios` or `ovmf` | SeaBIOS for simplicity, OVMF only for guests that demand UEFI |
| `scsihw` | `virtio-scsi-single` | Separate virtio controller per disk, better performance under parallel I/O |
| `cpu` | `host` | Pass through all CPU features to the guest, avoids performance loss and compatibility issues |
| `ostype` | Set correctly | PVE applies per-OS optimizations (l26 for Linux, win10/win11 for Windows) |

For the qemu-guest-agent, flipping the flag in the VM config is not enough on its own. The agent has to be installed and running inside the guest as well. On Debian and Ubuntu:

```
apt install qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

On Windows the agent comes from the virtio-win ISO. Only once the agent is running can PVE issue a clean shutdown (instead of a hard reset) and read IP addresses in the UI.

The `protection=1` flag is a cheap insurance policy. It stops an accidental `qm destroy <vmid>` without costing anything in performance or operational freedom. For throwaway lab VMs (scratch tag) it is deliberately off, because by their nature those are meant to be quickly torn down and rebuilt.

## Required container settings

Containers share many defaults with VMs, but have their own quirks.

| Setting | Value | Reason |
|---------|-------|--------|
| `unprivileged` | `1` | Root inside the container is not root on the host, default for every new CT |
| `onboot` | `1` | Restarts with the host |
| `protection` | `1` for production CTs | Same block as VMs but on `pct destroy` |
| `ostype` | Set correctly | Determines which integration PVE applies |
| `features` | `nesting=1` for Docker in LXC, `keyctl=1` where needed | Off by default, on only where a specific workload demands it |
| `hostname` | Consistent scheme | See naming above |

**Unprivileged by default.** Privileged containers are faster in a few edge cases, but root inside a privileged container is root on the host. That is a class-A risk. Every CT on this cluster is unprivileged unless there is a documented reason otherwise, and so far there is none.

**Nesting and keyctl only for Docker in LXC.** The Forgejo runner from the roadmap runs Docker inside an LXC, which requires `nesting=1,keyctl=1` as feature flags. Those flags give the container more kernel capabilities than the default, and should only be on where that is needed. Any LXC accidentally created with nesting on without the workload asking for it gets the flag turned off in review.

**Features review.** Every new LXC goes through a fixed check: look at the `features` line in the config and decide deliberately whether anything beyond the default is required. In practice that line is empty for 90 percent of the containers.

## Boot order and startup delays

Two settings control what happens on a node reboot.

**`onboot`** is on for every production guest. That is the default from the tables above and the reason the container stack brings itself up again after a reboot.

**`startup`** is an optional string that controls order and delays. It takes three values:

```
startup: order=5,up=60,down=120
```

- `order`: lower number starts earlier. Use this to respect dependencies. Infrastructure (PBS, Vaultwarden) at `order=1`, applications consuming credentials from Vaultwarden at `order=5`, lab VMs (if they are onboot at all) at `order=10`.
- `up`: seconds to wait after starting before the next guest is allowed to start. Useful when a service needs a few seconds to open its database before others hit it.
- `down`: seconds to wait for a clean shutdown before PVE does a hard stop. Default is 180 seconds for VMs and 60 for CTs. A database that needs longer to flush its buffers gets a higher value.

The `startup` string is opt-in. Without it, guests start in arbitrary order using the PVE defaults, which rarely causes problems in this cluster because there are no hard inter-service dependencies that do not recover on their own.

## Snapshots versus backups

Snapshots and backups are not the same and are occasionally confused.

**Snapshots** live at the LVM-thin level for containers and at the qcow2 level for VMs on directory storage. They are free and instant, and intended for short-term safety: "I am about to make a risky change, snapshot so I can roll back." A snapshot is not a backup because it lives on the same disk as the original. Disk gone, snapshot gone.

**Backups** are the vzdump or PBS outputs described in [03-backups.md](03-backups.md). Those live on separate storage (the SATA disk on Node 1 or the PBS datastore on top of it for this cluster) and cover disk failure of the node itself.

The convention for this cluster: every risky change gets a snapshot first (`qm snapshot <vmid> pre-change` or `pct snapshot <vmid> pre-change`), removed after the change succeeds or after a few days. Backups are not made manually except as extra safety for a genuinely large change. The weekly automated backup from 03-backups covers the normal case.

Snapshots on the thin pool are cheap until they sit around. A snapshot plus a few weeks of writes in the guest means the copy-on-write delta grows and takes up real space. Old snapshots are therefore flagged in review after a week.

## Review after every deploy

Every new VM or LXC goes through a fixed checklist right after creation. The list is short and manual, because tooling is not worth building for the scale of this cluster:

1. **Tags set?** At minimum the three categories (role, lifecycle, criticality).
2. **Guest agent installed and running?** `qm agent <vmid> ping` must succeed.
3. **onboot on?** `qm config <vmid> | grep onboot` or `pct config <vmid> | grep onboot`.
4. **Protection on for production?** `qm config <vmid> | grep protection`.
5. **Firewall flag on the NIC?** See [05-networking.md](05-networking.md) for the `firewall=1` convention.
6. **Discard and SSD flags on the disk?** See [04-storage.md](04-storage.md) for thin-pool settings.
7. **Hostname consistent with the scheme?**
8. **First backup will run on the next scheduled job?** Or there is a deliberate exclusion (like VM 180 sitting in the pbs-self-backup).

Point 8 is the most forgotten. It is easy to create a new CT, start its work, and notice two weeks later that the weekly job did not pick it up because it sits in an exclude list that no longer matches reality.

## Cleanup and deprovisioning

The counterpart to a careful setup is a careful cleanup. When a guest has to go:

1. **Final snapshot or backup** in case cleanup unexpectedly touches something relevant.
2. **Protection off** with `qm set <vmid> --protection 0` or `pct set <vmid> --protection 0`.
3. **Destroy** with `qm destroy <vmid>` or `pct destroy <vmid>`. The `--purge 1` flag also removes references in backup jobs and firewall configs.
4. **Verify** with `pvesm status` that thin-pool space came back (immediate for containers, up to a minute for VMs).
5. **Log entry** in `decisions.md` or `lessons-learned.md` if something was learned that a future deploy should handle differently.

A mistake on step 3 without `--purge 1` leaves orphaned entries in the backup config that produce errors on the next `vzdump` run. Not critical, but annoying.

## Result

The hygiene conventions deliver three things:

1. **Predictability.** Every VM or CT created under these rules behaves the same on reboot, during backup, and when searched in the UI.
2. **Low setup cost.** The checklist is manual but short, following the same order every time. No tooling needed, just discipline.
3. **Safety net against mistakes.** Protection flags, consistent VMID ranges, and explicit tags mean a typo in a destroy command stops before it touches anything important.

The cost is small: a few extra minutes per deploy for the checklist. The alternative, where every guest is left on defaults and later you have to guess what settings diverged from the norm, costs far more as soon as the cluster grows beyond a handful of guests.
