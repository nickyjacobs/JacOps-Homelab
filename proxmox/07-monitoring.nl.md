# Monitoring

🇬🇧 [English](07-monitoring.md) | 🇳🇱 Nederlands

Dit document beschrijft hoe het Proxmox cluster wordt gemonitord, welke lagen al actief zijn, welke gaten er nog zitten, en wat het plan is om die gaten te dichten. Het sluit aan op [02-uptime-kuma.nl.md](../services/02-uptime-kuma.nl.md), waar de Uptime Kuma monitoring stack zelf uitvoerig staat beschreven. Deze doc neemt de Proxmox-kant: wat je van de cluster meet, hoe je het meet, en wat er gebeurt als iets stuk gaat.

## Uitgangspunt

Monitoring op dit cluster bestaat vandaag uit twee dingen: de web UI van Proxmox zelf, en een Uptime Kuma stack in CT 151 die reachability en keyword-checks uitvoert. Dat is een werkend minimum dat de vraag "draait het?" beantwoordt. Het beantwoordt nog niet de vraag "hoe gaat het met de host?", want er zijn nog geen host-metrics (CPU, RAM, disk-IO, netwerk-doorvoer) die ergens worden verzameld of geschiedenis opbouwen.

Die twee vragen vragen om twee verschillende tools. Uptime Kuma is goed in reachability en heeft een lage drempel. Een metrics-tool als Beszel of Prometheus is goed in hosts profielen opbouwen en trends tonen. De afspraak is om beide tools naast elkaar te draaien, elk voor zijn sterke kant, zonder overlap.

## Twee lagen

De monitoring-stack is opgedeeld in twee lagen die niet mogen samenvallen.

**Laag 1: reachability.** Antwoordt de vraag: reageert deze service zoals hij zou moeten? Dat is Uptime Kuma's rol. Een HTTP-check naar een Proxmox web UI, een TCP-check naar een SSH-poort, een keyword-match in de response. Alleen binary uitkomst: up of down.

**Laag 2: host metrics.** Antwoordt de vraag: hoe belast is deze host? Dat is de rol van Beszel, gepland voor Fase 1 van de roadmap (zie [roadmap.nl.md](../docs/roadmap.nl.md)). CPU-load, RAM-verbruik, disk-IO, netwerk throughput, geschiedenis over dagen en weken. Continue waardes in plaats van binaire.

De twee overlappen bewust niet. Een reachability-probe kan niet zien dat een host op 95 procent RAM zit, omdat de host nog prima pakketten terugstuurt. Een host-metrics tool kan niet zien dat een reverse proxy een verkeerd certificaat serveert, want het certificaat komt niet uit de kernel-stats. Beide signalen zijn nodig, en ze komen uit verschillende plekken.

## Wat PVE zelf biedt

Proxmox heeft twee ingebouwde vormen van monitoring die zonder externe tooling al werken.

**De web UI dashboards.** Per node toont de UI CPU, RAM, disk en netwerk in real-time graphs met een schuifbaar tijdvenster tot een jaar. Dat is genoeg om ad-hoc te kijken of een node onder load staat, of een disk snel volloopt, of het netwerkverkeer vreemde pieken vertoont. De data zit in `/var/lib/rrdcached/` en wordt door `pvestatd` bijgehouden. Het is geen externe tool nodig om dat te zien, maar het is ook niet alerting: je moet zelf de UI openen.

**`pvestatd`** is de daemon die elke 10 seconden statistieken verzamelt en in de RRD's schrijft. Zonder deze daemon tonen de UI-graphs niks. Bij problemen met de graphs is de eerste check `systemctl status pvestatd`, niet de UI zelf.

Daarnaast heeft PVE een mail-notificatie-systeem dat backup-jobs en replicatie-events kan doorsturen. Dat is ingezet voor de `weekly-backup` en `pbs-self-backup` jobs met `mailnotification failure` (zie [03-backups.nl.md](03-backups.nl.md)). Slaagt een backup, dan gebeurt er niets. Faalt er een, dan komt er een mail binnen. Dat is het enige pad waarop PVE zelf alerts genereert. Alle andere alerting loopt buiten PVE om.

