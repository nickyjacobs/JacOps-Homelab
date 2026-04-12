# Backups

🇬🇧 [English](03-backups.md) | 🇳🇱 Nederlands

Dit document beschrijft de backup-infrastructuur voor het Proxmox cluster. De wekelijkse vzdump-job uit [02-hardening.nl.md](02-hardening.nl.md) is vervangen door een Proxmox Backup Server (PBS) opstelling met deduplicatie, integrity-verificatie en een circular-dependency-safe fallback-pad.

## Uitgangspunt

Na de hardening-sessie stond er een wekelijkse vzdump-job gepland die nooit had gedraaid. Het eerste onderhoudsvenster viel op de zondag na de setup. Het risico was stil: een geplande job zonder eerste handmatige testrun biedt geen zekerheid dat het schema werkt, dat de backup-storage schrijfbaar is, dat het juiste target geselecteerd is, of dat de container-snapshots op snapshot-mode terugvallen zoals ze horen.

Een tweede tekortkoming was de storage-keuze. De job schreef naar de SATA-directory-storage op Node 1 als gewone tar.zst archieven. Dat werkt voor configuratieherstel, maar mist alle voordelen die backup-infrastructuur de moeite waard maken: deduplicatie over VMs heen, integrity-verificatie van opgeslagen chunks, incremental-forever backups die alleen veranderingen sinds de vorige run schrijven, en encryption on disk.

Een derde tekortkoming was het ontbreken van een restore-test. Een backup zonder restore-test is geen backup.

Het doel van deze sessie was alle drie punten tegelijk aanpakken: een testrun + restore-test op de oude vzdump-flow uitvoeren, PBS deployen als vervanging, en de retention-policy scherp stellen voordat de eerste automatische run draait.

## Keuze: PBS als VM op de hypervisor

PBS is ontworpen om op dedicated hardware te draaien. De officiele aanbeveling luidt dat het Backup-doel fysiek gescheiden moet zijn van het PVE-cluster dat het beschermt. Dat principe is onbetwist: een hardwarefout die beide hosts meeneemt neemt ook de backups mee.

In dit homelab bestaat die tweede fysieke host niet. De opties waren:

1. PBS overslaan en vzdump blijven gebruiken
2. PBS als virtual machine op een van de PVE-nodes draaien
3. PBS op een externe VPS draaien met de backup-traffic via WireGuard

