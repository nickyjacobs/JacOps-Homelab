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

## Container images pinnen op tag plus SHA256 digest

**Datum:** 2026-04-11
**Gebied:** Supply chain

De n8n compose stack draaide met floating `latest` tags op alle drie de containers: n8n zelf, Postgres en cloudflared. Dat is de default uit de meeste quickstarts en werkt prima totdat het niet meer werkt. Een image-publisher die per ongeluk een breaking change uitrolt, of een upstream die gecompromitteerd wordt, is via `latest` direct jouw productie binnen zodra iemand `docker compose pull` draait.

De keuze werd om elk image te pinnen op zowel de leesbare tag als de SHA256 digest van het specifieke image dat op dat moment draaide. Het formaat wordt `repo:tag@sha256:hash`. De tag blijft leesbaar voor mensen die de config later openen, de digest is cryptografisch: zelfs als iemand de tag overschrijft, wijst dit image-referentie nog steeds naar het exacte image dat getest is.

Het effect is dat upgrades bewuste acties worden. Een nieuwe n8n-versie proberen vereist dat ik de digest expliciet update, een pull doe, en opnieuw deploy. Geen stille sprong naar een versie die ik niet heb getest. Voor een homelab dat naar een klant-rollout-patroon beweegt is dit de juiste gewoonte.

De afweging is iets meer werk bij elke upgrade in ruil voor voorspelbaarheid. Ik accepteer dat.

## Proxmox Backup Server als VM op de hypervisor

**Datum:** 2026-04-11
**Gebied:** Backup infrastructuur

De officiele Proxmox-aanbeveling is dat PBS op fysiek gescheiden hardware draait. In een homelab met twee PVE-nodes en geen derde machine valt die aanbeveling weg. Ik stond voor drie opties: geen PBS (en bij vzdump blijven), PBS op een externe VPS via WireGuard, of PBS als VM op een van de PVE-hosts zelf.

PBS overslaan betekent deduplicatie, verify-jobs, incremental-forever en encryption-at-rest opgeven. Dat zijn precies de dingen die moderne backup-infrastructuur onderscheiden van "een tar-bestand ergens neerzetten". Voor een setup die naar klantwerk beweegt is het leren van de PBS-flow waardevoller dan de eenvoud van vzdump behouden.

PBS op een externe VPS geeft fysieke scheiding terug, maar verplaatst alle backup-data buiten het eigen netwerk. Dat kost bandbreedte, vraagt encryption-keys op afstand, en maakt restore-operaties langzamer. Voor een homelab op deze schaal weegt de extra complexiteit niet op tegen de fysieke scheidingswinst.

De gekozen route is PBS als VM op Node 1, met een expliciete oplossing voor de circular dependency die deze keuze introduceert. De VM schrijft zijn datastore als qcow2-bestand op de SATA-directory, en een tweede backup-job draait elke maandag om 04:00 die alleen de PBS-VM zelf via vzdump naar diezelfde SATA-directory schrijft. Bij catastrofaal verlies van de PBS-VM kan hij teruggezet worden vanuit de vzdump-snapshot, waarna de datastore (die in een apart qcow2-bestand op dezelfde disk leeft) onaangetast beschikbaar blijft.

De prijs is een tweede backup-job en een documentatie-last: de recovery-procedure voor PBS zelf loopt niet via PBS. Zolang Job 2 elke maandag draait en de notificatie-at-failure aan staat, blijft dat pad in beeld.

## ext4 boven ZFS voor een single-disk PBS datastore

**Datum:** 2026-04-11
**Gebied:** Backup infrastructuur

De PBS installer vraagt tijdens setup welk filesystem de datastore krijgt. ZFS is de canonieke aanbeveling omdat het compressie, checksums en snapshots native aanbiedt. Op een enkele virtuele disk verdwijnt het grootste ZFS-voordeel: er is geen redundantie tussen disks, dus checksums kunnen corruptie opsporen maar niet herstellen.

De ZFS ARC-cache vraagt standaard ongeveer 1 GB extra RAM. Op een PBS-VM die al krap op 4 GB zit is dat een significante tax zonder directe winst. PBS doet zijn eigen deduplicatie en chunk-hashing op applicatielaag, dus de compressie-winst van het filesystem stapelt niet op een zinvolle manier op wat PBS al doet.

