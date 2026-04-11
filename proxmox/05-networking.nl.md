# Networking

🇬🇧 [English](05-networking.md) | 🇳🇱 Nederlands

Dit document beschrijft de netwerkconfiguratie op de Proxmox-hypervisors zelf. Het sluit aan op de bredere netwerkarchitectuur uit de [network-sectie](../network/), maar beperkt zich tot de laag die de hypervisor kant raakt: de VLAN-aware bridge, de tagged sub-interface voor hostverkeer, corosync-transport en hoe VMs en containers op het juiste VLAN terechtkomen.

## Uitgangspunt

De VLANs, zones en allow-regels staan volledig beschreven in [02-vlan-segmentation.nl.md](../network/02-vlan-segmentation.nl.md) en [03-zone-firewall.nl.md](../network/03-zone-firewall.nl.md). Wat die documenten niet uitleggen, is hoe Proxmox concreet verkeer op de juiste VLAN zet. Elk VM of LXC-container is uiteindelijk een veth-pair die aan een bridge hangt, en die bridge moet precies goed ingesteld staan anders belandt een container met VLAN-tag 40 in het verkeerde broadcast domain zonder duidelijke foutmelding.

Er is één bridge per node, `vmbr0`, en één uplink. Beide nodes zijn als trunk-port aangesloten op de UniFi switch, met Management VLAN als untagged en alle andere VLANs tagged. Alle segmentatie gebeurt op de bridge, niet op de switch.

## De bridge

Elke node heeft dezelfde bridge-configuratie in `/etc/network/interfaces`:

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

Drie keuzes in deze configuratie verdienen uitleg.

**`bridge-vlan-aware yes`** is de instelling die alles mogelijk maakt. Zonder deze vlag is `vmbr0` een gewone Linux-bridge die VLAN-tags of volledig doorlaat of volledig strippt, afhankelijk van hoe je tagging ervoor doet. Met de vlag aan, wordt de bridge VLAN-aware: per interface op de bridge kan een VLAN-tag ingesteld worden, en de bridge zorgt dat verkeer met die tag op de uplink verschijnt. Geen aparte sub-bridges per VLAN nodig.

**`bridge-vids 2-4094`** zegt tegen de bridge welke VLAN-IDs doorgelaten mogen worden op het trunk-poort. 2-4094 is effectief "alles behalve VLAN 1 native", maar in deze setup is dat juist wat we willen, want Management loopt untagged en wordt door de switchport-config afgehandeld, niet door de bridge.

**`vmbr0.10`** is een tagged sub-interface die de hypervisor zelf aan VLAN 10 koppelt. Dat is de management-interface van de host, niet van zijn guests. De keuze om hier een tagged sub-interface te gebruiken in plaats van `vmbr0` zelf een IP-adres te geven, staat uitgelegd in [decisions.nl.md](../docs/decisions.nl.md) onder "Proxmox hosts op een tagged sub-interface". Kort: het houdt hostverkeer en guestverkeer op dezelfde expliciete VLAN, zonder dat een native-VLAN-inconsistentie tussen switchport en bridge ontstaat.

## VLAN-tagging per VM en container

Met een VLAN-aware bridge op z'n plek, komt de VLAN-toewijzing per guest uit de VM- of container-config.

**Voor een VM** ziet de relevante regel in de config eruit als:

```
net0: virtio=BC:24:11:XX:XX:XX,bridge=vmbr0,tag=40,firewall=1
```

De `tag=40` zet het verkeer van deze VM op VLAN 40 (Apps). Vanuit de guest is er niets te zien van tagging: de guest ziet een gewone ethernet-interface en weet niet dat de hypervisor er een VLAN-label op plakt voordat het op de bridge komt. Omgekeerd pakt de bridge inkomend verkeer met tag 40 en levert het af bij de VM met de tag eraf gestript.

**Voor een LXC-container** staat het in de network-sectie van de config:

```
net0: name=eth0,bridge=vmbr0,firewall=1,gw=10.0.40.1,hwaddr=BC:24:11:XX:XX:XX,ip=10.0.40.<ct-ip>/24,tag=40,type=veth
```