Optie 1 geeft alle dedup- en verify-voordelen op. Optie 3 verplaatst de backup-data buiten het eigen netwerk, wat bandbreedte-kosten en extra complexiteit toevoegt zonder voor deze schaal proportionele beveiligingswinst. Optie 2 werd de keuze, met een expliciete oplossing voor de circular dependency die deze keuze introduceert (zie [Backup-strategie](#backup-strategie) verderop).

PBS draait nu als VM 180 (`pbs-01`) op Node 1, met zijn OS-disk op de NVMe thin pool en zijn datastore op de SATA-directory als qcow2-bestand. De datastore krijgt daarmee thin provisioning plus ruimte om te groeien zonder vooraf de hele 500 GB te committen.

## VM-specificaties

| Resource | Waarde | Reden |
|----------|--------|-------|
| vCPU | 2 (host type) | PBS is I/O-gebonden, niet CPU-gebonden. Twee cores dekken chunking plus de verify-job parallel. |
| RAM | 4 GB, ballooning uit | Officiele minimum plus marge voor de filesystem-cache op de datastore. Ballooning uit omdat fluctuaties in beschikbaar geheugen de chunk-hashing vertragen. |
| OS-disk | 32 GB op NVMe thin pool | Minimaal voor Debian plus PBS plus wat journald-headroom. Snelle disk voor OS-operations. |
| Datastore-disk | 500 GB qcow2 op SATA-directory | Thin-provisioned groei tot 500 GB. De qcow2-wrapper geeft een schone file die zelf gebackupt kan worden via vzdump zonder de datastore-inhoud te kopieren. |
| Netwerk | vmbr0 tagged VLAN 10 | Servers-zone bij de PVE-hosts zelf. Geen extra firewall-regels nodig voor inter-node backup-traffic. |
| Boot | `scsi0` only | Na installatie is de ISO losgekoppeld en de boot-order aangepast. Anders booten reboots opnieuw de installer. |
| Guest agent | Actief | PVE kan dan VM-status en IP-adressen uitlezen zonder in te loggen. |
| onboot | 1 | Start automatisch mee met Node 1, zodat backups na een host-reboot beschikbaar blijven. |

## Datastore: ext4 op qcow2

PBS vraagt tijdens setup om een filesystem voor de datastore. Twee opties zijn redelijk op deze hardware:

**ext4** is de eenvoudigste keuze. Geen extra tuning, geen RAM-overhead voor caches, geen extra configuratie voor snapshots. Alles wat de datastore hoeft te doen is schijfruimte bieden aan PBS, die zijn eigen deduplicatie en chunk-management doet.

**ZFS** biedt native compressie, bitrot-detectie via scrubs en snapshots. Op een single-disk setup verdwijnt het grootste ZFS-voordeel: er is geen redundantie tussen disks, dus checksums kunnen corruptie opsporen maar niet herstellen. De ARC cache vraagt standaard ongeveer 1 GB extra RAM, wat voor dit profiel geen extra waarde oplevert.

De keuze werd ext4. De redundantie-laag zit één niveau hoger: het qcow2-bestand waar de datastore in leeft, wordt meegenomen in de `pbs-self-backup`-job (zie hieronder), en de kwaliteit van PVE-niveau qcow2-snapshots is de fallback bij filesystem-problemen.

Het filesystem is gemount op `/mnt/datastore/main` en via `proxmox-backup-manager disk fs create` in één stap gecreëerd en als PBS-datastore `main` geregistreerd.

## Integratie met PVE

Tokens, geen wachtwoorden. PVE benadert PBS met een API-token die gekoppeld is aan een dedicated service-account, niet met `root@pam` en een wachtwoord. Dat levert drie winsten op:

1. Het wachtwoord van de service-account hoeft nooit gebruikt te worden en kan als random gegenereerde waarde in PBS blijven zonder dat iemand het kent of onthoudt.
2. Revocatie is specifiek: als een token lekt, trek je dat ene token in. De rest van de authenticatie blijft functioneel.
3. De ACL is scoped. De token heeft alleen `DatastoreBackup`-rechten op `/datastore/main`, niks anders.

De setup in PBS:

```
proxmox-backup-manager user create pve-sync@pbs --password <random>
proxmox-backup-manager acl update /datastore/main DatastoreBackup --auth-id pve-sync@pbs
proxmox-backup-manager acl update / Audit --auth-id pve-sync@pbs
proxmox-backup-manager user generate-token pve-sync@pbs pve-backup
proxmox-backup-manager acl update /datastore/main DatastoreBackup \
    --auth-id 'pve-sync@pbs!pve-backup'
```

De `Audit`-role op `/` geeft de token alleen lees-toegang tot de fingerprint-informatie, niet tot de inhoud van andere datastores. De `DatastoreBackup`-role op `/datastore/main` is expliciet zowel op de user als op de token gezet, wat vereist is: tokens erven niet automatisch alle rechten van hun user.

Aan de PVE-kant wordt PBS toegevoegd als cluster-wide storage:

```
pvesm add pbs pbs-main \
    --server 10.0.10.<pbs-ip> \
    --datastore main \
    --username 'pve-sync@pbs!pve-backup' \
    --password <token-secret> \
    --fingerprint <sha256> \
    --content backup
```

De fingerprint vervangt certificaatverificatie tegen een publieke CA. PBS gebruikt een self-signed certificaat bij installatie, wat in een intern netwerk de juiste keuze is. De fingerprint pint de verbinding: PVE weigert te verbinden als het certificaat op de andere kant niet exact deze SHA256-hash heeft.

## Backup-strategie

De kern van de setup zijn twee jobs die samen de circular dependency wegwerken.

**Job 1: `weekly-backup`**

Deze job dekt alles behalve PBS zelf. Zondag 03:00, snapshot-mode, zstd-compressie. Target: PBS. Scope: alle VMs en containers met VM 180 expliciet uitgesloten. De retentie wordt niet door deze job afgedwongen maar door de PBS-side prune-job (zie Datastore-onderhoud), zodat het `pve-sync@pbs` service-account alleen `DatastoreBackup`-rechten nodig heeft en geen `Datastore.Prune`.

```
vzdump: weekly-backup
    schedule sun 03:00
    compress zstd
    enabled 1
    exclude 180
    mailnotification failure
    mode snapshot
    notes-template {{guestname}}
    storage pbs-main
    all 1
```

**Job 2: `pbs-self-backup`**

Deze job bestaat puur om de circular dependency te breken. Maandag 04:00, dezelfde snapshot-mode, vaste scope: alleen VM 180. Target: de oude SATA-directory-storage, dezelfde bulk-disk waar Job 1 vroeger naartoe schreef.

```
vzdump: pbs-self-backup
    schedule mon 04:00
    compress zstd
    enabled 1
    mailnotification failure
    mode snapshot
    notes-template {{guestname}} (pbs-self)
    prune-backups keep-weekly=2
    storage local-sata
    vmid 180
```

De redenering is dat een PBS-VM die zichzelf naar PBS backupt geen recovery-pad heeft als de PBS-datastore onbereikbaar raakt. Met deze tweede job ligt er elke week een gewone vzdump van de PBS-VM op een andere storage. Bij een catastrofe is het recovery-pad: herstel VM 180 uit `local-sata`, start hem op, en de datastore (die als apart qcow2-bestand op dezelfde SATA-disk staat) blijft ongemoeid want die zit niet in de VM-backup.

De retentie op Job 2 is bewust korter (twee weken in plaats van vier). De configuratie van PBS verandert zelden, dus oude snapshots zijn minder waardevol dan bij de productie-VMs en CTs.

## Datastore-onderhoud

Drie terugkerende jobs op de PBS-kant houden de datastore gezond. Alle drie vallen in hetzelfde zondag-venster kort na de wekelijkse backup-run, zodat ze pas actief worden als de nieuwe backup-data binnen is.

| Job | Schema | Taak |
|-----|--------|------|
| Garbage collection | Zondag 05:00 | Ruimt dedupe-chunks op die niet meer door een snapshot gereferenceerd worden |
| Prune | Zondag 05:30 | Dwingt retention af: keep-last 2, keep-weekly 4, keep-monthly 3 |
| Verify | Zondag 06:00 | Leest chunks terug en controleert hun checksums tegen de index |

Daarnaast staat `verify-new=true` op de datastore, wat betekent dat PBS elke nieuwe backup direct na upload verifieert. Dat vangt corruptie op voordat die in de retention-vensters verdwijnt.

De GC-job gebruikt PBS zijn eigen twee-fase algoritme: eerst markeert het alle chunks die nog in gebruik zijn, daarna verwijdert het de ongemarkeerde. De job kan draaien terwijl er backups lopen. Het is een veilige operatie die niet afgestemd hoeft te worden op de Job 1 / Job 2 run-schema's.

De retentie wordt volledig door deze PBS-side prune-job afgehandeld, niet door de PVE backup-job. Het `pve-sync@pbs` service-account heeft alleen `DatastoreBackup`-rechten en geen `Datastore.Prune`. Dit volgt het principe van minimale rechten: de backup-client mag data schrijven, maar de retentie-beslissingen liggen bij PBS zelf. De combinatie `keep-last 2, keep-weekly 4, keep-monthly 3` zorgt ervoor dat recente backups extra lang blijven en maandelijkse backups een langere tijdlijn bieden. De lagen kosten samen nauwelijks extra disk doordat de meeste oude maandelijkse backups vrijwel volledig deduperen met de nieuwere.

## Eerste testrun

Na configuratie zijn CT 150 en CT 151 handmatig gebackupt naar PBS om de flow end-to-end te verifieren.

| Target | Data | Compressed | Duur | Doorvoer |
|--------|------|------------|------|----------|
| CT 151 (monitoring-stack) | 4.01 GiB | 2.03 GiB | 33 s | 126 MiB/s |
| CT 150 (n8n-stack) | 4.09 GiB | 1.72 GiB | 42 s | 99 MiB/s |

Beide backups slaagden bij de eerste poging. De `verify-new=true`-instelling betekent dat PBS de chunks direct na upload heeft gecontroleerd, en de `pbs-main`-storage toonde in `pvesm list pbs-main` beide nieuwe snapshots met hun volume-IDs. De datastore-bezetting stond op ongeveer 0.8% van 500 GB na twee backups, wat overeenkomt met de verwachte compressiegraad.

De eerste automatische run van Job 1 staat gepland voor de eerstvolgende zondagnacht. Mail-notificatie bij failure is aan, dus stilzwijgend falen wordt niet mogelijk.

## Resultaat

De backup-infrastructuur staat op drie lagen:

1. **PBS-datastore** voor de productie-VMs en CTs met deduplicatie, integrity-checks en incremental-forever opslag
2. **SATA-directory** als recovery-pad voor de PBS-VM zelf, los van de datastore die hij beheert
3. **Wekelijkse maintenance-jobs** die garbage collection, retention en verificatie in die volgorde laten draaien op een zondag-onderhoudsvenster

Deze opstelling geeft alles wat een moderne backup-infrastructuur hoort te leveren, zonder de tweede fysieke host te vereisen die de officiele aanbeveling voorstelt. De prijs is de complexiteit van een tweede backup-job en een stukje operationele discipline: de recovery-procedure voor PBS zelf loopt via de oude vzdump-flow, niet via PBS. Die procedure is gedocumenteerd en blijft in beeld zolang Job 2 elke maandagochtend succesvol draait.
