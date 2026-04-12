# Lessons Learned

🇬🇧 English | 🇳🇱 [Nederlands](lessons-learned.nl.md)

Things that went wrong, surprised me, or that I would handle differently next time. Written down so I do not repeat them.

---

## VLAN renumbering order matters

When renumbering VLANs, subnet conflicts can block you. I needed to move the Guest network to `10.0.50.0/24`, but that subnet was occupied by the Lab network. The Lab network had to move to `10.0.30.0/24` first to free up the range.

The lesson is to map out the full chain of moves before starting. Each VLAN rename is a small migration, and the order depends on which subnets need to be freed first. Planning the sequence on paper took five minutes and saved at least an hour of backtracking.

## UniFi networks cannot always be edited in place

The Guest network refused to save after changing its VLAN ID and subnet. The UI returned a generic "Failed saving network" error with no further detail. The fix was to delete the network entirely and recreate it with the new settings.

This meant temporarily reassigning the Guest WiFi SSID to another network, creating the new Guest network, and then pointing the SSID back. It worked, but if I had not known the SSID needed to be unlinked first, the delete would have failed too.

**Takeaway:** before renaming or renumbering a UniFi network, check what depends on it (SSIDs, switch port profiles, firewall rules). If the edit fails, deleting and recreating is a valid path, but only if you detach dependencies first.

## Proxmox cluster migration needs coordinated steps

Moving a two-node Proxmox cluster to a new subnet required changes on both nodes in a specific order: network interfaces, `/etc/hosts`, and corosync configuration. Changing only one node first would break the cluster because corosync would try to reach the other node on the old IP.

The approach that worked:
1. Stop all VMs and containers
2. Prepare the new network config on both nodes (write to `interfaces.new`, do not activate yet)
3. Update `/etc/hosts` on both nodes
4. Update corosync config with new IPs and bump the config version
5. Reboot both nodes at the same time

The key insight is that the cluster has to transition as a unit. Doing one node at a time creates a split-brain situation where each node thinks the other is unreachable.

**Takeaway:** always back up the full config directory (`/etc/pve/`, `/etc/network/`, `/etc/hosts`) before a cluster-wide network change. The backups saved me when I had to verify the original corosync config version number.

## Custom zones are deny-by-default without extra work

I spent time planning how to implement deny-by-default firewalling with the global "Block All" toggle. Turns out custom zones in UniFi are already deny-by-default between each other. Moving every network out of the built-in Internal zone and into a custom zone was enough.

I only realized this after reading the UniFi documentation more carefully. The global toggle exists for the built-in zones (Internal, External, Hotspot). Custom zones do not follow that toggle because they start with no inter-zone rules at all, which means deny.

**Takeaway:** read the platform documentation before designing workarounds. The feature I was trying to build already existed.

## Honeypot addresses should follow VLAN renumbering

After renumbering VLANs, the honeypot IP addresses still pointed to the old subnets. Honeypots in UniFi are configured per network with a fixed IP (`.2` addresses in my case). When the subnets changed, the honeypots needed to be reconfigured to match.

This is easy to miss because honeypots do not show up in the main network configuration. They are under the security settings and do not automatically follow subnet changes.

**Takeaway:** keep a checklist of everything that references a specific subnet. VLANs, DHCP ranges, firewall rules, honeypots, static DNS entries, VPN routes. Renumbering one means updating all of them.

## Switch port profiles survive network changes

When renumbering VLANs, I expected to have to reconfigure switch port profiles. The ports kept working because UniFi switch profiles reference the network by name, not by VLAN ID. Renaming the VLAN or changing its ID does not break the port assignment.

This is good design on UniFi's part, but I only discovered it during the migration. Knowing this upfront would have reduced the risk assessment for the VLAN renumbering.

## Pre-shared keys on WireGuard are worth the extra step

WireGuard already authenticates peers through public key cryptography. Adding a pre-shared key (PSK) on top is optional and adds another symmetric encryption layer. The setup cost is one extra line in each peer config.

The reason to use it: post-quantum resistance. If someone captures WireGuard traffic today and breaks Curve25519 in ten years, the PSK layer still protects the session. For a homelab this is arguably overkill, but the cost is near zero and the habit is worth building.

## iOS ntfy push breaks when the base URL does not match exactly

Self-hosted ntfy uses an upstream pattern for iOS notifications. The server forwards a poll request to `ntfy.sh` using a SHA256 hash that is computed from `base-url + topic`. The iOS app computes the same hash from the default server URL that the user entered. When the two hashes do not match, pushes never arrive on the phone.