ext4 werd de keuze. De redundantielaag zit een niveau hoger: het qcow2-bestand waar de datastore in leeft wordt meegenomen in de `pbs-self-backup`-job, en filesystem-corruptie wordt opgevangen door fsck tijdens boot plus de `verify-new=true`-instelling die elke nieuwe backup direct na upload controleert.

Als de PBS-VM ooit naar dedicated hardware met meerdere disks migreert, wordt ZFS de juiste keuze. Op deze schaal is de eenvoud van ext4 de betere trade-off.

## API-token boven wachtwoord voor PVE-PBS integratie

**Datum:** 2026-04-11
**Gebied:** Backup infrastructuur

PVE kan PBS benaderen met een gebruikersnaam-plus-wachtwoord of met een API-token. De `pvesm add pbs`-flow ondersteunt beide. Een wachtwoord voor `root@pam` is de snelste route: twee regels config en je hebt verbinding.

De API-token-route kost meer stappen maar verdient zichzelf terug. De flow is: dedicated service-account aanmaken (`pve-sync@pbs`), DatastoreBackup-rechten scoped op `/datastore/main`, token genereren onder dat account, dezelfde DatastoreBackup-role expliciet op de token zetten, en de token-waarde in de PVE storage-config plakken.

Drie voordelen tegen één nadeel. Het voordeel is revocatie-granulariteit: als de token lekt, trek je dat ene token in en de rest van de authenticatie blijft intact. Een gelekt root-wachtwoord daarentegen vraagt een rotatie over alle systemen die het gebruiken. Het tweede voordeel is scope: de token heeft alleen backup-rechten op één datastore, geen admin-rechten op andere delen van PBS. Het derde voordeel is dat het service-account wachtwoord nooit door een mens gebruikt hoeft te worden. Het blijft een random gegenereerde waarde die niemand onthoudt en die in geen enkel script staat.

Het nadeel is complexiteit bij de eerste setup. Twee ACL-entries in plaats van één, en een generate-token stap. Bij elke andere interactie met dit pad is het tokensysteem makkelijker omdat het geen menselijke geheugen vraagt.

## Foundation layer herzien na validatie-ronde

**Datum:** 2026-04-11
**Gebied:** Service-selectie

De eerste planning voor de foundation layer bevatte Forgejo, Vaultwarden, LiteLLM, Apprise en Changedetection.io als de vijf "must-have" services voor de volgende uitbreidingsronde. Een diepgaande validatie-ronde bracht drie van die vijf in twijfel.

**LiteLLM werd geschrapt.** In maart 2026 werden twee PyPI-versies van LiteLLM gecompromitteerd via een backdoor in de CI/CD-pipeline. Kort daarna volgde een reeks kritieke CVEs, waaronder een OIDC auth bypass en een privilege escalation. Voor een solo-gebruiker van Claude Code levert LiteLLM vooral centrale cost tracking en virtual keys per skill op. Beide bleken minder scherp dan verwacht: virtual keys vereisen dat elke skill in een aparte proces-context draait, wat de workflow breekt. Het alternatief `ccusage` leest de eigen JSONL session-logs van Claude Code direct en geeft 90% van de cost tracking waarde zonder extra infrastructuur. De afweging tussen een centrale proxy met een actieve supply-chain-geschiedenis en een read-only tool die niets toevoegt aan de attack surface viel naar de tweede.

**Apprise werd geschrapt.** De assumptie was dat Apprise als universele notification-abstraction waardevol is. Bij nader inzien heeft ntfy (al draaiend) inmiddels declarative users, ACL's, tokens en templates. De use-cases die Apprise zou oplossen zijn oplosbaar met directe webhooks of de ntfy CLI. Geen concrete pijn om op te lossen, dus geen reden om een service toe te voegen.

**Changedetection.io werd vervangen door Miniflux.** De oorspronkelijke use-case was CVE-feeds en vendor-advisories naar de threat-intel workflow brengen. Changedetection.io heeft in de afgelopen zes maanden drie noemenswaardige CVEs gehad, waaronder een SSRF en een auth bypass via decorator-ordering. Het grotere probleem is dat vrijwel alle security-feeds die relevant zijn (NVD, CISA KEV, Rapid7 blog, vendor PSIRTs, GitHub releases) al RSS of Atom aanbieden. Een dedicated RSS-reader zoals Miniflux is lichter, heeft een kleiner attack surface, en dekt het gebruik beter. Changedetection.io blijft relevant voor pages zonder RSS-feed, maar als foundation-service is het de verkeerde keuze.

