# Geleerde Lessen

🇬🇧 [English](lessons-learned.md) | 🇳🇱 Nederlands

Dingen die misgingen, me verrasten, of die ik de volgende keer anders zou aanpakken. Opgeschreven zodat ik ze niet herhaal.

---

## VLAN-hernummeringsvolgorde is belangrijk

Bij het hernummeren van VLANs kunnen subnetconflicten je blokkeren. Het Guest-netwerk moest naar `10.0.50.0/24`, maar dat subnet was bezet door het Lab-netwerk. Het Lab-netwerk moest eerst naar `10.0.30.0/24` verhuizen om het bereik vrij te maken.

De les: breng de volledige keten van verplaatsingen in kaart voordat je begint. Elke VLAN-hernummering is een kleine migratie, en de volgorde hangt af van welke subnets eerst vrijgemaakt moeten worden. De volgorde op papier uitwerken kostte vijf minuten en bespaarde minstens een uur terugkrabbelen.

## UniFi-netwerken zijn niet altijd in-place bewerkbaar

Het Guest-netwerk weigerde op te slaan na wijziging van VLAN ID en subnet. De UI gaf een generieke "Failed saving network" fout zonder verdere uitleg. De oplossing was het netwerk volledig verwijderen en opnieuw aanmaken met de nieuwe instellingen.

Dit betekende dat de Guest WiFi SSID tijdelijk naar een ander netwerk verplaatst moest worden, het nieuwe Guest-netwerk aangemaakt kon worden, en de SSID weer teruggekoppeld. Het werkte, maar zonder voorkennis dat de SSID eerst losgekoppeld moest worden, zou het verwijderen ook gefaald hebben.

**Les:** controleer voor het hernoemen of hernummeren van een UniFi-netwerk wat ervan afhankelijk is (SSIDs, switch port profiles, firewallregels). Als de bewerking faalt, is verwijderen en opnieuw aanmaken een werkbaar pad, maar alleen als je de afhankelijkheden eerst loskoppelt.

## Proxmox clustermigratie vereist gecoordineerde stappen

Een twee-node Proxmox cluster naar een nieuw subnet verplaatsen vereiste wijzigingen op beide nodes in een specifieke volgorde: netwerkinterfaces, `/etc/hosts`, en corosync-configuratie. Eerst maar één node wijzigen zou het cluster breken omdat corosync de andere node op het oude IP probeert te bereiken.

De aanpak die werkte:
1. Stop alle VMs en containers
2. Bereid de nieuwe netwerkconfig voor op beide nodes (schrijf naar `interfaces.new`, activeer nog niet)
3. Werk `/etc/hosts` bij op beide nodes
4. Werk de corosync-config bij met nieuwe IPs en verhoog het versienummer
5. Reboot beide nodes tegelijkertijd

Het kernpunt is dat het cluster als geheel moet overgaan. Eén node tegelijk doen creëert een split-brain situatie waarbij elke node denkt dat de ander onbereikbaar is.

**Les:** maak altijd een backup van de volledige configuratiemap (`/etc/pve/`, `/etc/network/`, `/etc/hosts`) voor een clusterwijde netwerkwijziging. De backups redden me toen ik het originele corosync-versienummer moest verifiëren.

## Custom zones zijn deny-by-default zonder extra werk

Ik besteedde tijd aan het plannen van deny-by-default firewalling via de globale "Block All" toggle. Het bleek dat custom zones in UniFi al deny-by-default zijn ten opzichte van elkaar. Alle netwerken uit de ingebouwde Internal zone halen en in een custom zone plaatsen was voldoende.

Dit realiseerde ik me pas na het zorgvuldiger lezen van de UniFi-documentatie. De globale toggle bestaat voor de ingebouwde zones (Internal, External, Hotspot). Custom zones volgen die toggle niet omdat ze starten zonder inter-zone regels, wat neerkomt op deny.

**Les:** lees de platformdocumentatie voordat je workarounds ontwerpt. De functie die ik probeerde te bouwen bestond al.

## Honeypot-adressen moeten mee met VLAN-hernummering

Na het hernummeren van VLANs wezen de honeypot IP-adressen nog naar de oude subnets. Honeypots in UniFi worden per netwerk geconfigureerd met een vast IP (`.2` adressen in mijn geval). Toen de subnets veranderden, moesten de honeypots opnieuw geconfigureerd worden.

Dit is makkelijk te missen omdat honeypots niet in de hoofdnetwerkconfiguratie verschijnen. Ze staan onder de beveiligingsinstellingen en volgen subnetwijzigingen niet automatisch.

**Les:** houd een checklist bij van alles dat naar een specifiek subnet verwijst. VLANs, DHCP-bereiken, firewallregels, honeypots, statische DNS-entries, VPN-routes. Eén hernummeren betekent allemaal bijwerken.