I spent over an hour chasing this problem. Notifications showed up in the ntfy web UI and in the iOS app when I opened it manually, but never as banners. Every config file looked correct. The debug logs showed a successful `Publishing poll request` line. Everything appeared healthy, and nothing worked.

The cause was a typo in the Docker Compose file. The `NTFY_BASE_URL` environment variable was set to `https://ntfy.example.nl` while the actual public URL used the `.online` TLD. The config file inside the container had the correct `.online` value, but environment variables override config files in ntfy. The server was hashing against one URL, the iOS app against another, and the two never met at `ntfy.sh`.

**Takeaway:** set the base URL in exactly one place (either the env var or the config file, never both), verify the `/v1/config` endpoint returns what you expect, and double-check the default server URL stored in the iOS app character by character. The silent failure mode is particularly brutal because every diagnostic suggests things are working.

## Docker environment variables override config files silently

Closely related to the ntfy base URL issue: ntfy (and many other Go services) let you configure the same setting through either a YAML config file or an environment variable. When both exist, the environment variable wins. There is no warning, no startup log line, nothing that says "I am ignoring your config file."

I updated `server.yml` inside the container, restarted ntfy, and assumed my change had taken effect. It had not. The env var from `docker-compose.yml` was still driving the behaviour, and my "fix" did nothing.

**Takeaway:** pick one source of truth per setting. For containerized services, environment variables are usually the better choice because they travel with the compose file and show up in `docker inspect`. If you use the config file instead, make sure the env vars are not set at all, not just set to the same value.

## Documentation marked "done" does not have to describe reality

The hardening documentation of the Proxmox cluster was listed in the local working directory as fully complete. All nine phases ticked off, including SSH hardening and a dedicated admin user with sudo. A follow-up session that started with an SSH check on both nodes revealed that the `sudo` binary was not installed at all, and that `PermitRootLogin yes` plus `X11Forwarding yes` were still active in `sshd_config`. The changes had been planned and written down, but not actually applied to the nodes.

The cause is hard to reconstruct after the fact. A previous session may have edited the config without running `systemctl reload ssh`, after which somebody rebooted the node later without the on-disk config being updated. A rollback of something unrelated may have pulled the SSH changes back with it. Whatever the cause, the documentation and reality drifted apart without anybody noticing.

**Takeaway:** verify the actual state before trusting documentation. For every session that builds on a previous one, a three-minute SSH check of critical config files is cheaper than an hour of debugging something that "should already be in place". A `sshd -T | grep -E 'permitroot|password|x11'` tells you more than a checkmark in a README.

## US and NL keyboard layouts in installer password prompts

The first install of Proxmox Backup Server ended with a root password that no longer worked. Not in SSH, not in the web UI, not in the console through noVNC. The installer asked for password confirmation by typing it twice and accepted both entries as matching. After reboot, the password I was now typing turned out not to be the password I had meant to set during install.