De resultaten zijn toegevoegd aan de lijst: Forgejo en Vaultwarden blijven, PBS werd toegevoegd als kritieke eerste deploy voordat alle andere services landen, Miniflux vervangt Changedetection.io, en Beszel plus Dockge werden bijgeschreven als lichte host-metrics en compose-management laag.

De les uit deze ronde is dat een service-lijst uit een handvol blog-aanbevelingen niet hetzelfde is als een gevalideerde stack. Elke service bij binnenkomst is een nieuw attack surface en een nieuwe operationele last. De vraag "wat gaat kapot zonder" is strenger dan "wat zou leuk zijn om erbij te hebben", en die strengere vraag filterde drie van de vijf oorspronkelijke keuzes weg.

## Prometheus voorlopig overslaan

**Datum:** 2026-04-11
**Gebied:** Monitoring

Prometheus en Grafana is de logische volgende stap in monitoring-volwassenheid. Betere metrics, betere dashboards, alerting-regels met echte logica. Het homelab is er nog niet klaar voor, en misschien voorlopig ook niet.

Voor tien monitors beantwoordt het eigen dashboard van Uptime Kuma de vraag die als eerste telt: draait het of draait het niet. Prometheus zou een tweede daemon toevoegen, een scrape-config, een time-series database, Grafana erbovenop voor visualisatie, en exporters op elke host die meer diepgang vraagt. Dat is een paar uur setup en nog eens 500+ MB RAM voor een resultaat dat het antwoord op "draait het" niet wezenlijk verbetert.

Prometheus wordt nuttig zodra er meerdere databronnen zijn om te combineren. Zodra Wazuh komt na de eJPT-certificering, is er data van defensieve tools om tegen beschikbaarheid en performance-metrics af te zetten. Grafana als één scherm over Uptime Kuma, Wazuh, Proxmox node-exporter en n8n begint op dat punt zichzelf terug te verdienen.

Uptime Kuma heeft al een eigen `/metrics` endpoint in Prometheus-formaat, dus het migratiepad is schoon. Geen verhuizing, geen herschrijving, alleen een nieuw scrape-target.

## Audit Round 1: git history met BLOCKER-content accepteren (Optie 3 hybrid)

**Datum:** 2026-04-12
**Gebied:** Security, git hygiene

Bij de eerste volledige audit van de repo werden drie BLOCKERs gevonden in HEAD: een concreet host-IP in lessons-learned dat niet als placeholder was geschreven, een absoluut filesystem-pad in CLAUDE.md dat de lokale mappenstructuur onthulde, en werkgever-referenties in de roadmap. Alle drie zitten ook in git history (commits `361f433`, `7033ebc`, `e2ca3a6`) die al naar `origin/main` zijn gepushed.

Drie opties lagen er:

1. **Accept history, fix HEAD only.** Gaat niet mee met history rewrite. HEAD is schoon, commits behouden de leak in hun diff
2. **Filter-repo + force-push.** Schoont history, maar breekt de commit-policy no-force-push regel, breekt eventuele clones, en GitHub cached commit views blijven maandenlang bestaan via SHA-URL's
3. **Hybrid: fix HEAD nu, history-beslissing later.** Combineert de acute fix met uitstel van de destructieve operatie

Keuze werd Optie 3 (hybrid). Redeneringen:

- De commit-policy is een zelfopgelegde harde regel. Die breken vereist een bewuste, gedocumenteerde uitzondering, niet een audit-bijproduct
- De repo is nieuw, waarschijnlijk nul forks of clones, dus de praktische impact van de history-leak is minimaal
- De BLOCKERs zijn al publiek geweest sinds de push. Een paar uur meer of minder exposure verandert niks aan het risico
- HEAD-fix voorkomt verdere verspreiding bij nieuwe clones of scrapes
- Filter-repo kan later alsnog als bewuste, separate cleanup-actie worden uitgevoerd