## Switch port profiles overleven netwerkwijzigingen

Bij het hernummeren van VLANs verwachtte ik switch port profiles opnieuw te moeten configureren. De ports bleven werken omdat UniFi switch profiles verwijzen naar het netwerk op naam, niet op VLAN ID. Het hernoemen van het VLAN of wijzigen van het ID breekt de poorttoewijzing niet.

Dit is goed ontwerp aan UniFi's kant, maar ik ontdekte het pas tijdens de migratie. Dit van tevoren weten had de risicoinschatting van de VLAN-hernummering verlaagd.

## Pre-shared keys op WireGuard zijn de moeite waard

WireGuard authenticeert peers al via public key cryptografie. Een pre-shared key (PSK) toevoegen is optioneel en voegt een extra symmetrische encryptielaag toe. De setupkosten zijn één extra regel in elke peer-config.

De reden: post-quantum weerstand. Als iemand vandaag WireGuard-verkeer opvangt en Curve25519 over tien jaar kraakt, beschermt de PSK-laag de sessie nog steeds. Voor een homelab is dit misschien overdreven, maar de kosten zijn vrijwel nul en de gewoonte is het waard om op te bouwen.

## iOS ntfy push breekt als de base URL niet exact gelijk is

Self-hosted ntfy gebruikt een upstream-patroon voor iOS notificaties. De server stuurt een poll-request naar `ntfy.sh` met een SHA256 hash die berekend wordt uit `base-url + topic`. De iOS app berekent dezelfde hash uit de default server URL die de gebruiker heeft ingevuld. Komen de hashes niet overeen, dan arriveren pushes nooit op de telefoon.

Ik heb ruim een uur achter dit probleem aangelopen. Notificaties verschenen in de ntfy web UI en in de iOS app zodra ik hem opende, maar nooit als banner. Elk config-bestand zag er correct uit. De debug logs lieten een geslaagde `Publishing poll request` regel zien. Alles leek gezond, en niks werkte.

De oorzaak was een typo in de Docker Compose file. De `NTFY_BASE_URL` environment variable stond op `https://ntfy.example.nl` terwijl de echte publieke URL `.online` gebruikte. Het config-bestand in de container had wel de juiste `.online` waarde staan, maar environment variables winnen het in ntfy van config-bestanden. De server hashte tegen de ene URL, de iOS app tegen de andere, en die twee kwamen bij `ntfy.sh` nooit samen.

**Les:** zet de base URL op precies één plek (óf in de env var, óf in het config-bestand, nooit allebei), controleer dat `/v1/config` teruggeeft wat je verwacht, en check de default server URL in de iOS app karakter voor karakter. De stille faalmodus is bijzonder lastig omdat elke diagnose suggereert dat het werkt.

## Docker environment variables overschrijven config-bestanden in stilte

Nauw verbonden met de ntfy base URL valkuil: ntfy (en veel andere Go-services) laten je dezelfde instelling configureren via een YAML config-bestand of een environment variable. Bestaan beide, dan wint de environment variable. Geen waarschuwing, geen startup-regel, niets dat zegt "ik negeer je config-bestand".

Ik paste `server.yml` in de container aan, herstartte ntfy, en ging ervan uit dat mijn wijziging had gewerkt. Dat was niet zo. De env var uit `docker-compose.yml` stuurde het gedrag nog steeds aan, en mijn "fix" deed niks.

**Les:** kies één bron van waarheid per instelling. Voor gecontaineriseerde services zijn environment variables meestal de betere keuze, omdat die met de compose file meereizen en zichtbaar zijn in `docker inspect`. Gebruik je liever het config-bestand, zorg er dan voor dat de env vars niet gezet zijn, niet dat ze op dezelfde waarde staan.

## Uptime Kuma 2.x heeft wachtwoord-beveiliging van status pages weggehaald

In Uptime Kuma v1.x kon een publieke status page met een simpel wachtwoord beveiligd worden. Invullen, delen met wie het nodig heeft, klaar. In v2.x is die functie weg. Status pages zijn daar óf publiek (geen login) óf bereikbaar via het admin panel (login plus 2FA).

Ik had twee status pages gepland: een publieke met een beperkte monitor-lijst, en een interne met alles achter een wachtwoord. De tweede is niet meer mogelijk zonder externe tools. Cloudflare Access werkt voor een browser, maar breekt native apps die geen Access login redirect aankunnen, en de ntfy iOS app is er daar een van. Voor het homelab werd de interne status page dus "het admin dashboard na login", functioneel hetzelfde minus een custom layout.

**Les:** voordat je een feature inplant, controleer of die nog bestaat in de versie die je draait. Grote version bumps schrappen features vaker dan changelogs suggereren. Voor Uptime Kuma specifiek: v2 is een flinke herschrijving en meerdere v1-gemakken zijn weg.
