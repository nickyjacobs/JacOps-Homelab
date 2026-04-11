# Zone-based firewall

🇳🇱 Nederlands | 🇬🇧 [English](03-zone-firewall.md)

Dit document beschrijft hoe de VLANs uit [02-vlan-segmentation.nl.md](02-vlan-segmentation.nl.md) zijn gegroepeerd in zones, en welk verkeer de zonegrenzen mag oversteken.

## Waarom zones en niet per-VLAN regels

Regel-gebaseerde firewalls worden snel onleesbaar. Tien VLANs staat gelijk aan honderd directionele regelparen, en elk nieuw VLAN vermenigvuldigt het werk. Zones draaien het model om. Je groepeert VLANs op vertrouwensniveau en doel, en schrijft vervolgens regels tussen zones in plaats van tussen VLANs. Een nieuw VLAN toevoegen betekent het in de juiste zone droppen en de bestaande regels erven.

Moderne UniFi ondersteunt zone-based firewalling native. Custom zones zijn standaard deny-all naar elkaar, en dat is precies wat ik wil.

## Zone matrix in één oogopslag

![Zone-based firewall matrix](diagrams/zone-matrix.svg)

## Zone-indeling

| Zone | Bevat | Vertrouwensniveau |
|------|-------|-------------------|
| Mgmt | Management VLAN | Hoog, alleen mijn beheerapparaat |
| Servers | Servers VLAN | Hoog, hypervisor management |
| Apps | Apps VLAN | Gemiddeld, applicatie-workloads |
| SOC | Blue Team VLAN | Hoog, defensieve tooling |
| Lab | Lab VLAN | Niet vertrouwd, bewust |
| IoT | IoT VLAN | Niet vertrouwd, langlevende apparaten |
| Hotspot (ingebouwd) | Guest VLAN | Niet vertrouwd, bezoekers |
| External (ingebouwd) | Internet | Niet vertrouwd |
| VPN (ingebouwd) | Remote clients | Hoog na authenticatie |

Elke custom zone staat standaard op deny-all naar elke andere custom zone. Dat is precies de reden om ze uit de standaard `Internal` zone te halen.

## Allow-regels

De regels hieronder openen alleen wat een dienst daadwerkelijk nodig heeft. Elke regel heeft een reden-kolom, zodat een toekomstige ik kan beoordelen of de regel nog nuttig is.

### Vanuit Mgmt

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| Servers | TCP 8006 | Proxmox web UI |
| Servers | TCP 22, ICMP | SSH en ping voor troubleshooting |
| Apps | Any | Volledige toegang voor beheer |
| SOC | Any | Volledige toegang voor defensieve tooling |
| Lab | Any | Volledige toegang om labmachines te beheren |
| IoT | Any | Smart home bediening vanaf het beheerapparaat |
| External | Any | Normale internettoegang |

### Vanuit Servers

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| Apps | Any | Container management dat met app-containers praat |
| External | Any | Package updates, image pulls, NTP |

### Vanuit Apps

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| External | Any | Uitgaande webhooks en API calls |
| Mgmt | ICMP echo request | Uptime Kuma ping probes naar netwerkhardware (switch, access point) |
| Servers | TCP 8006 | Uptime Kuma keyword checks op de Proxmox web UI |

### Vanuit SOC

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| External | Any | Threat feeds, updates |

### Vanuit Lab

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| External | TCP 443 | HTTPS voor package downloads en browsen |
| External | UDP 53 | DNS |

Kijk wat Lab **niet** krijgt: geen ICMP naar buiten, geen willekeurige uitgaande poorten, geen toegang tot welke interne zone dan ook. Dat is de hele reden dat de Lab-zone bestaat.

### Vanuit IoT

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| External | Any | Clouddiensten waar smart devices van afhankelijk zijn |

### Vanuit VPN

| Naar | Protocol en poort | Reden |
|------|-------------------|-------|
| Mgmt | Any | Beheerwerk vanaf afstand |
| Servers | Any | Hypervisor management vanaf afstand |
| Apps | Any | App-beheer vanaf afstand |
| External | Any | Full tunnel clients routen al het verkeer naar buiten |

VPN-clients krijgen bewust een subset. Geen toegang tot SOC, Lab of IoT. Lekt er een VPN-credential, dan blijft de blast radius beperkt tot de zones waar een beheerder tijdens normaal werk aankomt.

## Wat de regels expliciet niet doen

**Geen regel van Lab naar welke interne zone dan ook.** Lab is eenrichtingsverkeer. Verkeer dat vanaf een labmachine wordt geïnitieerd, kan niet bij Mgmt, Servers, Apps of SOC. Stateful retourverkeer van een beheersessie die vanuit Mgmt is gestart, mag nog wel, omdat de ingebouwde regel voor retourverkeer dat afhandelt.

**Geen regel van IoT naar welke interne zone dan ook.** Zelfde patroon. IoT-apparaten praten met hun vendor cloud, en verder niets.

**Geen regel van Servers of Apps naar Mgmt.** De Proxmox-hosts en hun workloads hoeven geen verbindingen terug het management-netwerk in te initiëren. Als ze dat wel deden, zou ik eerst uitzoeken wat er iets naar buiten probeert te trekken voordat ik een regel toevoeg.

## Het model testen

Na het toepassen van de regels bevestigt een korte testlijst dat het model klopt.

- Beheerapparaat kan de Proxmox web UI openen: toegestaan.
- Beheerapparaat kan een willekeurige website openen: toegestaan.
- Labmachine kan een website openen via HTTPS: toegestaan.
- Labmachine kan de Proxmox-host pingen: geblokkeerd.
- Labmachine kan de Proxmox web UI openen: geblokkeerd.
- IoT-apparaat kan zijn clouddienst bereiken: toegestaan.
- IoT-apparaat kan het beheerapparaat direct bereiken: geblokkeerd.

De laatste twee zijn de eerlijke test van het model. Werkt een van de `geblokkeerd`-regels wél, dan klopt er iets niet aan de zonetoewijzing of de volgorde van de regels.

## Wat komt hierna

Met het verkeer tussen zones onder controle voegt het [WireGuard-document](04-wireguard-vpn.nl.md) een veilige remote route toe naar de high-trust zones, zonder iets open te zetten naar het publieke internet.