De HEAD-fixes zijn doorgevoerd: het IP is vervangen door een placeholder, het absoluut pad is verplaatst naar het gitignored bestand `CLAUDE.local.md`, en de werkgever-referenties zijn herschreven naar neutrale formuleringen. De hooks zijn uitgebreid met detectie van absolute filesystem-paden om herhaling te voorkomen.

Open: als de repo significant groeit in visibility (forks, sterren), heroverweeg Optie 2 als gecontroleerde cleanup met expliciete commit-policy-exception.

## Eigen homelab CA boven self-signed certificaten

**Datum:** 2026-04-12
**Gebied:** TLS, certificaatbeheer

Proxmox VE genereert bij installatie een self-signed certificaat met de hostname van de node als CN. Toen WebAuthn-registratie van een YubiKey vereiste dat de PVE web UI via een hostname benaderd werd in plaats van een IP-adres, ontstond een kettingreactie: het self-signed cert had de verkeerde CN, Firefox vertrouwde het niet via de macOS system keychain (omdat `security.enterprise_roots.enabled` alleen CA-certificaten importeert, niet individuele end-entity certs), en Chrome vertrouwde het wel maar dat loste het Firefox-probleem niet op.

Drie opties lagen er:

1. **Per service een self-signed cert met correcte SAN.** Werkt in Chrome en Safari via de system keychain, maar niet in Firefox zonder handmatige security exceptions per site
2. **Certs handmatig importeren in Firefox.** Werkt, maar schaalt niet naar meerdere services en moet bij elke cert-vernieuwing herhaald worden
3. **Eigen CA aanmaken en alle service-certs daarmee ondertekenen.** De CA gaat eenmalig in de macOS system keychain, waarna alle browsers (inclusief Firefox via enterprise_roots) elk cert dat ermee ondertekend is automatisch vertrouwen

Optie 3 werd de keuze. De `JacOps Homelab CA` is een RSA 4096-bit root CA met `basicConstraints: CA:TRUE, pathlen:0` en een geldigheid van tien jaar. De private key is AES256-encrypted en opgeslagen in `~/.homelab-ca/` op de Mac (chmod 700). Service-certs zijn RSA 2048-bit met twee jaar geldigheid.

De directe winst is dat elke nieuwe service (Vaultwarden/Caddy, Forgejo, PBS, Miniflux) een cert krijgt dat in alle browsers vertrouwd is zonder extra stappen. De CA key verhuist naar Vaultwarden zodra die draait, zodat het secret niet op een onversleuteld filesystem blijft staan.

## Top-level hardware map voor cross-cutting apparatuur

**Datum:** 2026-04-12
**Gebied:** Repo-structuur

De YubiKey 5C NFC documentatie hoorde aanvankelijk in `proxmox/` als nummer 08. Bij nader inzien klopt dat niet: de YubiKey is geen Proxmox-specifiek onderwerp. Hij wordt gebruikt bij PVE, maar straks ook bij Vaultwarden, Forgejo, Bitwarden cloud en mogelijk SSH. Dat maakt het een cross-cutting hardware-item dat niet onder een enkele categorie thuishoort.

Twee opties lagen er:

1. **In `proxmox/` laten.** Snel, geen structuurwijziging, maar misleidend. Lezers die de YubiKey-doc zoeken kijken niet als eerste in de Proxmox-sectie
2. **Nieuwe top-level map `hardware/`.** Eigen categorie voor fysieke apparatuur die meerdere secties raakt. Volgt hetzelfde patroon als `network/`, `proxmox/` en `services/`

Optie 2 werd de keuze. De YubiKey is het eerste item als `hardware/01-yubikey`. De map schaalt naar toekomstige hardware-documentatie als die relevant wordt, zonder dat er opnieuw een structuurwijziging nodig is.

## Miniflux container specs opgehoogd van roadmap

**Datum:** 2026-04-14
**Gebied:** Resource-planning

De roadmap specificeerde 256 MB RAM en 3 GB disk voor Miniflux (CT 163). Tijdens de deploy bleek dat te krap. Miniflux, PostgreSQL 16, Caddy en de Docker daemon samen vragen meer dan 256 MB aan overhead, zelfs als de applicaties zelf maar ~74 MB idle gebruiken. Docker daemon alleen neemt al 80-120 MB. De 3 GB disk raakt vol door drie Docker images (~400-500 MB samen) plus PostgreSQL data en Docker overlay.