De `tag=40` doet hier hetzelfde werk. Containers krijgen via `ip=` direct een statisch adres toegewezen omdat DHCP-discovery in een container-rootfs niet altijd voorspelbaar werkt, en omdat statische adressen het makkelijker maken om firewallregels op te bouwen rond specifieke workloads.

Het `firewall=1`-attribuut op beide voorbeelden activeert de per-guest Proxmox firewall op die interface, en is een van de lagen die in de volgende sectie worden behandeld.

## Drie firewall-lagen

Als een pakket vanuit het netwerk een workload probeert te bereiken op deze cluster, passeert het tot drie Proxmox-lagen voordat het de guest bereikt. Elke laag kan onafhankelijk dropppen.

```
Internet / andere VLANs
        │
        ▼
  UniFi zone firewall       ← [03-zone-firewall.nl.md] (network laag, niet Proxmox)
        │
        ▼
  Proxmox cluster firewall  ← cluster-wide defaults
        │
        ▼
  Proxmox host firewall     ← per-node, [02-hardening.nl.md] Fase 4
        │
        ▼
  Proxmox guest firewall    ← per-VM of per-CT via `firewall=1`
        │
        ▼
   VM of container
```

De cluster-wide firewall heet in Proxmox gewoon "datacenter firewall" en dekt alle nodes tegelijk. Die staat hier ingesteld op inbound-policy `DROP` met uitzonderingen voor corosync-verkeer tussen de nodes, SSH-beheer vanuit Management en de Proxmox web UI. De exacte regels staan in [02-hardening.nl.md](02-hardening.nl.md) onder Fase 4.

De host-level firewall is een tweede laag die op elke node apart draait. Die regel-set is doelbewust een subset van wat de cluster-firewall al doet, zodat als iemand per ongeluk de datacenter-regels verbrokkelt, er nog steeds iets drop-by-default op node-niveau staat.

De guest-level firewall is de derde laag, die actief wordt door `firewall=1` op de netwerkinterface van de VM of container. Per guest kun je daarna IN- en OUT-regels definieren in `/etc/pve/firewall/<vmid>.fw`, die alleen gelden voor die ene workload. In deze setup wordt die laag nog niet breed gebruikt, omdat de zone-firewall op het netwerk en de host-level firewall samen al het meeste afdekken. Het blijft wel aanstaan zodat de laag klaarligt wanneer een workload het nodig heeft.

## Corosync-verkeer

Het cluster heeft twee nodes die met elkaar moeten praten voor state-synchronisatie. Corosync handelt dat af via een secure multicast-achtig protocol (knet), dat in de config is vastgelegd aan de Servers VLAN:

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

De `ring0_addr`-waarden zijn management-adressen op VLAN 10, exact dezelfde interfaces die `vmbr0.10` uit de vorige sectie oplevert. Dat betekent dat de cluster-state over de Servers zone loopt, wat de zone-firewall expliciet toestaat voor inter-node verkeer.

Er is bewust geen tweede ring (`ring1_addr`). Twee ringen zouden fysieke redundantie bieden, maar dat vraagt een tweede NIC op beide nodes waar de uplink naartoe gaat. Die is hier niet. Bij verlies van de enige uplink op een node valt die node offline, maar de andere node blijft draaien met een degraded quorum (zie cluster-setup).

## VM- en containerplaatsing versus netwerk

De placement-tabel in [01-cluster-setup.nl.md](01-cluster-setup.nl.md) koppelt elke guest aan een node en een VLAN. Die koppeling is niet willekeurig:

| Type workload | Node | VLAN | Waarom |
|---------------|------|------|--------|
| Always-on applicatie (n8n, monitoring) | Node 1 | Apps (40) | Node 1 heeft meer cores en bulk-storage, Apps is de applicatiezone |
| Foundation services (Vaultwarden, Forgejo, Miniflux) | Node 1 | Servers (10) | Worden gelijkgesteld met hypervisor-niveau infrastructuur, zie [roadmap.nl.md](../docs/roadmap.nl.md) |
| PBS | Node 1 | Servers (10) | Backup-server staat in dezelfde zone als de hosts die hij beschermt |
| Forgejo runner | Node 2 | Apps (40) | Workload-spreiding naar Node 2, runner is applicatie-scope |
| Lab-VMs (Windows, DVWA, Metasploitable) | Node 2 | Lab (30) | Lab-zone is geisoleerd, Node 2 draait alleen als sessie actief is |

