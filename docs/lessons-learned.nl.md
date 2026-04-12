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

## Documentatie die "afgerond" staat hoeft de realiteit niet te beschrijven

De hardening-documentatie van het Proxmox cluster stond in de lokale werkmap als volledig afgerond. Alle negen fases met een vinkje, inclusief SSH-hardening en een dedicated admin-user met sudo. Een vervolgsessie die begon met een SSH-check op beide nodes bracht aan het licht dat de `sudo`-binary helemaal niet geinstalleerd was, en dat `PermitRootLogin yes` plus `X11Forwarding yes` nog actief waren in `sshd_config`. De wijzigingen waren gepland en opgeschreven, maar niet op de nodes doorgezet.

De oorzaak is moeilijk achteraf te reconstrueren. Mogelijk heeft een sessie de config aangepast zonder een `systemctl reload ssh`, waarna iemand de node later herstart heeft zonder de config-file op disk te updaten. Mogelijk heeft een rollback van iets anders de SSH-wijzigingen mee teruggedraaid. Wat de oorzaak ook was, de documentatie en de werkelijkheid liepen uit elkaar zonder dat iemand het merkte.

**Les:** verifieer de werkelijke staat voordat je op documentatie vertrouwt. Voor elke sessie die voortbouwt op een eerdere, is een drie-minuten check via SSH van kritieke config-bestanden goedkoper dan een uur debuggen van iets dat "al geregeld zou moeten zijn". Een `sshd -T | grep -E 'permitroot|password|x11'` zegt meer dan een vinkje in een README.

## US en NL keyboard layout in installer-password prompts

De eerste installatie van Proxmox Backup Server eindigde met een root password dat niet meer werkte. Niet in SSH, niet in de web UI, niet in de console via noVNC. De installer vroeg om een password-bevestiging door het twee keer te typen en accepteerde beide invoer als matchend. Na reboot bleek het password dat ik nu typte niet het password dat ik tijdens install had bedoeld in te geven.

De oorzaak was een layout-mismatch. De installer stond op US-toetsenbord, wat in de praktijk betekent dat speciale tekens zoals `@`, `#`, `/`, `|` en `\` op andere posities zitten dan op een Mac met Nederlandse of US-International layout. Het password bevatte een `@` dat bij installtijd een ander teken opleverde dan bij login-tijd. De dubbele bevestigings-prompt detecteerde dat niet, omdat tijdens de install dezelfde layout werd gebruikt voor beide invoer.

De oplossing was reinstall met een password dat alleen letters (a-z, A-Z) en cijfers (0-9) bevat. Die tekens hebben dezelfde positie op vrijwel elke keyboard-layout, dus het password typt hetzelfde uit ongeacht waar het vandaan komt.

**Les:** voor installer-prompts in een browser-console, of voor virtuele consoles die hun eigen keyboard-handling doen, kies een password dat layout-onafhankelijk is. Dat betekent in de praktijk: alleen alfanumerieke tekens, geen speciale karakters. Het verlies aan entropie compenseer je door extra lengte. Een wachtwoord van twintig tekens met alleen letters en cijfers is sterker dan een van twaalf tekens met speciale tekens die je niet betrouwbaar kunt typen.

## Proxmox VMs booten na installer opnieuw naar de installer

De standaard boot-order van een nieuw aangemaakte VM in Proxmox is `ide2;scsi0`, waarbij `ide2` de CDROM is en `scsi0` de OS-disk. Dat is prima voor de eerste boot (want dan komt de installer van de CDROM), maar niet voor de tweede. Na een succesvolle installatie gaf ik de VM een reboot via de installer's "reboot" optie, waarna dezelfde installer opnieuw opstartte omdat de boot-order nog steeds CDROM-eerst stond.

Proxmox detecteert dit niet automatisch. De installer schrijft het systeem naar `/dev/sda`, meldt dat de installatie klaar is, en rebooted. Bij de volgende boot grijpt BIOS naar `ide2` omdat die eerst in de lijst staat, ziet de ISO nog steeds gemount in de CDROM-slot, en start het installer-menu opnieuw.

De fix is twee stappen na de succesvolle install: boot-order wijzigen naar `scsi0` only (of de CDROM verwijderen uit de order), en de ISO detachen zodat een expliciete F2-boot naar CDROM ook niet meer kan. Beide via `qm set`:

```
qm set <vmid> --boot order='scsi0'
qm set <vmid> --ide2 none,media=cdrom
```

**Les:** in Proxmox is post-install configuratie van een VM even belangrijk als de installatie zelf. Een standaard checklist voor elke nieuwe VM zou minimaal moeten bevatten: boot-order naar disk-only, ISO ejecten, `onboot=1` als het productie is, `qemu-guest-agent` enablen in de VM options, en een post-install snapshot voordat de eerste workload erin landt.

## Stale SSH host-keys blokkeren ssh-copy-id bij reinstalls

Na een PBS reinstall faalde `ssh-copy-id` met `REMOTE HOST IDENTIFICATION HAS CHANGED`. De vorige install had een host-key gegenereerd en een entry in `~/.ssh/known_hosts` achtergelaten. De reinstall genereerde nieuwe host-keys. SSH weigerde te verbinden omdat de fingerprint niet overeenkwam met wat hij in known_hosts had staan.

Dat is precies het juiste gedrag. Een gewijzigde host-key kan een legitieme reinstall zijn, maar ook een man-in-the-middle. SSH kiest defaults aan de veilige kant: blokkeren tot de gebruiker bevestigt wat er is gebeurd.

De fix is `ssh-keygen -R <hostname-or-ip>` om de oude entry te verwijderen, gevolgd door een nieuwe `ssh-copy-id`-poging die de nieuwe host-key accepteert en de public key installeert.

```
ssh-keygen -R 10.0.10.<pbs-ip>
ssh-copy-id root@10.0.10.<pbs-ip>
```

**Les:** bij elke reinstall van een host die via key-auth benaderd wordt, is `ssh-keygen -R` de eerste stap voordat je weer probeert te verbinden. Dit hoort in een mental-checklist voor post-reinstall operaties, naast "nieuwe cert fingerprint noteren" en "eerste succesvolle login verifieren".

## Debian deb822 sources disablen vraagt een rename, geen comment-hack

Voor oudere `.list`-formaat sources.list.d bestanden werkt het prima om de enige regel met een `#` te prefixen om de hele repo te deactiveren. Voor het nieuwere `.sources` formaat (deb822-stijl, standaard sinds Debian 12) werkt dat niet. Deze bestanden zijn gestructureerde stanzas met `Types:`, `URIs:`, `Suites:` en `Components:` op eigen regels. Het commentariseren van alleen de `Types:`-regel maakt het bestand ongeldig in plaats van uitgeschakeld, omdat de andere regels nog actief zijn maar geen geldige stanza vormen.

