# Cybersecurity hardening

🇬🇧 [English](05-cybersecurity-hardening.md) | 🇳🇱 Nederlands

De vorige documenten beschrijven de structurele controls: [VLAN-segmentatie](02-vlan-segmentation.nl.md), [zone-based firewallregels](03-zone-firewall.nl.md) en de [WireGuard VPN](04-wireguard-vpn.nl.md) voor remote toegang. Dit document behandelt de defensieve lagen daarbovenop. Op zichzelf is elke laag goedkoop en in isolatie zinloos. Opgestapeld verhogen ze de prijs van een geslaagde inbraak tot voorbij wat een doorsnee opportunistische aanvaller wil betalen.

## Threat model

Hardening zonder threat model wordt cargo culting. De homelab verdedigt zich tegen drie categorieën:

1. **Opportunistische internetscans.** Massascanners die de WAN raken, op zoek naar exposed admin panels, standaardwachtwoorden en bekende CVEs.
2. **Gecompromitteerde IoT- of labmachines.** Apparaten op niet-vertrouwde VLANs die overgenomen worden en intern proberen te pivoten of naar een C2 beaconen.
3. **Credential theft op endpoints.** Een gestolen laptop of een gephishte wachtwoord dat een aanvaller gebruikt om in te bellen.

Nation-state adversaries en targeted APTs vallen expliciet buiten scope. De controls hieronder stoppen geen gemotiveerde aanvaller met tijd en budget. Ze stoppen wel de achtergrondruis van het internet en leggen de lat hoger voor de middenmoot.

## Intrusion prevention

UniFi heeft een IPS-engine op basis van Suricata aan boord. Die draait op de gateway en inspecteert verkeer tussen zones en tussen zones en het internet.

| Setting | Waarde | Reden |
|---------|--------|-------|
| Modus | Detect and block | Blokkeren is de hele reden |
| Rule-categorieën | Critical, high, medium | Low-severity regels leveren ruis zonder waarde |
| Richting | WAN in, WAN out, intern | Vangt inbound scans én outbound beacons |
| Suppression-lijst | Een handvol bekende goede regels | Voorkomt dat Smart TV-verkeer de log volspamt |

IPS is de enige control die uitgaande activiteit uit de IoT- en Lab-zones vangt. De firewallregels in [03](03-zone-firewall.nl.md) zeggen dat IoT het internet op mag, maar niets over wat IoT daar zegt. IPS vult dat gat.

De suppression-lijst groeit naarmate er false positives opduiken. Elke suppression krijgt een opmerking met welk apparaat de trigger veroorzaakte en waarom het veilig is om te negeren. Blind suppressen is de snelste route naar een IPS die niets meer detecteert.

## GeoIP-filtering

Het meeste inbound scanverkeer komt uit een klein aantal bronlanden. Die regio's op de WAN blokkeren levert gratis throughput terug en een enorme reductie van logruis op.

De homelab blokkeert inbound verkeer uit elk land behalve Nederland en een korte allow-lijst met buurlanden. Outbound GeoIP staat uit. Gebruikers moeten diensten wereldwijd kunnen bereiken, en outbound bestemmingen per land blokkeren breekt meer dan het oplost.

Het WireGuard endpoint is de uitzondering die ertoe doet. Ben ik buiten de allow-lijst onderweg, dan kan de client `vpn.example.com` niet bereiken. Twee opties lossen dat op:

1. Tijdelijk het huidige land aan de allow-lijst toevoegen vanaf een vertrouwd apparaat voor vertrek.
2. De beperking accepteren en remote werk eromheen plannen.

Optie één is de praktische keuze. Een kort regeltje op de reischecklist herinnert me eraan om de lijst bij te werken voor het boarden.

## Versleutelde DNS

Plaintext DNS lekt elke hostname die een apparaat opvraagt. Die lek is zichtbaar voor de ISP en voor alles wat ertussen zit. Versleutelde DNS haalt de ISP uit beeld en maakt passieve monitoring een stuk lastiger.

