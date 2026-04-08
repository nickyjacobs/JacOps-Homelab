# Architectuur

🇬🇧 [English](01-architecture.md) | 🇳🇱 Nederlands

Dit document beschrijft de fysieke en logische basis van het homelab. Alle andere netwerkdocs bouwen voort op de concepten die hier vastgelegd staan.

## Doelen

Het homelab moet vier doelen tegelijk halen.

1. **Leren en oefenen.** Het dient als lab voor offensive en defensive security werk, dus verkeer van kwetsbare machines moet afgeschermd blijven.
2. **Echte services draaien.** Workflow automation, monitoring en een handvol self-hosted tools draaien hier en moeten bereikbaar blijven.
3. **Reproduceerbaar zijn.** Ik moet de hele boel kunnen afbreken en vanuit documentatie opnieuw opbouwen zonder te gokken.
4. **Veilig falen.** Een gecompromitteerd IoT device of lab-VM mag niets belangrijks raken.

Deze doelen sturen elke ontwerpkeuze hieronder.

## Hardware

| Rol | Apparaat | Opmerkingen |
|-----|----------|-------------|
| Gateway en firewall | UniFi Cloud Gateway Ultra | Routing, zone-based firewall, IPS, VPN |
| Switch | UniFi USW-Lite-8-PoE | 8 poorten, PoE voor het accesspoint |
| Accesspoint | UniFi U6 Pro | WiFi 6, bekabelde backhaul |
| Hypervisor node 1 | Proxmox VE 9.x, 6 core, 16 GB RAM | Draait het meeste werk |
| Hypervisor node 2 | Proxmox VE 9.x, 4 core, 16 GB RAM | Clusterpartner, Windows lab |
| Uplink | Consumentenglasvezel, PPPoE, dynamisch publiek IP | DDNS vangt het dynamische deel op |

Het cluster heeft twee nodes. Dat is genoeg om clusterconcepten te oefenen (quorum, migratie, corosync) zonder de kosten van een derde machine. Voor services die tijdens node-onderhoud bereikbaar moeten blijven leg ik handmatige failover vast in plaats van te doen alsof ik echte HA heb.

## Fysieke topologie

```
            Internet (PPPoE)
                  │
         ┌────────┴────────┐
         │  Cloud Gateway  │  routing, firewall, VPN, IPS
         └────────┬────────┘
                  │ trunk
         ┌────────┴────────┐
         │      Switch     │  8 poorts PoE, VLAN aware
         └─┬──────┬──────┬─┘
           │      │      │
           │      │      └── Accesspoint (WiFi 6)
           │      │
           │      └── Proxmox node 2 (trunk)
           │
           └── Proxmox node 1 (trunk)
```

Beide Proxmox nodes hangen als trunkpoort aan de switch. De bridge op elke hypervisor is VLAN aware, dus elk VLAN kan op elke VM of container landen zonder dat ik de switch aanraak.

## Logische lagen

Het netwerk valt uiteen in vier logische lagen, elk met een eigen doel en vertrouwensniveau.

**Management.** De infrastructuur zelf. Gateway, switch, accesspoint en mijn eigen admin device. Meer hoort hier niet.

**Servers.** De Proxmox hypervisors en hun managementinterfaces. Behandeld als infrastructuur, niet als applicatiewerk.

**Apps.** Applicatiewerk dat bereikbaar moet zijn vanuit de rest van het netwerk en selectief vanuit het internet. Losgekoppeld van de hypervisors zodat compromis van een app geen compromis van het platform betekent.

**Lab en IoT.** Standaard niet vertrouwd. Lab is voor offensive security oefeningen en bewust kwetsbare targets. IoT bevat smart home apparaten die ik niet volledig vertrouw. Beide mogen het internet op. Geen van beide mag iets anders bereiken zonder expliciete regel.

De concrete VLAN nummering, subnetten en DHCP staan in [02-vlan-segmentation.md](02-vlan-segmentation.nl.md).

## Ontwerpprincipes

Vier principes kleuren de rest van de documentatie.

**Segmenteer op basis van doel, niet op basis van gemak.** Werk in hetzelfde VLAN zetten omdat het een klik scheelt, kost je later isolatie. Elk workload krijgt het VLAN dat bij het vertrouwensniveau past, ook als dat meer VLANs betekent.

**Standaard dicht.** Elke custom zone begint als deny-all. Allow rules openen alleen het verkeer dat een service daadwerkelijk nodig heeft, met een korte toelichting waarom. Als niemand nog weet waarom een regel bestaat, gaat die eruit.

**Least privilege voor remote access.** VPN gebruikers krijgen niet het hele netwerk. Ze krijgen de subset die past bij wat ze komen doen. Lab en IoT blijven onbereikbaar ook als ik via de VPN werk.

**Leg de redenering vast, niet alleen het resultaat.** Een configsnippet zonder context is over zes maanden waardeloos. Elke keuze krijgt een korte alinea over de afweging.

## Wat je in de andere docs vindt

- [02-vlan-segmentation.nl.md](02-vlan-segmentation.nl.md) vertaalt de logische lagen hierboven naar echte VLANs, subnetten en switchport profielen.
- [03-zone-firewall.nl.md](03-zone-firewall.nl.md) bouwt het zone model boven op de VLANs en somt elke custom allow regel op.
- [04-wireguard-vpn.nl.md](04-wireguard-vpn.nl.md) behandelt remote access, DDNS en de afweging tussen split en full tunnel.
- [05-cybersecurity-hardening.nl.md](05-cybersecurity-hardening.nl.md) verzamelt de hardeningstappen die niet in de andere categorieën passen: IPS tuning, WiFi hardening, encrypted DNS, honeypots.

Een visuele versie van de topologie en het zone model staat in [diagrams/](diagrams/).