De manifestatie was apt die `Malformed stanza 1` gaf op de pbs-enterprise.sources file nadat ik de `Types:`-regel had uitgeschreven. apt weigerde elke update uit te voeren totdat het bestand weer syntactisch klopte.

De oplossing is een rename naar iets wat apt niet leest, bijvoorbeeld `.sources.disabled`:

```
mv /etc/apt/sources.list.d/pbs-enterprise.sources /etc/apt/sources.list.d/pbs-enterprise.sources.disabled
```

Alternatief: de hele file verwijderen als je zeker weet dat je hem nooit meer nodig hebt. Een rename is minder destructief omdat het ruimte laat voor een latere enable zonder de content opnieuw te moeten typen.

**Les:** check het formaat van de source-file voordat je hem probeert te editen. `.list`-formaat gebruikt `#` voor comments, `.sources`-formaat gebruikt rename of delete. Een `Enabled: false` veld bestaat niet in deb822, dus dat werkt ook niet.

## Circular dependency bij PBS als VM op de hypervisor

PBS draaien als VM op een PVE-host die hij zelf backup-dekt introduceert een circulaire afhankelijkheid. De PBS-VM bevat de datastore met alle andere backups. Als je hem in een PBS-side backup meeneemt, staat zijn backup in zichzelf, wat niet herstelbaar is als de VM zelf beschadigd raakt.

Het eerste instinct is de PBS-VM gewoon in de `weekly-backup` job laten meelopen. Dat werkt tot de dag dat je hem nodig hebt. Dan ontdek je dat de recovery-flow is: start PBS om de backup van PBS te kunnen lezen om PBS te restoren. Dat werkt niet.

De oplossing is een tweede vzdump-job met een andere scope en een ander target. De productie-job schrijft naar PBS en excludeert VM 180. Een aparte job backupt alleen VM 180 en schrijft naar de directe SATA-directory (dezelfde bulk-disk, maar via de oude vzdump-flow, niet via PBS). De twee paden delen fysieke hardware maar zijn onafhankelijk op de applicatielaag: een kapot PBS-proces breekt de SATA-directory-backup niet.