## Wat Uptime Kuma al dekt

De Uptime Kuma stack in CT 151 monitort op dit moment tien services verdeeld over drie labels (zie [02-uptime-kuma.nl.md](../services/02-uptime-kuma.nl.md) voor de volledige lijst). Drie daarvan raken het Proxmox cluster direct:

| Monitor | Type | Target | Check |
|---------|------|--------|-------|
| Proxmox Node 1 | HTTPS keyword | Management IP, poort 8006 | Keyword "Proxmox" in de response |
| Proxmox Node 2 | HTTPS keyword | Management IP, poort 8006 | Keyword "Proxmox" in de response |
| UniFi Gateway | Ping | Gateway IP | ICMP |

De keyword-match is belangrijker dan een gewone TCP-check. Een TCP-check zou slagen zelfs als de web UI een HTTP 500 teruggeeft, waardoor een kapotte PVE-daemon door het net zou glippen. Het woord "Proxmox" dwingt dat de loginpagina daadwerkelijk rendert.

Daarnaast heeft Uptime Kuma nog geen monitor voor PBS zelf. Dat is een gat dat gevuld hoort te worden zodra de deploy rond is: een HTTPS-check naar `https://pbs-01.jacops.local:8007` met keyword-match op "Proxmox Backup Server". PBS faalt lang stil zonder zo'n probe omdat de enige output een wekelijkse backup-job is, wat minder dan een dag zichtbaar is voordat er data gemist wordt.

## Wat er nu ontbreekt

Drie soorten metrics worden niet verzameld, en dat is een bewuste gap die Fase 1 van de roadmap aanpakt.

**Host-metrics met geschiedenis.** De web UI toont real-time CPU/RAM/disk/netwerk, maar niemand kijkt op vaste momenten of zet er alerting op. Beszel lost dit op door agents op beide PVE-nodes en op de foundation-CTs te draaien, die hun metrics naar een centrale hub in CT 151 sturen. De hub bewaart de geschiedenis en kan thresholds triggeren voor notifications.

**Disk SMART-data.** De NVMe's op beide nodes en de SATA-disk op Node 1 rapporteren via SMART hun eigen gezondheidstoestand: schrijf-amplificatie, bad sectors, temperatuur, reallocate counts. Op dit moment wordt daar niks mee gedaan. Een losse `smartmontools`-install op elke node met een dagelijkse cron die `smartctl -a` uitvoert en bij afwijkingen een ntfy-push stuurt, is een kleine toevoeging die vroegtijdig disk-sterfte kan signaleren. Staat op de wensenlijst, niet urgent omdat de failure-mode van NVMe/SATA in een homelab typisch luidruchtig is.

**Log-aggregatie.** Elke node heeft zijn eigen journald met standaard-retentie (nu teruggebracht naar 500 MB per [02-hardening.nl.md](02-hardening.nl.md)). Er is geen centrale plek die logs van beide nodes plus alle containers samenbrengt. Bij een post-incident analyse betekent dat SSH'en naar meerdere plekken. Een centrale log-store is een gewicht-categorie hoger dan de rest van dit monitoring-plan en is daarom bewust uitgesteld.

## Alerting-pad

Alle alerts komen uiteindelijk op de iPhone binnen via ntfy. Zie [03-ntfy.nl.md](../services/03-ntfy.nl.md) voor hoe de ntfy-stack dat doet zonder dat alert-inhoud het homelab verlaat. De samenvatting:

```
PVE node / service / Uptime Kuma ─── HTTP POST ───┐
                                                   │
                          ┌────────────────────────┘
                          ▼
                      ntfy (CT 151)
                          │
                          ├──► Webclients (realtime)
                          │
                          └──► Upstream poll ──► ntfy.sh ──► APNs ──► iPhone
```

