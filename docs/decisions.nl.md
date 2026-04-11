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

## Self-hosted pushmeldingen in plaats van een externe dienst

**Datum:** 2026-04-11
**Gebied:** Monitoring

Uptime Kuma ondersteunt een lange lijst aan notificatie-providers: Telegram, Discord, Slack, e-mail, ntfy en meer. De makkelijke route is Telegram of Discord kiezen, een bot opzetten, token plakken, klaar. Ik heb voor self-hosted ntfy gekozen.

Elke monitoring alert bevat de hostname, het IP of de URL van een service in het homelab. Die stroom door de messaging-infrastructuur van een derde partij sturen betekent dat iemand anders een betrouwbaar beeld krijgt van welke services hier draaien en wanneer ze uitvallen. Voor een homelab dat bouwt op security-first defaults voelt dat als de verkeerde richting in ruil voor vijf minuten setup-tijd.

ntfy draait als container naast Uptime Kuma. Het is licht (rond de 30-50 MB RAM), open source, en ondersteunt iOS push via een upstream patroon waarbij de publieke `ntfy.sh` instantie alleen een SHA256 hash van de topic en het bericht-ID te zien krijgt. De eigenlijke inhoud blijft in het homelab, omdat de telefoon het bericht direct bij de self-hosted server ophaalt nadat Apple's push-service hem wakker heeft gemaakt.

De wissel is meer complexiteit: één extra container, één extra config-bestand, één extra troubleshooting-pad. De iOS push pipeline heeft randgevallen die niet opduiken bij een publieke ntfy.sh topic (zie [lessons-learned.nl.md](lessons-learned.nl.md)). Voor een homelab is die extra moeite het waard.

## Eén Cloudflare tunnel per stack, meerdere hostnames

**Datum:** 2026-04-11
**Gebied:** Remote toegang

n8n draait met een eigen Cloudflared container in de n8n stack. De monitoring stack (Uptime Kuma plus ntfy) had ook publieke toegang nodig, en er waren drie opties:

1. Elke service een eigen tunnel geven (twee tunnels voor twee services in dezelfde stack)
2. De ingebouwde tunnel van Uptime Kuma gebruiken voor UK en een aparte tunnel voor ntfy
3. Eén losse cloudflared container in de monitoring stack die beide services routeert via één tunnel met twee hostnames

Optie drie werd het. Uptime Kuma en ntfy delen een failure domain: dezelfde LXC, hetzelfde Docker netwerk, dezelfde host. Splitsen in twee tunnels maakt de opstelling niet veerkrachtiger, omdat een gecrashte LXC ze alsnog beide meeneemt. Eén tunnel met meerdere publieke hostnames is simpeler om te beheren, gebruikt minder resources, en houdt alle tunnel-config in het Cloudflare dashboard op één plek.

De ingebouwde Uptime Kuma tunnel blijft om dezelfde reden ongebruikt. Een losse cloudflared container is taal-onafhankelijk, doet meerdere hostnames standaard, en wordt beheerd door Docker Compose in plaats van door het Uptime Kuma proces.

Het patroon is: één tunnel per stack, één stack per LXC. n8n heeft zijn tunnel, de monitoring stack heeft zijn tunnel, en elke toekomstige stack (Wazuh en wat daarbij past) krijgt een eigen tunnel.

## Publieke status page zonder interne services

**Datum:** 2026-04-11
**Gebied:** Monitoring

De publieke status page van Uptime Kuma is een mooie portfolio-toevoeging. Hij laat zien dat services draaien, ziet er professioneel uit, en spiegelt wat echte SaaS-producten tonen op `status.something.com`. De vraag was wat er op zou komen.

De eerste ingeving was "alles". Alle tien monitors, gegroepeerd op label, zichtbaar voor iedereen die de URL vindt. Het probleem met "alles" is dat het een gratis OSINT-blad wordt. Proxmox nodes noemen vertelt een aanvaller welke hypervisor de infrastructuur draagt. UniFi hardware noemen verraadt de netwerkleverancier. Op zichzelf is geen van die punten bruikbaar, maar elk datapunt maakt het raadspel kleiner als iemand beslist om verder te kijken.

De tweede ingeving was de pagina compleet achter Cloudflare Access of een wachtwoord zetten. Cloudflare Access breekt de iOS ntfy app, omdat native apps de Access login flow niet kunnen volgen. Uptime Kuma 2.x heeft de ingebouwde password-functie voor status pages weggehaald. Volledig dichtzetten zou dus betekenen: óf iOS notificaties slopen, óf de status page helemaal laten vallen.

Het gekozen pad is een publieke pagina met een beperkte monitor-lijst. Alleen de services die naar buiten mogen staan erop: n8n, ntfy en Uptime Kuma zelf. Alles wat intern is (Proxmox, UniFi, DNS, lokale container-checks) is voor de admin zichtbaar via het dashboard na login, maar onzichtbaar op de publieke pagina. De portfolio-waarde blijft, en het OSINT-oppervlak blijft klein.

## Prometheus voorlopig overslaan

**Datum:** 2026-04-11
**Gebied:** Monitoring

Prometheus en Grafana is de logische volgende stap in monitoring-volwassenheid. Betere metrics, betere dashboards, alerting-regels met echte logica. Het homelab is er nog niet klaar voor, en misschien voorlopig ook niet.

Voor tien monitors beantwoordt het eigen dashboard van Uptime Kuma de vraag die als eerste telt: draait het of draait het niet. Prometheus zou een tweede daemon toevoegen, een scrape-config, een time-series database, Grafana erbovenop voor visualisatie, en exporters op elke host die meer diepgang vraagt. Dat is een paar uur setup en nog eens 500+ MB RAM voor een resultaat dat het antwoord op "draait het" niet wezenlijk verbetert.

Prometheus wordt nuttig zodra er meerdere databronnen zijn om te combineren. Zodra Wazuh komt na de eJPT-certificering, is er data van defensieve tools om tegen beschikbaarheid en performance-metrics af te zetten. Grafana als één scherm over Uptime Kuma, Wazuh, Proxmox node-exporter en n8n begint op dat punt zichzelf terug te verdienen.

Uptime Kuma heeft al een eigen `/metrics` endpoint in Prometheus-formaat, dus het migratiepad is schoon. Geen verhuizing, geen herschrijving, alleen een nieuw scrape-target.
