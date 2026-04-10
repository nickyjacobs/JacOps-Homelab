# Ontwerpbeslissingen

🇬🇧 [English](decisions.md) | 🇳🇱 Nederlands

Dit document beschrijft de keuzes die niet vanzelf spreken. Elke entry legt uit wat er besloten is, waarom, en welke alternatieven er lagen. Als ik deze setup over een jaar opnieuw bouw, moeten deze notities voorkomen dat ik dezelfde fouten maak of eerder bewezen keuzes in twijfel trek.

---

## Custom zones in plaats van globale deny-all

**Datum:** 2026-04-07
**Gebied:** Firewall

UniFi biedt twee manieren om deny-by-default firewalling in te richten. De eerste is de globale Default Security Posture van "Allow All" naar "Block All" zetten. De tweede is elk netwerk in een custom zone plaatsen, waardoor inter-zone verkeer automatisch deny-by-default wordt.

Ik koos voor custom zones. De globale toggle is een enkele schakelaar die alles tegelijk blokkeert. Eén gemiste allow-regel en je sluit jezelf buiten de gateway. Custom zones bereiken hetzelfde resultaat maar laten je policies per zone-paar opbouwen. Het mentale model is schoner: elk zone-paar is of expliciet toegestaan, of wordt stilzwijgend gedropt.

**Afweging:** meer initieel werk (13 custom policies in plaats van één toggle), maar veiliger uitrol en makkelijker te beredeneren achteraf.

## Apps VLAN gescheiden van Servers

**Datum:** 2026-04-07
**Gebied:** Segmentatie

Proxmox hypervisors staan op het Servers VLAN. Application workloads (workflow-automatisering, monitoring) staan op een apart Apps VLAN. De hypervisors kunnen het Apps-subnet bereiken voor containerbeheer, maar andersom niet.

De reden is blast radius. Als een applicatiecontainer gecompromitteerd raakt, landt de aanvaller in de Apps-zone. Vandaaruit blokkeert de zone-firewall laterale beweging naar het hypervisor management plane. Zonder deze scheiding zou een gecompromitteerde container op hetzelfde VLAN als Proxmox direct API-calls tegen de hypervisor kunnen proberen.

## Tagged VLAN management voor Proxmox

**Datum:** 2026-04-07
**Gebied:** Proxmox networking

Twee opties bestonden om Proxmox op een eigen VLAN te plaatsen. De eerste was de switch-port wijzigen naar een native (untagged) VLAN, wat geen aanpassingen op Proxmox vereist. De tweede was de trunk-port behouden en een tagged sub-interface (`vmbr0.10`) op de bridge aanmaken.

Ik koos de tagged aanpak. Die is consistent met hoe VMs en containers hun VLAN-tags al krijgen, houdt de switch-port als schone trunk, en betekent dat de Proxmox-host deelneemt aan dezelfde VLAN-aware bridge als de rest. De untagged aanpak had gewerkt maar creëert een inconsistentie: de host gebruikt native VLAN terwijl de workloads tagged VLANs gebruiken op dezelfde bridge.

## VLAN-nummering volgt derde octet

**Datum:** 2026-04-06
**Gebied:** Segmentatie

Elk VLAN ID komt overeen met het derde octet van het subnet. VLAN 10 gebruikt `10.0.10.0/24`, VLAN 30 gebruikt `10.0.30.0/24`, enzovoort. Dit verwijdert een laag mentale vertaling bij troubleshooting. Als je verkeer ziet van `10.0.20.x`, weet je dat het VLAN 20 is zonder een tabel te raadplegen.

De originele setup had inconsistente nummering (VLAN 133 op `10.0.10.0`, VLAN 5 op `10.0.5.0`). Hernummeren vereiste zorgvuldige volgorde omdat subnets vrijgemaakt moesten worden voordat ze opnieuw toegewezen konden worden. Zie [lessons-learned.nl.md](lessons-learned.nl.md) voor de details.

## WireGuard met split en full tunnel profielen

