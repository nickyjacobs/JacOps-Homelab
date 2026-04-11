# VM en container hygiene

🇬🇧 [English](06-vm-hygiene.md) | 🇳🇱 Nederlands

Dit document beschrijft de afspraken die elke VM en container op dit cluster volgt. Het gaat niet over hoe je een VM aanmaakt, dat doet de Proxmox-installer en `qm create` al. Het gaat over de instellingen en conventies die ervoor zorgen dat een guest tien maanden later nog steeds snapshot-safe is, terugvindbaar is in de UI en correct herstart na een reboot van zijn host.

## Uitgangspunt

Een verse Proxmox-install produceert guests met defaults die werken maar niet optimaal zijn voor een homelab dat langer dan een week meegaat. De meestgemiste zijn de qemu-guest-agent (PVE weet de VM-status niet), de protection-vlag (`qm destroy` is één typo ver) en consistent gebruik van tags (zoeken wordt raden als de cluster groeit). Dit document legt de afspraken vast die de verschillende deploys uit [roadmap.nl.md](../docs/roadmap.nl.md) samenhang geven.

De afspraken zijn niet allemaal even hard. Sommige zijn strikt (guest agent, onboot), andere zijn conventies die consistentie opleveren (hostnaamschema, tags). De tekst hieronder markeert het verschil.

## Naamgeving en VMID's

Elke guest krijgt een VMID volgens een vast schema, en een hostnaam die die VMID zichtbaar maakt in elke terminal.

**VMID's per categorie.** De nummering is gegroepeerd, zodat `pct list` en `qm list` vanzelf ordenen:

| Range | Categorie | Voorbeelden |
|-------|-----------|-------------|
| 100-149 | Gereserveerd | Standaard Proxmox install ISO's, eventuele helper CTs |
| 150-159 | Applicatiecontainers | CT 150 n8n, CT 151 monitoring-stack |
| 160-169 | Foundation LXC-services | CT 160 Forgejo, CT 161 runner, CT 162 Vaultwarden, CT 163 Miniflux |
| 170-179 | Lab containers | CT 170 Docker-host voor DVWA en Metasploitable 2 |
| 180-189 | Infrastructure VMs | VM 180 `pbs-01` |
| 2000+ | Lab VMs | VM 2000 Windows 10 Evaluation |

De vier ranges voor containers (150/160/170) scheiden wat productie-applicatie is van wat foundation is en wat lab is. Die grens loopt parallel aan de VLAN-toewijzing uit [05-networking.nl.md](05-networking.nl.md). Een VMID tussen 160 en 169 hoort op het Servers VLAN. Een tussen 170 en 179 op het Lab VLAN. Dat maakt mispliaatsing makkelijk te spotten bij een audit.

**Hostnames.** Foundation-services krijgen een hostnaam in de vorm `<service>-<nn>` (bijvoorbeeld `pbs-01`, `vault-01`, `forgejo-01`). Container-stacks die meerdere services hosten krijgen een hostname die die stack beschrijft (`monitoring-stack` op CT 151). De hostname staat los van de DNS-CNAME waarmee de service publiek of intern bereikbaar is. `vault.jacops.local` wijst naar CT 162, maar de container zelf heet `vault-01` vanaf de shell.

## Tags

Tags zijn een lichte vorm van metadata op Proxmox-niveau. Ze verschijnen in de UI naast elke VM en container, en ze zijn doorzoekbaar. Zonder tags moet je bij elke wijziging opnieuw door de lijst zoeken welke guests welke rol hebben. Met tags krijgt elke guest een klein setje labels dat zegt waar hij bij hoort.

Drie tag-categorieen zijn in gebruik:

**Rol.** Wat deze guest is. Voorbeelden: `application`, `infrastructure`, `backup`, `foundation`, `lab`, `monitoring`, `automation`.

**Lifecycle.** Hoe de guest behandeld wordt. Voorbeelden: `production`, `scratch`, `onboarding`, `deprecated`.

**Criticaliteit.** Hoe ernstig een uitval is. Voorbeelden: `critical`, `important`, `normal`.

Een typische foundation-service heeft dus drie tags: `infrastructure;foundation;critical`. Een lab-container krijgt `lab;scratch;normal`. Het voordeel komt uit zoeken: `Tags: critical` filtert in één klik alle guests waarvan de uitval aandacht vraagt.

Tags zijn geen vervanger voor documentatie en horen niet bij te worden gehouden voor elke kleine wijziging. Ze dienen als operationele snelkoppelingen, niets meer.

## Verplichte VM-instellingen

Onderstaande instellingen horen op elke VM aan te staan, ongeacht wat erop draait.