The cause was a layout mismatch. The installer was set to US keyboard, which in practice means that special characters like `@`, `#`, `/`, `|` and `\` sit in different positions than on a Mac with Dutch or US-International layout. The password contained an `@` that produced a different character at install time than at login time. The double confirmation prompt did not detect this because the same layout was used for both entries during the install.

The fix was a reinstall with a password containing only letters (a-z, A-Z) and digits (0-9). Those characters sit in the same position on nearly every keyboard layout, so the password types out identically regardless of origin.

**Takeaway:** for installer prompts in a browser console, or for virtual consoles that handle their own keyboard translation, pick a layout-independent password. That means alphanumerics only, no special characters. The entropy loss is compensated by extra length. A twenty-character password with only letters and digits is stronger than a twelve-character one with special characters you cannot reliably type.

## Proxmox VMs boot back into the installer after first install

The default boot order of a freshly created VM in Proxmox is `ide2;scsi0`, where `ide2` is the CDROM and `scsi0` is the OS disk. That is fine for the first boot (because then the installer comes off the CDROM), but not for the second. After a successful install I rebooted the VM through the installer's "reboot" option, and the same installer came back up because the boot order still started with CDROM.

Proxmox does not detect this automatically. The installer writes the system to `/dev/sda`, reports that installation is complete, and reboots. On the next boot, BIOS reaches for `ide2` because it comes first in the list, sees the ISO still mounted in the CDROM slot, and starts the installer menu again.

The fix is two steps after a successful install: change the boot order to `scsi0` only (or remove the CDROM from the order), and detach the ISO so that an explicit F2 boot to CDROM is no longer possible either. Both via `qm set`:

```
qm set <vmid> --boot order='scsi0'
qm set <vmid> --ide2 none,media=cdrom
```

**Takeaway:** in Proxmox, post-install configuration of a VM is as important as the installation itself. A standard checklist for every new VM should at minimum include: boot order to disk-only, ISO detach, `onboot=1` if production, `qemu-guest-agent` enabled in VM options, and a post-install snapshot before the first workload lands on it.

## Stale SSH host keys block ssh-copy-id on reinstalls

After a PBS reinstall, `ssh-copy-id` failed with `REMOTE HOST IDENTIFICATION HAS CHANGED`. The previous install had generated host keys and left an entry in `~/.ssh/known_hosts`. The reinstall generated new host keys. SSH refused to connect because the fingerprint did not match what it had stored.

That is exactly the right behaviour. A changed host key could be a legitimate reinstall, but it could also be a man-in-the-middle. SSH picks the safe default: block until the user confirms what happened.

The fix is `ssh-keygen -R <hostname-or-ip>` to remove the old entry, followed by a new `ssh-copy-id` attempt that accepts the new host key and installs the public key.

```
ssh-keygen -R 10.0.10.<pbs-ip>
ssh-copy-id root@10.0.10.<pbs-ip>
```

**Takeaway:** on every reinstall of a host reached through key-based auth, `ssh-keygen -R` is the first step before trying to connect again. This belongs in a mental checklist for post-reinstall operations, alongside "note new cert fingerprint" and "verify first successful login".

## Debian deb822 sources need a rename to disable, not a comment hack

For older `.list`-format files in `sources.list.d`, prefixing the single line with a `#` works fine to deactivate the whole repo. For the newer `.sources` format (deb822-style, default since Debian 12) it does not. These files are structured stanzas with `Types:`, `URIs:`, `Suites:` and `Components:` on separate lines. Commenting out only the `Types:` line leaves the file invalid instead of disabled, because the other lines are still active but no longer form a valid stanza.

The manifestation was apt returning `Malformed stanza 1` on the pbs-enterprise.sources file after I had commented out the `Types:` line. apt refused to run any update until the file was syntactically valid again.

The solution is a rename to something apt does not read, for example `.sources.disabled`:

```
mv /etc/apt/sources.list.d/pbs-enterprise.sources /etc/apt/sources.list.d/pbs-enterprise.sources.disabled
```

Alternative: delete the whole file if you know you will never need it again. A rename is less destructive because it leaves room for a later re-enable without retyping the content.

**Takeaway:** check the format of the source file before editing it. `.list`-format uses `#` for comments, `.sources`-format needs rename or delete. An `Enabled: false` field does not exist in deb822, so that does not work either.

## Circular dependency when PBS runs as a VM on the hypervisor

Running PBS as a VM on a PVE host that it itself backs up introduces a circular dependency. The PBS VM contains the datastore with all the other backups. If you include it in a PBS-side backup job, its backup sits inside itself, which is not recoverable if the VM itself is damaged.

The first instinct is to let the PBS VM run along in the `weekly-backup` job. That works until the day you need it. That day you discover the recovery flow is: start PBS to read the backup of PBS to restore PBS. That does not work.

The solution is a second vzdump job with a different scope and a different target. The production job writes to PBS and excludes VM 180. A separate job backs up VM 180 only and writes to the direct SATA directory (the same bulk disk, but through the old vzdump flow, not through PBS). The two paths share physical hardware but are independent at the application layer: a broken PBS process does not break the SATA directory backup.

**Takeaway:** as soon as a service is both the producer and the consumer of its own backup path, an alternative path must exist that does not require that service. This is not unique to PBS. The same pattern applies to a database that stores its own backups inside its own tables, a log aggregator that only writes into its own logs, or a secrets vault whose recovery key is held inside the vault. The pattern is always the same: the recovery route must be physically and logically independent of whatever is being recovered.

## Uptime Kuma 2.x removed status page password protection

In Uptime Kuma v1.x, a public status page could be protected with a simple password. Paste it in, share it with whoever needs access, done. The feature disappeared in v2.x. The status pages in v2 are either public (no auth at all) or accessed through the admin panel (which requires a user login plus 2FA).

I planned to run two status pages: one public with curated monitors, one internal with everything behind a password. The second page is no longer possible without external tools. Cloudflare Access would work for a browser, but it breaks native apps that cannot handle the Access login redirect, and the ntfy iOS app is one of them. For the homelab, the internal status page became "the admin dashboard after login", which is functionally the same thing minus a custom page layout.

**Takeaway:** before planning a feature, verify it still exists in the version you are running. Major version bumps quietly drop features more often than changelogs advertise. For Uptime Kuma specifically, v2 is a substantial rewrite and several v1 conveniences are gone.