**Les:** zodra een service tegelijk producent en consument van zijn eigen backup-pad is, moet er een alternatief pad bestaan dat die service niet nodig heeft. Dat is niet uniek voor PBS. Hetzelfde geldt voor een database die zijn eigen backups in zijn eigen tabellen opslaat, een log-aggregator die alleen naar zijn eigen logs schrijft, of een secrets-vault waarvan de herstel-sleutel in de vault zelf staat. Het patroon is altijd hetzelfde: de recovery-route moet fysiek en logisch losstaan van wat er gerecovered wordt.

## Uptime Kuma 2.x heeft wachtwoord-beveiliging van status pages weggehaald

In Uptime Kuma v1.x kon een publieke status page met een simpel wachtwoord beveiligd worden. Invullen, delen met wie het nodig heeft, klaar. In v2.x is die functie weg. Status pages zijn daar óf publiek (geen login) óf bereikbaar via het admin panel (login plus 2FA).

Ik had twee status pages gepland: een publieke met een beperkte monitor-lijst, en een interne met alles achter een wachtwoord. De tweede is niet meer mogelijk zonder externe tools. Cloudflare Access werkt voor een browser, maar breekt native apps die geen Access login redirect aankunnen, en de ntfy iOS app is er daar een van. Voor het homelab werd de interne status page dus "het admin dashboard na login", functioneel hetzelfde minus een custom layout.

**Les:** voordat je een feature inplant, controleer of die nog bestaat in de versie die je draait. Grote version bumps schrappen features vaker dan changelogs suggereren. Voor Uptime Kuma specifiek: v2 is een flinke herschrijving en meerdere v1-gemakken zijn weg.

## WebAuthn werkt niet met IP-adressen als Relying Party ID

Proxmox VE's Auto-fill voor WebAuthn Settings vult het IP-adres van de node in als RP ID en Origin. Dat is technisch correct vanuit PVE's perspectief, maar de WebAuthn-spec en de meeste browser-implementaties vereisen een domeinnaam als RP ID. Het resultaat was een niet-beschrijvende foutmelding: `failed to begin webauthn context instantiation: The configuration was invalid`.

De oplossing was lokale DNS-records instellen via de UniFi gateway (Client Devices > device > IP Settings > Local DNS Record) en de PVE WebAuthn Settings bijwerken met de hostname als RP ID en Origin.

**Les:** benader services altijd via hostname, niet via IP. Stel lokale DNS in als eerste stap bij een nieuw cluster, voor je met 2FA-configuratie begint. De foutmelding vanuit PVE wijst niet naar de oorzaak, wat het debuggen bemoeilijkt.

## Firefox enterprise_roots importeert geen self-signed end-entity certs

`security.enterprise_roots.enabled = true` in Firefox importeert alleen certificaten met de CA basic constraint uit de macOS system keychain. Individuele self-signed certs zonder CA-flag worden genegeerd, ook als ze via `sudo security add-trusted-cert -d -r trustRoot` zijn toegevoegd. Chrome en Safari vertrouwen deze certs wel direct via de system keychain.

Het gevolg was dat een self-signed cert voor PVE wel in Chrome werkte maar niet in Firefox, ondanks dat het cert in de system keychain als trusted stond.

**Les:** voor multi-browser certificaatvertrouwen op macOS is een eigen CA de juiste aanpak. De CA heeft de CA basic constraint, wordt geimporteerd door Firefox via enterprise_roots, en elk cert dat ermee ondertekend is wordt automatisch vertrouwd in alle browsers.

## macOS passkey-handler onderschept Firefox WebAuthn met hardware keys

Firefox op macOS delegeert WebAuthn standaard naar de macOS passkey-handler (`security.webauthn.enable_macos_passkeys = true` in `about:config`). Die handler toont eerst een "Save a passkey?" dialoog voor iCloud Keychain. Na "More Options" en "Security Key" zou de hardware key bereikbaar moeten zijn, maar in de praktijk herkende de macOS-handler de YubiKey touch niet. Chrome, dat zijn eigen WebAuthn-implementatie gebruikt, werkte direct.

De oplossing was `security.webauthn.enable_macos_passkeys` op `false` zetten. Firefox gebruikt dan zijn eigen FIDO2/WebAuthn-handler die direct via USB HID met de key communiceert, zonder macOS-tussenlaag.

**Les:** zet deze instelling op `false` in Firefox als je een hardware security key gebruikt. De macOS passkey-handler is ontworpen voor iCloud Keychain passkeys en werkt niet betrouwbaar met USB security keys in Firefox.
