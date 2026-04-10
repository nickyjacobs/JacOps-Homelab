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