De foundation-services op Servers VLAN is een belangrijke keuze die consistentie geeft met de PBS-plaatsing. Een infrastructuur-credential vault hoort logisch dichter bij de hosts dan bij de applicatie-workloads. De Apps zone blijft daardoor alleen voor daadwerkelijke applicaties die de credentials gebruiken.

## DNS en resolvers

Alle VMs en containers krijgen de UniFi Cloud Gateway (10.0.1.1) als primary resolver via DHCP of via hun statische config. De gateway stuurt queries door naar een upstream DNS-over-TLS provider. De keuze voor de upstream staat in [05-cybersecurity-hardening.nl.md](../network/05-cybersecurity-hardening.nl.md).

Voor intern gebruik binnen het homelab bestaat een lokale zone `jacops.local`. Die wordt nog niet op DNS-niveau beheerd, maar komt er zodra Vaultwarden binnen is: een intern CNAME-systeem voor `vault.jacops.local`, `forgejo.jacops.local`, `miniflux.jacops.local` en vergelijkbare names. Tot die tijd zijn de services alleen via hun container-IP's bereikbaar, wat operationeel prima werkt.

## Troubleshooting

De meest voorkomende foutmodi bij deze opzet hebben een vaste volgorde voor diagnose.

**Container heeft geen netwerk na aanmaken.**
Check eerst of `bridge-vlan-aware yes` echt aan staat op de bridge met `ip -d link show vmbr0`. De uitvoer moet `vlan_filtering 1` bevatten. Is dat niet het geval, dan is de bridge geen VLAN-aware en strippt alle tagging. Herstart de netwerk-stack of de hele node om het weer op te halen.

**Container heeft netwerk maar kan de gateway niet pingen.**
Controleer de VLAN-tag in de container-config (`pct config <vmid>` of `cat /etc/pve/lxc/<vmid>.conf`) en vergelijk met de juiste VLAN. Een verkeerde tag plaatst de container in een broadcast domain waar zijn gateway niet bestaat.

**VM op het juiste VLAN maar kan een specifieke andere dienst niet bereiken.**
Drie lagen kunnen de oorzaak zijn: de UniFi zone-firewall, de Proxmox cluster/host firewall, en de per-guest firewall. Werk ze in volgorde af. Vanaf de PVE-host `iptables -L -n | grep <zone-regel>` laat zien of de host-level laag de drop veroorzaakt. De zone-firewall is alleen in de UniFi UI in te zien.

**Twee containers op hetzelfde VLAN kunnen elkaar niet bereiken.**
Dit is bijna altijd de per-guest firewall. Default deny op een container-interface blokkeert ook verkeer van buren. Zet `firewall=0` tijdelijk om het te bevestigen, en als dat het probleem oplost, voeg dan een expliciete regel toe in `/etc/pve/firewall/<vmid>.fw` die het inter-container verkeer toestaat.

## Resultaat

De Proxmox-netwerklaag levert:

1. **Een enkele bridge per node** die VLAN-aware is, met alle VLANs bereikbaar zonder per-VLAN sub-bridges.
2. **Tagged sub-interfaces** voor het hostverkeer zelf, consistent met hoe guests ook tagged zijn.
3. **Drie opeenvolgende firewall-lagen** (cluster, host, guest) bovenop de externe zone-firewall uit de network-sectie, elk deny-by-default.
4. **Corosync over het Servers VLAN**, expliciet toegestaan en daardoor niet per ongeluk te breken door een nieuwe zone-regel.

Deze configuratie is het Proxmox-eind van de keten. De network-documenten in [../network/](../network/) beschrijven wat daarboven zit: welke VLANs bestaan, welke zones ze krijgen, welke remote access er is via WireGuard. De twee lagen samen vormen een gesegmenteerd netwerk waar elke deploy zijn plek weet en geen laag stilletjes kan worden overgeslagen.