| Instelling | Waarde | Reden |
|------------|--------|-------|
| `agent` | `1` | PVE leest VM-status en IP-adressen via de qemu-guest-agent uit zodra die in de guest draait |
| `onboot` | `1` | VM start automatisch mee bij reboot van de host, zodat services niet handmatig hoeven worden gestart |
| `protection` | `1` voor productie-VMs | Blokkeert `qm destroy` zonder dat je eerst expliciet protection uitzet |
| `machine` | `q35` | Modernere chipset-emulatie, nodig voor PCIe-passthrough en nieuwere guests |
| `bios` | `seabios` of `ovmf` | SeaBIOS voor eenvoud, OVMF alleen voor guests die UEFI eisen |
| `scsihw` | `virtio-scsi-single` | Aparte virtio controller per disk, betere performance bij parallelle I/O |
| `cpu` | `host` | Geef alle CPU-features door aan de guest, voorkomt performance-verlies en compatibility-problemen |
| `ostype` | Correct gezet | PVE past optimalisaties toe per OS-type (l26 voor Linux, win10/win11 voor Windows) |

Voor de qemu-guest-agent geldt dat de vlag aanzetten in de VM-config niet voldoende is. De agent moet ook in de guest geinstalleerd en draaiende zijn. Op Debian en Ubuntu:

```
apt install qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

Op Windows komt de agent uit de virtio-win ISO. Pas nadat de agent loopt, kan PVE de VM clean shutdown geven (in plaats van een hard reset) en de IP-adressen uitlezen in de UI.

De `protection=1`-vlag is een cheap insurance-policy. Hij voorkomt `qm destroy <vmid>` per ongeluk, zonder dat het iets kost aan performance of operationele vrijheid. Voor wegwerp-lab-VMs (scratch tag) staat hij juist uit, omdat die door hun aard bedoeld zijn om snel gesloopt en opnieuw gebouwd te worden.

## Verplichte container-instellingen

Containers delen veel defaults met VMs, maar hebben eigen eigenaardigheden.

| Instelling | Waarde | Reden |
|------------|--------|-------|
| `unprivileged` | `1` | Root in de container is geen root op de host, default voor elke nieuwe CT |
| `onboot` | `1` | Herstart mee met de host |
| `protection` | `1` voor productie-CTs | Zelfde blokkade als bij VMs maar op `pct destroy` |
| `ostype` | Correct | Bepaalt welke integratie PVE toepast |
| `features` | `nesting=1` voor Docker-in-LXC, `keyctl=1` waar nodig | Standaard uit, alleen aan waar een specifieke workload het eist |
| `hostname` | Consistent schema | Zie naamgeving hierboven |

**Unprivileged als standaard.** Privileged containers zijn sneller in een paar edge cases, maar root in een privileged container is root op de host. Dat is een klasse-A risico. Elke CT in deze cluster is unprivileged tenzij er een gedocumenteerde reden is voor het tegendeel, en die reden staat er tot nu toe niet.

**Nesting en keyctl alleen voor Docker-in-LXC.** De Forgejo runner uit de roadmap draait Docker binnen een LXC, en dat vraagt `nesting=1,keyctl=1` als feature-flags. Die vlaggen geven de container meer kernel-capabilities dan de standaard, en horen alleen aan waar dat nodig is. Elke LXC die per ongeluk met nesting aan wordt aangemaakt zonder dat de workload het vraagt, krijgt de vlag bij een review weer uit.

**Features-review.** Er is een vaste controle bij elke nieuwe LXC: de `features`-regel in de config kijken en bewust beoordelen of iets anders dan de default nodig is. In praktijk is die regel leeg voor 90 procent van de containers.

## Boot-order en startup-delays

Twee instellingen bepalen wat er gebeurt als een node reboot.

**`onboot`** staat op elke production-guest aan. Dat is de standaard uit de tabellen hierboven en de reden dat na een reboot de container-stack zichzelf weer opstart.

**`startup`** is een optionele string die de volgorde en delays bepaalt. Drie waardes:

```
startup: order=5,up=60,down=120
```

- `order`: lager getal start eerder. Gebruik dit om afhankelijkheden te respecteren. Infrastructure (PBS, Vaultwarden) op `order=1`, applicaties die credentials uit Vaultwarden halen op `order=5`, lab-VMs (als ze al onboot zijn) op `order=10`.
- `up`: hoeveel seconden wachten na de start voordat de volgende guest mag starten. Nuttig als een service een paar seconden nodig heeft om zijn database te openen voordat andere services hem mogen raken.
- `down`: hoeveel seconden wachten op een clean shutdown voordat PVE een hard stop doet. Standaard is 180 seconden voor VMs en 60 voor CTs. Een database die langer nodig heeft om zijn buffers te flushen krijgt een hogere waarde.

De `startup`-string is opt-in. Zonder de string starten guests in willekeurige volgorde met de PVE-defaults, wat in dit cluster zelden problemen geeft omdat er geen harde inter-service-dependencies zijn die niet vanzelf herstellen.

## Snapshots versus backups

Snapshots en backups zijn niet hetzelfde, en worden af en toe verward.

**Snapshots** zitten op het LVM-thin niveau voor containers en op het qcow2-niveau voor VMs op directory-storage. Ze zijn gratis en direct, en bedoeld voor korte-termijn veiligheid: "ik ga een risicovolle change doen, snapshot even zodat ik kan rollbacken." Een snapshot is geen backup omdat hij op dezelfde disk leeft als het origineel. Disk weg, snapshot ook weg.

**Backups** zijn de vzdump- of PBS-outputs beschreven in [03-backups.nl.md](03-backups.nl.md). Die zitten op aparte storage (in dit cluster de SATA-disk op Node 1 of de PBS-datastore daar bovenop) en dekken disk-uitval van de node zelf.

De afspraak voor deze cluster: elke risicovolle change krijgt eerst een snapshot (`qm snapshot <vmid> pre-change` of `pct snapshot <vmid> pre-change`), die na successful change of na een paar dagen wordt opgeruimd. Backups worden niet handmatig gemaakt behalve als extra veiligheid voor een echt grote wijziging. De wekelijkse geautomatiseerde backup uit 03-backups dekt het normale geval.

Snapshots op de thin pool zijn goedkoop tot ze lang blijven staan. Een snapshot plus een paar weken schrijven in de guest betekent dat de copy-on-write delta groot wordt en dus echte ruimte inneemt. Oude snapshots worden daarom na een week automatisch gevlagd in de review.

## Review-moment na elke deploy

Elke nieuwe VM of LXC doorloopt direct na aanmaken een vaste check-lijst. De lijst is kort en handmatig, omdat het niet de moeite is om er tooling voor te bouwen voor de schaal van dit cluster:

1. **Tags gezet?** Minimaal de drie categorieen (rol, lifecycle, criticaliteit).
2. **Guest agent geinstalleerd en actief?** `qm agent <vmid> ping` moet slagen.
3. **onboot aan?** `qm config <vmid> | grep onboot` of `pct config <vmid> | grep onboot`.
4. **Protection aan voor productie?** `qm config <vmid> | grep protection`.
5. **Firewall-vlag op de NIC?** Zie [05-networking.nl.md](05-networking.nl.md) voor de `firewall=1` afspraak.
6. **Discard en SSD-vlaggen op de disk?** Zie [04-storage.nl.md](04-storage.nl.md) voor de thin-pool instellingen.
7. **Hostname consistent met het schema?**
8. **Eerste backup draait bij de eerstvolgende geplande job?** Of er is een bewuste uitsluiting (zoals VM 180 die in de pbs-self-backup zit).

Punt 8 is de meest vergeten. Het is makkelijk om een nieuwe CT te maken, zijn werk op te starten, en dan twee weken later te merken dat de wekelijkse job hem niet heeft meegenomen omdat hij in een exclude-lijst staat die niet meer klopt.

## Opruimen en deprovisioning

De tegenhanger van een zorgvuldige setup is een zorgvuldige cleanup. Wanneer een guest weg moet:

1. **Final snapshot of backup** voor het geval de cleanup onverwacht iets relevants raakt.
2. **Protection uit** met `qm set <vmid> --protection 0` of `pct set <vmid> --protection 0`.
3. **Destroy** met `qm destroy <vmid>` of `pct destroy <vmid>`. De flag `--purge 1` verwijdert ook referenties in backup-jobs en firewall-configs.
4. **Controleer** met `pvesm status` of de thin-pool ruimte is teruggekomen (bij containers is dat direct, bij VMs kan het een minuut duren).
5. **Logbestand-entry** in `decisions.nl.md` of `lessons-learned.nl.md` als er iets geleerd is dat een toekomstige deploy anders hoort te doen.

Een fout in stap 3 zonder `--purge 1` laat verweesde entries achter in de backup-config die bij de volgende `vzdump`-run een foutmelding opleveren. Niet kritiek, wel vervelend.

## Resultaat

De hygiene-afspraken leveren drie dingen op:

1. **Voorspelbaarheid.** Elke VM of CT die volgens deze regels is aangemaakt, gedraagt zich hetzelfde na een reboot, bij een backup en bij een zoekactie in de UI.
2. **Lage opzet-kosten.** De check-lijst is handmatig maar kort, en loopt elke keer dezelfde volgorde. Geen tooling nodig, wel discipline.
3. **Vangnet tegen fouten.** Protection-vlaggen, consistente VMID-ranges en expliciete tags betekenen dat een typo in een destroy-commando stopt voordat het iets belangrijks raakt.

De kosten zijn klein: een paar minuten per deploy extra voor de check-lijst. De alternatieve opzet, waarbij elke guest op defaults wordt gelaten en je achteraf moet raden wat er aan bepaalde settings af is, kost veel meer zodra het cluster boven een handvol guests uitkomt.
