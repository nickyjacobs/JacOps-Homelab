# Networking

🇬🇧 English | 🇳🇱 [Nederlands](05-networking.nl.md)

This document describes the network configuration on the Proxmox hypervisors themselves. It connects to the wider network architecture in the [network section](../network/), but limits itself to the layer that touches the hypervisor side: the VLAN-aware bridge, the tagged sub-interface for host traffic, corosync transport, and how VMs and containers land on the right VLAN.

## Starting point

The VLANs, zones, and allow rules are fully described in [02-vlan-segmentation.md](../network/02-vlan-segmentation.md) and [03-zone-firewall.md](../network/03-zone-firewall.md). What those documents do not explain is how Proxmox concretely places traffic on the right VLAN. Every VM or LXC container is ultimately a veth pair attached to a bridge, and that bridge has to be configured exactly right or a container with VLAN tag 40 ends up in the wrong broadcast domain without a clear error.

There is one bridge per node, `vmbr0`, and one uplink. Both nodes connect to the UniFi switch as trunk ports, with the Management VLAN as untagged and all other VLANs tagged. All segmentation happens on the bridge, not on the switch.

## The bridge

Each node has the same bridge configuration in `/etc/network/interfaces`:

```
auto vmbr0
iface vmbr0 inet manual
        bridge-ports eno1
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094

auto vmbr0.10
iface vmbr0.10 inet static
        address 10.0.10.<node-ip>/24
        gateway 10.0.10.1
```

Three choices in this configuration deserve explanation.

**`bridge-vlan-aware yes`** is the setting that makes everything work. Without this flag, `vmbr0` is a plain Linux bridge that either fully passes through VLAN tags or fully strips them, depending on how tagging was set up upstream. With the flag on, the bridge becomes VLAN-aware: each interface on the bridge can be given its own VLAN tag, and the bridge ensures traffic with that tag appears on the uplink. No separate sub-bridges per VLAN needed.

**`bridge-vids 2-4094`** tells the bridge which VLAN IDs are allowed on the trunk port. 2-4094 is effectively "everything except the native VLAN 1", which in this setup is what we want, because Management runs untagged and is handled by the switchport configuration, not by the bridge.

**`vmbr0.10`** is a tagged sub-interface that connects the hypervisor itself to VLAN 10. This is the host's management interface, not its guests'. The decision to use a tagged sub-interface here instead of giving `vmbr0` an IP address directly is explained in [decisions.md](../docs/decisions.md) under "Proxmox hosts on a tagged sub-interface". Short version: it keeps host traffic and guest traffic on the same explicit VLAN, without creating a native-VLAN inconsistency between switchport and bridge.

## VLAN tagging per VM and container

With a VLAN-aware bridge in place, VLAN assignment per guest comes from the VM or container config.

**For a VM**, the relevant line in the config looks like:

```
net0: virtio=BC:24:11:XX:XX:XX,bridge=vmbr0,tag=40,firewall=1
```

The `tag=40` places this VM's traffic on VLAN 40 (Apps). From inside the guest, tagging is invisible: the guest sees a regular ethernet interface and does not know that the hypervisor attaches a VLAN label before traffic reaches the bridge. Going the other way, the bridge takes inbound traffic with tag 40 and delivers it to the VM with the tag stripped.

**For an LXC container**, the setting lives in the network section of the config:

```
net0: name=eth0,bridge=vmbr0,firewall=1,gw=10.0.40.1,hwaddr=BC:24:11:XX:XX:XX,ip=10.0.40.<ct-ip>/24,tag=40,type=veth
```

The `tag=40` does the same work here. Containers get a static address assigned directly through `ip=` because DHCP discovery inside a container rootfs is not always predictable, and because static addresses make it easier to build firewall rules around specific workloads.

The `firewall=1` attribute in both examples activates the per-guest Proxmox firewall on that interface, one of the layers covered in the next section.

## Three firewall layers

If a packet from the network tries to reach a workload on this cluster, it passes up to three Proxmox layers before it reaches the guest. Each layer can drop independently.

```
Internet / other VLANs
        │
        ▼
  UniFi zone firewall       ← [03-zone-firewall.md] (network layer, not Proxmox)
        │
        ▼
  Proxmox cluster firewall  ← cluster-wide defaults
        │
        ▼
  Proxmox host firewall     ← per-node, [02-hardening.md] Phase 4
        │
        ▼
  Proxmox guest firewall    ← per-VM or per-CT via `firewall=1`
        │
        ▼
   VM or container
```

The cluster-wide firewall is called "datacenter firewall" in Proxmox and covers all nodes at once. It is set here to an inbound policy of `DROP` with exceptions for corosync traffic between the nodes, SSH management from Management, and the Proxmox web UI. The exact rules live in [02-hardening.md](02-hardening.md) under Phase 4.

The host-level firewall is a second layer that runs on each node separately. That rule set is deliberately a subset of what the cluster firewall already does, so that if someone accidentally breaks the datacenter rules, there is still a drop-by-default layer at the node level.

