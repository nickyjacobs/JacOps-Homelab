# VLAN-segmentatie

🇳🇱 Nederlands | 🇬🇧 [English](02-vlan-segmentation.md)

Dit document zet de logische lagen uit [01-architecture.nl.md](01-architecture.nl.md) om naar echte VLANs, subnets en switchport-profielen.

## Regels voor naamgeving en nummering

Twee regels houden de VLAN-indeling over een jaar nog leesbaar.

**Het derde octet van het subnet is gelijk aan het VLAN-ID.** Zie je `10.0.20.0/24`, dan weet je zonder op te zoeken dat het op VLAN 20 draait. Boven de 255 werkt die regel niet meer, maar voor een thuisnetwerk is dat geen probleem.

**Namen beschrijven de rol, niet de techniek.** `Servers` leest beter dan `Proxmox_VLAN`. Vervang ik Proxmox volgend jaar door iets anders, dan wil ik niet het VLAN hoeven hernoemen.

## Indeling

| VLAN ID | Naam | Subnet | Doel |
|---------|------|--------|------|
| 1 | Management | 10.0.1.0/24 | Gateway, switch, access point, adminapparaat |
| 10 | Servers | 10.0.10.0/24 | Proxmox hypervisor management interfaces |
| 20 | Blue Team | 10.0.20.0/24 | Defensieve tooling (Wazuh, MISP, DFIR) |
| 30 | Lab | 10.0.30.0/24 | Offensieve oefeningen, kwetsbare targets |
| 40 | Apps | 10.0.40.0/24 | Applicatie-workloads (automation, dashboards) |
| 50 | Guest | 10.0.50.0/24 | Bezoekers, geïsoleerd van de rest |
| 100 | IoT | 10.0.100.0/24 | Smart home apparaten, standaard niet vertrouwd |

Het Management VLAN staat bewust op de standaard VLAN 1. Sommige UniFi-features gaan ervan uit dat managementverkeer untagged loopt, en daartegenin werken levert meer nadeel dan voordeel op.

## Waarom Servers en Apps gesplitst zijn

De hypervisors en de applicatie-workloads draaien op aparte VLANs, ook al zijn beide vertrouwde infrastructuur. De reden is blast radius.

Wordt een app overgenomen (via een openstaande webhook, een kwetsbare dependency, een verkeerd geconfigureerde reverse proxy), dan mag de aanvaller geen directe netwerktoegang hebben tot de Proxmox API op de host waar die container draait. Door Apps te scheiden van Servers betekent de compromittatie van een app niet automatisch de compromittatie van het platform.

De prijs zijn een paar extra firewallregels voor het managementverkeer dat de grens wél moet oversteken. Dat is een eerlijke ruil.

## Waarom Lab en IoT lijken, maar gescheiden blijven

Beide VLANs zijn niet vertrouwd. Beide mogen het internet op. Geen van beide mag ergens anders bij zonder expliciete regel. Toch krijgen ze ieder een eigen VLAN, om twee redenen.

Ten eerste staat er iets anders op. Lab bevat kortlevende machines waar ik actief op inhak. IoT bevat langlevende apparaten die ik gewoon wil laten werken. Gooi ik ze op één VLAN, dan loop ik bij elke snapshot of reset van een lab-VM het risico iets te raken dat mijn partner gebruikt.

Ten tweede gelden er andere remote access-regels. Lab is nooit bereikbaar via de VPN. IoT wel vanaf het beheerapparaat, omdat ik smart home apparaten vanaf mijn telefoon wil bedienen. Samen op één VLAN zou een van die regels uithollen.

## Switchport-profielen

Drie profielen dekken elke poort op de switch.

**Management access.** Untagged Management, geen getagde VLANs. Voor het beheerapparaat en alles dat geen andere netwerken hoeft te zien.

**IoT access.** Untagged IoT, geen getagde VLANs. Voor bedrade smart home apparaten.

**Trunk.** Untagged Management, alle andere VLANs getagd. Voor de Proxmox-nodes en het access point. Hier kan de VLAN-aware bridge op de hypervisor per VM een willekeurig VLAN kiezen.

Op papier bestaat er nog een vierde profiel voor Lab-only poorten, maar in de praktijk is elke lab-machine virtueel en hangt aan de Proxmox-trunk.

## DHCP en DNS

Elk VLAN draait zijn eigen DHCP-scope vanuit de gateway. De ranges zijn zo ingedeeld dat de eerste 20 adressen gereserveerd blijven voor statische toewijzingen (infrastructuur, honeypots, printers). Alles daarboven krijgt dynamische leases.

DNS loopt via de gateway, die doorstuurt naar een versleutelde upstream. Het [hardening-document](05-cybersecurity-hardening.nl.md) behandelt dat deel.

## WiFi mapping

Het access point zendt drie SSIDs uit. Elke SSID hangt aan één VLAN, dat houdt het voorspelbaar.

| SSID | VLAN | Beveiliging |
|------|------|-------------|
| M | Management | WPA2/WPA3 mixed, protected management frames |
| IoT | IoT | WPA2 only (sommige apparaten ondersteunen geen WPA3), alleen 2,4 GHz |
| Guest | Guest | WPA2/WPA3 mixed, client isolation aan |

Het Lab VLAN heeft bewust geen WiFi SSID. Labverkeer is alleen bedraad, dat maakt het lastiger om per ongeluk met een telefoon of laptop op het verkeerde netwerk te belanden.

## Wat komt hierna

Met de VLAN-indeling op z'n plek groepeert het [zone firewall document](03-zone-firewall.nl.md) deze VLANs in zones en beschrijft het de allow-regels die de zones met elkaar laten praten.