**Datum:** 2026-04-07
**Gebied:** Remote access

Twee clientprofielen bestaan. De telefoon gebruikt een full tunnel die al het verkeer via het homelab routeert, handig op onbetrouwbaar WiFi. De laptop gebruikt een split tunnel die alleen het homelab-subnet door de VPN stuurt, zodat regulier browsen op de lokale verbinding blijft.

WireGuard is gekozen boven de ingebouwde Teleport-functie. Teleport werkt maar is vendor-locked, ondersteunt geen split tunneling, en voegt latency toe via relay-servers. WireGuard is een directe peer-to-peer verbinding, sneller, en draagbaar naar elk clientplatform. Teleport blijft ingeschakeld als fallback voor situaties waar UDP 51820 geblokkeerd is.

VPN-clients kunnen Management, Servers en Apps zones bereiken. Toegang tot SOC, Lab en IoT is geblokkeerd. Als VPN-credentials lekken, kan de aanvaller bij admin-interfaces maar niet bij de opzettelijk kwetsbare lab-machines of IoT-apparaten.

## Dynamic DNS via gateway API

**Datum:** 2026-04-07
**Gebied:** Remote access

De ISP wijst een dynamisch publiek IP toe. De VPN-endpoint hostname wijst naar dit IP via dynamic DNS. In plaats van een aparte DDNS-client te draaien, werkt de gateway het DNS-record direct bij via de API van de DNS-provider wanneer het IP verandert.

Het API-token is beperkt tot een enkele zone met uitsluitend DNS-bewerkingsrechten. Als het token lekt, is het ergste scenario dat iemand de VPN-hostname naar een ander IP wijst. Diegene kan geen andere DNS-records aanpassen, geen andere API-resources benaderen, en geen verkeer onderscheppen (WireGuard authenticeert peers op basis van public key, niet hostname).

## IPS in blockmodus vanaf dag één

**Datum:** 2026-04-06
**Gebied:** Hardening

De IPS draaide in notify-only modus. Ik schakelde over naar notify-and-block met alle handtekeningcategorieën op maximale gevoeligheid.

IPS draaien in notify-only modus in een homelab heeft weinig nut. Er staat geen SOC-team paraat om alerts dag en nacht te bewaken, dus notificaties zonder automatische blokkering produceren alleen een log die niemand leest. In een productieomgeving zou je met notify beginnen om te voorkomen dat false positives bedrijfsprocessen verstoren. In een homelab is een false positive die iets blokkeert een leerkans, geen bedrijfsrisico.

## GeoIP-blokkering alleen inbound

**Datum:** 2026-04-06
**Gebied:** Hardening

GeoIP-regels blokkeren inbound verkeer vanuit Rusland, China, Noord-Korea en Iran. Outbound is niet geblokkeerd.

Outbound verkeer blokkeren op basis van land is fragiel. CDN's serveren content vanuit onverwachte regio's, package mirrors kunnen resolven naar geblokkeerde landen, en legitieme diensten gebruiken wereldwijd verspreide infrastructuur. De waarde van outbound GeoIP-blokkering is laag vergeleken met de troubleshootingkosten wanneer iets stilzwijgend breekt. Inbound blokkering is zinvoller omdat er geen reden is voor ongevraagde verbindingen vanuit deze regio's naar een homelab.

## Versleutelde DNS met filtering

**Datum:** 2026-04-06
**Gebied:** Hardening

DNS-queries gaan door versleutelde resolvers met ingebouwde malware- en phishingfiltering. Twee providers zijn geconfigureerd voor redundantie.

Onversleutelde DNS lekt elke domeinlookup naar de ISP. Versleutelde DNS met filtering voegt twee lagen toe: privacy (de ISP kan queries niet zien) en basisprotectie (bekende kwaadaardige domeinen worden geblokkeerd op resolverniveau). Dit vervangt geen endpoint security, maar vangt de makkelijke gevallen op netwerkniveau op zonder onderhoud.