Uptime Kuma stuurt alerts naar ntfy via het interne Docker netwerk (`http://ntfy:80`). PVE-mail voor backup-failures loopt niet via ntfy, want PVE zelf heeft geen native ntfy-output. Dat is een tweede route die uit de inbox van de beheerder komt. In de praktijk is dat prima voor backup-failures, want die vragen een doordachte reactie en niet een instant push.

Beszel krijgt later een eigen alerting-pad, waarschijnlijk ook via ntfy maar met andere templates zodat een "CPU boven 90 procent voor 15 minuten" duidelijk onderscheidbaar is van een reachability-alert.

## Operationele checks

Naast de passieve monitoring zijn er handmatige checks die regelmatig worden uitgevoerd en die niet door tooling worden vervangen omdat ze te laag-niveau zijn om te automatiseren.

**Dagelijks bij het openen van de MacBook.** Kijk op de Uptime Kuma status page voor eventuele rode icoontjes. Dat is nu nog een handmatig ritueel en staat op de to-do om als status-widget op het iPhone lock screen te zetten.

**Wekelijks na de zondagnacht-backup.** Controleer dat `pvesm list pbs-main` de verwachte nieuwe backups bevat. De eerste keer dat de automatische job draait is dat expliciet: verifieer dat de vier jobs (weekly-backup, pbs-self-backup, GC, prune, verify) allemaal in de juiste volgorde zijn uitgevoerd.

**Maandelijks.** Controleer de `Data%` op de thin pool (`lvs` op beide nodes, zie [04-storage.nl.md](04-storage.nl.md)) en de vulling van de SATA-disk. Dit is de laatste check voordat een pool vol loopt, en gebeurt met de hand omdat het eens per maand genoeg is.

**Bij een deploy.** De check-lijst uit [06-vm-hygiene.nl.md](06-vm-hygiene.nl.md) valt technisch ook onder monitoring: het is een post-change verificatie dat de nieuwe guest op de juiste manier is aangehaakt in de cluster.

## Beszel

Beszel v0.18.7 draait als Docker container in CT 151, naast Uptime Kuma en ntfy. De hub verzamelt metrics van negen agents: zeven foundation-LXCs via SSH-mode en twee PVE-nodes via WebSocket-mode. De UI is intern bereikbaar via `beszel.jacops.local` achter Traefik.

De agents meten CPU, RAM, disk, disk-IO, netwerk, load average, temperatuur en actieve services. Alerts staan ingesteld op 80% drempel (10 minuten venster) voor CPU, geheugen en disk, plus status-alerts bij uitval. Notificaties lopen via ntfy over het interne Docker netwerk.

Volledige documentatie in [services/10-beszel.nl.md](../services/10-beszel.nl.md).

## Resultaat

De huidige monitoring-staat:

1. **Reachability is gedekt** via Uptime Kuma met tien monitors waarvan drie direct op PVE/UniFi en zeven op applicaties en netwerkhardware.
2. **Realtime host-inzicht is handmatig** via de PVE web UI dashboards en `pvestatd`, zonder alerting.
3. **Backup-alerting loopt via mail** voor failures, met een automatische wekelijkse `verify-new`-check op de PBS-datastore.
4. **Push-meldingen komen op de iPhone** via self-hosted ntfy, zonder dat alert-inhoud het homelab verlaat.

De bekende gaten:

1. ~~Geen geschiedenis van host-metrics~~ Opgelost door Beszel, zie hierboven.
2. **Geen SMART-monitoring** voor de disks zelf, wordt opgelost door een kleine smartmontools-cron wanneer die gebouwd wordt.
3. **Geen centrale log-aggregatie**, bewust uitgesteld tot na de foundation-laag omdat de complexiteit niet in verhouding staat tot de waarde op deze schaal.

De drie gaten zijn gedocumenteerd en weten wie hun oplossing is. Dat is wat monitoring hoort te leveren: niet perfect inzicht, maar voorspelbare dekking met duidelijk benoemde randen.