De gateway draait DNS over HTTPS naar een upstream resolver. Alle VLANs gebruiken de gateway als DNS-server. Clients die de gateway proberen te omzeilen en rechtstreeks met `8.8.8.8` of `1.1.1.1` willen praten, worden door een NAT-regel teruggeleid naar de lokale resolver. Alleen het uitgaande DoH-verzoek verlaat daadwerkelijk het netwerk.

Eén upstream resolver is één single point of observation. De homelab wisselt tussen twee providers met verschillende logging-policies. Geen van beide is perfect, maar de combinatie is beter dan elk afzonderlijk.

## WiFi hardening

Wireless is de makkelijkste route een thuisnetwerk in. De hardening hier richt zich op het expliciet maken van het wireless trust model.

- **Aparte SSIDs per vertrouwensniveau.** Eén SSID voor vertrouwde apparaten, één voor IoT, één voor gasten. Geen gedeelde PSK over vertrouwensniveaus heen.
- **WPA3 waar ondersteund, WPA2 als fallback.** Mixed mode alleen op de IoT-SSID, omdat smart bulbs weigeren WPA3 te joinen.
- **PMF (802.11w) verplicht op WPA3-SSIDs.** Blokkeert deauth- en disassoc-spoofing.
- **Client isolation op de guest- en IoT-SSIDs.** Apparaten kunnen niet met elkaar praten, alleen met de gateway.
- **Verborgen SSIDs staan uit.** Een SSID verbergen voegt geen beveiliging toe en breekt auto-join op sommige clients.
- **Rogue AP detection aan.** De controller markeert onbekende APs die in de buurt uitzenden.

De WPA2-fallback op de IoT-SSID is een bekende zwakte. Smart home apparaten hebben levenscycli van jaren, en de helft krijgt nooit een firmware-update die WPA3-ondersteuning toevoegt. Het IoT VLAN uit [02](02-vlan-segmentation.nl.md) bestaat specifiek om die zwakte in te dammen.

## Honeypots

Een honeypot is een dienst die nooit verkeer hoort te krijgen. Elke verbindingspoging is automatisch verdacht, en dat maakt honeypots een extreem hoog-signaal detectiebron.

De homelab draait een kleine set honeypots in de Lab-zone:

- **SSH-honeypot.** Cowrie, logt credential-pogingen en post-auth commando's.
- **HTTP-honeypot.** Een nep login-pagina die credentials en user agents vastlegt.
- **SMB-honeypot.** Luistert naar laterale bewegingen in Windows-stijl.

Geen van deze diensten is doorgezet naar de WAN. Ze bestaan alleen om interne laterale bewegingen vanaf een gecompromitteerd apparaat te vangen. Logt de SMB-honeypot ooit een verbinding, dan scant iets op het netwerk naar file shares, en dat is reden om het offline te halen en te onderzoeken.

Honeypot-logs gaan naar de SOC-zone, waar de blue team tooling ze oppakt.

## Logging en retentie

Geen van de controls hierboven doet ertoe zonder logs. De gateway, de IPS, de wireless controller en de honeypots sturen allemaal logs naar een centrale collector in de SOC-zone. De retentie is 30 dagen op snelle opslag en 90 dagen in archief.

Dertig dagen is lang genoeg om de meeste incidenten te onderzoeken die laat ontdekt worden. Negentig dagen in archief is een compromis tussen opslagkosten en het feit dat sommige inbraken pas na maanden opduiken.

## Wat dit document niet dekt

De controls in dit document hardenen de netwerklaag. Ze vervangen niet:

- Endpoint protection op de apparaten zelf
- Patch management op Proxmox, containers en applicaties
- Backup en recovery voor de workloads in de Servers-zone
- Periodieke review van de firewall- en IPS-regels

Die horen thuis in aparte documenten onder `proxmox/` en `services/` en staan in de README van de repo vermeld.

## Wat komt hierna

Dit is het laatste document in de `network/`-serie. De volgende laag omhoog is het Proxmox-cluster zelf, behandeld in [proxmox/](../proxmox/). Daarvandaan staan de individuele diensten in [services/](../services/), en de overkoepelende besluiten en lessen in [docs/](../docs/).