Beide zijn opgehoogd naar de waardes die Vaultwarden (CT 152) ook gebruikt: 512 MB RAM met 256 MB swap, en 5 GB rootfs op de NVMe thin pool. In de praktijk zit de idle footprint rond 74 MB (Caddy 10 MB, Miniflux 24 MB, Postgres 40 MB), ruim binnen de 512 MB grens, met headroom voor feed polling pieken.

## Traefik als standaard reverse proxy, Caddy vervangen

**Datum:** 2026-04-14
**Gebied:** Reverse proxy, infrastructuur

Drie reverse proxy opties lagen er: Caddy (al in gebruik bij Vaultwarden, Forgejo, Miniflux), Traefik en Nginx Proxy Manager.

Nginx Proxy Manager viel af op basis van een recente CORS CVE in de huidige versie (token theft via JWT interception, CVE-2025-50579), het ontbreken van Infrastructure-as-Code (config niet versioneerbaar of auditeerbaar), een dubbel attack surface (Node.js GUI plus C-based Nginx), en MariaDB als extra dependency.

Caddy en Traefik zijn beide Go-based en memory-safe. Caddy heeft superieure TLS defaults (automatische HTTPS, ingebouwde OCSP stapling, eigen CA/ACME server). Traefik heeft native Docker service discovery via labels, kan Docker en file providers simultaan draaien (gebouwd voor een mix van Docker en native LXC services), en schaalt naar honderden services zonder config-overhead.

Traefik werd de keuze. De doorslag gaf de mixed setup van het homelab: sommige services draaien als Docker containers, andere als native binaries in LXC. Traefik's provider-model handelt beide af zonder plugins of workarounds. Bij drie bestaande Caddy configs is nu het goedkoopste moment om te migreren. De steilere leercurve weegt niet op tegen de operationele voordelen op termijn.

De migratie betreft Vaultwarden (CT 152), Forgejo (CT 160) en Miniflux (CT 163). Nieuwe services (Beszel, Dockge, en alles in Fase 3) worden direct op Traefik gebouwd.

## step-ca als interne ACME server, handmatige OpenSSL CA vervangen

**Datum:** 2026-04-14
**Gebied:** PKI, certificaatbeheer

De handmatige OpenSSL CA (RSA 4096 root, handmatige cert-generatie per service, twee jaar geldigheid) wordt vervangen door step-ca als interne ACME server met kortstondige certificaten.

Drie problemen met de huidige aanpak rechtvaardigden de wissel:

1. **Key compromise window.** Een gecompromitteerde service-key geeft een aanvaller twee jaar geldige impersonatie. Met step-ca's default van 24 uur (configureerbaar) krimpt dat venster naar een dag.
2. **Operationele last.** Handmatige cert-vernieuwing schaalt niet. Bij twintig services zijn dat twintig handmatige OpenSSL sessies per twee jaar. step-ca vernieuwt automatisch via ACME.
3. **Geen revocatie.** De handmatige CA heeft geen mechanisme om een gecompromitteerd cert in te trekken. step-ca lost dit passief op: kortstondige certs verlopen simpelweg.

step-ca draait als eigen LXC met een two-tier PKI: de root key gaat offline (USB drive), de intermediate key op de YubiKey PIV slot (slot 9c, non-exportable). Signing vereist fysieke YubiKey plus PIN. Caddy en Traefik vragen certs aan via het standaard ACME protocol, exact zoals ze dat bij Let's Encrypt zouden doen.

De bestaande homelab CA blijft vertrouwd in de macOS system keychain totdat alle services zijn gemigreerd. Daarna wordt de oude CA ingetrokken.

Alternatieven die afvielen: Caddy's ingebouwde CA (gekoppeld aan Caddy's lifecycle, niet geschikt als centrale PKI), Let's Encrypt voor interne services (Certificate Transparency logs onthullen interne domeinnamen, externe dependency voor intern verkeer), en de handmatige CA behouden (suboptimaal voor een cybersecurity professional, niet conform de industrie-standaard van geautomatiseerde kortstondige certificaten).