The guest-level firewall is the third layer, activated by `firewall=1` on a VM or container's network interface. Per guest you can then define IN and OUT rules in `/etc/pve/firewall/<vmid>.fw` that apply only to that workload. This layer is not used broadly in this setup yet, because the network zone firewall and the host-level firewall together already cover most needs. It stays enabled so the layer is ready when a workload requires it.

## Corosync traffic

The cluster has two nodes that must talk to each other for state synchronization. Corosync handles this through a secure multicast-like protocol (knet), which the config binds to the Servers VLAN:

```
# /etc/pve/corosync.conf
nodelist {
  node {
    name: srv-01
    nodeid: 1
    quorum_votes: 1
    ring0_addr: 10.0.10.<node1-ip>
  }
  node {
    name: srv-02
    nodeid: 2
    quorum_votes: 1
    ring0_addr: 10.0.10.<node2-ip>
  }
}
```

The `ring0_addr` values are management addresses on VLAN 10, the same interfaces `vmbr0.10` creates in the previous section. That means cluster state flows over the Servers zone, which the zone firewall explicitly allows for inter-node traffic.

There is deliberately no second ring (`ring1_addr`). Two rings would provide physical redundancy, but that requires a second NIC on both nodes for the uplink to feed. That is not present here. On loss of the single uplink on a node, that node falls offline, but the other node keeps running with a degraded quorum (see cluster-setup).

## VM and container placement versus network

The placement table in [01-cluster-setup.md](01-cluster-setup.md) ties every guest to a node and a VLAN. That tie is not arbitrary:

| Workload type | Node | VLAN | Why |
|---------------|------|------|-----|
| Always-on application (n8n, monitoring) | Node 1 | Apps (40) | Node 1 has more cores and bulk storage, Apps is the application zone |
| Foundation services (Vaultwarden, Forgejo, Miniflux) | Node 1 | Servers (10) | Treated as hypervisor-level infrastructure, see [roadmap.md](../docs/roadmap.md) |
| PBS | Node 1 | Servers (10) | Backup server sits in the same zone as the hosts it protects |
| Forgejo runner | Node 2 | Apps (40) | Workload spread to Node 2, runner is application scope |
| Lab VMs (Windows, DVWA, Metasploitable) | Node 2 | Lab (30) | Lab zone is isolated, Node 2 only runs when a session is active |

Placing foundation services on the Servers VLAN is a deliberate choice that keeps the PBS placement consistent. A credential vault for infrastructure logically lives closer to the hosts than to the application workloads. The Apps zone then stays reserved for actual applications that consume those credentials.

## DNS and resolvers

All VMs and containers get the UniFi Cloud Gateway (10.0.1.1) as their primary resolver through DHCP or static config. The gateway forwards queries to an upstream DNS-over-TLS provider. The choice of upstream is documented in [05-cybersecurity-hardening.md](../network/05-cybersecurity-hardening.md).

For internal use inside the homelab there is a local zone `jacops.local`. That zone is not yet managed on a DNS level, but will be once Vaultwarden comes online: an internal CNAME system for `vault.jacops.local`, `forgejo.jacops.local`, `miniflux.jacops.local`, and similar names. Until then, services are reachable through their container IPs, which works fine operationally.

## Troubleshooting

The most common failure modes in this setup have a fixed diagnosis order.

**Container has no network after creation.**
First check that `bridge-vlan-aware yes` is actually on for the bridge with `ip -d link show vmbr0`. The output should contain `vlan_filtering 1`. If not, the bridge is not VLAN-aware and is stripping all tags. Restart the network stack or the whole node to bring it back.

**Container has network but cannot ping the gateway.**
Check the VLAN tag in the container config (`pct config <vmid>` or `cat /etc/pve/lxc/<vmid>.conf`) and compare with the intended VLAN. A wrong tag places the container in a broadcast domain where its gateway does not exist.

**VM on the right VLAN but cannot reach a specific other service.**
Three layers can be the cause: the UniFi zone firewall, the Proxmox cluster/host firewall, and the per-guest firewall. Walk them in order. From the PVE host, `iptables -L -n | grep <zone-rule>` shows whether the host-level layer is the source of the drop. The zone firewall can only be inspected in the UniFi UI.

**Two containers on the same VLAN cannot reach each other.**
This is almost always the per-guest firewall. Default deny on a container interface also blocks neighbours. Temporarily set `firewall=0` to confirm it, and if that fixes it, add an explicit rule in `/etc/pve/firewall/<vmid>.fw` that allows the inter-container traffic.

## Result

The Proxmox network layer delivers:

1. **A single bridge per node** that is VLAN-aware, with all VLANs reachable without per-VLAN sub-bridges.
2. **Tagged sub-interfaces** for host traffic itself, consistent with how guests are tagged.
3. **Three successive firewall layers** (cluster, host, guest) on top of the external zone firewall from the network section, each deny-by-default.
4. **Corosync over the Servers VLAN**, explicitly allowed so it is not accidentally broken by a new zone rule.

This configuration is the Proxmox end of the chain. The network documents in [../network/](../network/) describe what sits above it: which VLANs exist, which zones they fall into, which remote access is provided by WireGuard. The two layers together form a segmented network where every deploy knows its place and no layer can be silently skipped.
