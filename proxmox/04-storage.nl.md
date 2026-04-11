# Storage

🇬🇧 [English](04-storage.md) | 🇳🇱 Nederlands

Dit document verdiept de storage-laag van het Proxmox cluster. De basistabel uit [01-cluster-setup.nl.md](01-cluster-setup.nl.md) beschrijft welke storage er is en waar die op draait. Deze doc legt uit hoe die lagen samenwerken, hoe ruimte gemeten wordt, en welke operationele discipline nodig is om een thin-provisioned cluster niet stilletjes uit ruimte te laten lopen.

## Uitgangspunt

Het cluster draait op twee nodes met een bewust asymmetrische storage-opzet. Node 1 heeft een extra SATA-disk die Node 2 niet heeft, en dat verschil dicteert welke workloads op welke node terechtkomen. De always-on applicatiecontainers en de backup-infrastructuur staan op Node 1, terwijl Node 2 vrij blijft voor lab-VMs die niet permanent draaien.

De Proxmox-installer maakt bij een standaard-setup drie storage-entries aan: `local` (directory), `local-lvm` (LVM-thin pool) en eventueel extra directory-storage voor losse disks. Die indeling is hier overgenomen zonder aanpassingen, met één toevoeging: de SATA-disk op Node 1 is handmatig als directory-storage `local-sata` toegevoegd na de installatie.

## Disk-indeling

De werkelijke bruikbare ruimte verschilt van de marketing-capaciteit op de disks. Onderstaande tabel geeft de gemeten situatie, niet de labels op de hardware.

| Node | Disk | Totaal | `pve-root` | `local-lvm` thin pool | Directory storage |
|------|------|--------|------------|------------------------|-------------------|
| Node 1 | NVMe | 238 GB | 69 GB | 141 GB | — |
| Node 1 | SATA | 953 GB | — | — | 953 GB (`local-sata`) |
| Node 2 | NVMe | 238 GB | 69 GB | 141 GB | — |

`pve-root` bevat de Debian-installatie plus de Proxmox-binaries, ISO-uploads en LXC-templates. De rest van de NVMe gaat op in de thin pool waar VM- en containerdisks uit getrokken worden. De SATA-disk op Node 1 is exclusief voor bulk-opslag: de PBS-datastore (als qcow2-bestand) en de self-backup van PBS zelf.

## Storage-entries en wat erin zit

De Proxmox storage-configuratie in `/etc/pve/storage.cfg` koppelt fysieke locaties aan logische storage-entries. Elke entry heeft een content-type dat bepaalt wat erin mag.

| Entry | Type | Locatie | Content | Shared | Gebruik |
|-------|------|---------|---------|--------|---------|
| `local` | Directory | `/var/lib/vz` op `pve-root` | `iso`, `vztmpl`, `snippets`, `backup` | Nee | ISO-uploads, LXC-templates, cloud-init snippets |
| `local-lvm` | LVM-thin | `pve/data` thin pool | `images`, `rootdir` | Nee | VM-disks en container rootfs |
| `local-sata` | Directory | `/mnt/pve/local-sata` op HDD | `images`, `rootdir`, `backup`, `iso`, `vztmpl` | Nee | PBS-datastore qcow2, PBS self-backup, grote wegwerp-VMs |
| `pbs-main` | Proxmox Backup Server | VM 180 `pbs-01` | `backup` | Nee | Wekelijkse backup-targets van Job 1 (zie [03-backups.nl.md](03-backups.nl.md)) |

Content-types zijn de rem die voorkomt dat er per ongeluk ISO's in een thin pool terechtkomen, of backups naar een storage die niet groot genoeg is om ze te houden. Een storage-entry weigert content die niet op het `content`-veld staat.

Geen van de entries is `shared`. Twee-node clusters met lokale storage kunnen geen live-migratie doen, en live-migration over shared storage vraagt infrastructuur (NFS of Ceph) die in dit cluster niet bestaat. Migratie tussen nodes loopt via de `qm migrate` plus `--with-local-disks`-flag, wat de disk-inhoud over het netwerk kopieert. Dat is trager dan live, maar werkt voor geplande verhuizingen zoals een node-reboot.

## Thin provisioning in de praktijk

LVM-thin provisioning is de standaard voor VM- en containerdisks op dit cluster. Het mechanisme is simpel: een VM met een 60 GB disk reserveert niet direct 60 GB uit de thin pool. De pool houdt bij hoeveel blocks er echt geschreven zijn, en geeft die aan de VM terug.

Dat heeft drie gevolgen die bij elke deploy meetellen.

**Overcommit is mogelijk, en gevaarlijk.** Je kunt tien VMs met elk een 60 GB disk op een 141 GB pool aanmaken zolang die VMs samen niet meer dan 141 GB daadwerkelijk schrijven. Bij de elfde schrijfactie die de pool vol zet, begint alles te klappen: VM-filesystems gaan in read-only of raken corrupt. De pool heeft geen zachte limiet, hij heeft een harde grens.

**De pool-vulling moet gemonitord worden, niet de som van de disk-groottes.** `pvesm status` toont hoeveel GB de pool als totaal heeft, niet hoeveel VMs er samen voor gereserveerd staan. De relevante cijfers komen uit `lvs -o +data_percent`:

```
# lvs -o +data_percent pve
  LV              VG  Attr       LSize    Data%
  data            pve twi-aotz-- 141.43g  42.67
  root            pve -wi-ao---- 69.37g
```

De `Data%`-kolom op de `data` LV is de enige waarde die ertoe doet. Stijgt die boven de tachtig procent, dan is het tijd om ofwel disks op te schonen ofwel naar de directory-storage te verhuizen voor groeiende workloads.

**Trimmen is nodig om vrijgekomen ruimte terug te geven aan de pool.** Een VM die een bestand verwijdert, ziet zelf meteen vrije ruimte terug in zijn eigen filesystem. De thin pool eronder merkt daar niks van, tenzij de guest een TRIM-commando stuurt. Zonder TRIM groeit het `Data%`-percentage monotoon omhoog, ook als workloads data weggooien.

## Discard en TRIM

Discard staat standaard uit op VM-disks die door de installer of via `qm create` worden aangemaakt. Elke VM die op de thin pool staat hoort dit aan te hebben. De configuratie zit in de VM-config:

```
scsi0: local-lvm:vm-180-disk-0,discard=on,iothread=1,ssd=1
```

Drie vlaggen werken samen:

- `discard=on` vertelt Proxmox dat de VM TRIM-commando's mag sturen naar de thin pool. Zonder deze vlag worden ze stil genegeerd.
- `ssd=1` adverteert de disk als SSD aan de guest, wat ertoe leidt dat moderne Linux-distro's hun periodieke `fstrim.timer` inschakelen.
- `iothread=1` laat de storage-I/O op een eigen thread draaien in plaats van de QEMU main loop, wat throughput verbetert bij parallelle workloads.

In de guest moet `fstrim` draaien. Op Debian en Ubuntu is dat standaard aan via `fstrim.timer`, die wekelijks alle gemounte filesystems langsloopt. Je kunt het direct controleren:

```
# systemctl status fstrim.timer
● fstrim.timer - Discard unused filesystem blocks once a week
     Loaded: loaded
     Active: active (waiting)
    Trigger: Mon 2026-04-13 00:04:03 CEST
```

Voor containers werkt het iets anders. LXC-containers delen de host-kernel en hebben geen eigen block-device. De thin pool ziet elke schrijfactie direct, en bij `pct destroy` wordt de container-volume teruggegeven aan de pool. Er is geen TRIM-stap nodig: de pool weet zelf welke blocks weer vrij zijn.

## Directory-storage op de SATA-disk

`local-sata` is geen LVM-thin pool maar een simpele directory op een ext4 filesystem. De keuze is bewust, om twee redenen.

De eerste is dat de SATA-disk voornamelijk wordt gebruikt voor grote bestanden die maar één schrijver hebben: de PBS-datastore als qcow2 en de vzdump-archieven van de PBS self-backup. Voor dat patroon voegt LVM-thin niks toe en introduceert het alleen extra lagen die kunnen falen.

De tweede is dat directory-storage de qcow2-wrapper toelaat die nodig is voor de PBS-setup. De datastore staat als één groot qcow2-bestand op het filesystem, en PBS zelf is de enige die erin schrijft. Bij een herstelactie kan die qcow2 via gewone file-operaties worden benaderd, zonder dat je eerst een LVM-logical-volume hoeft te activeren.

```
# ls -lh /mnt/pve/local-sata/images/180/
total 12G
-rw-r----- 1 root root 500G Apr 11 17:45 vm-180-disk-1.qcow2
```

De `500G` in de listing is de *virtuele* grootte. Het qcow2-bestand groeit mee met de data die PBS erin schrijft, dankzij sparse allocation. Na twee backups stond de werkelijke ruimteverbruik op 12 GB, zoals hierboven te zien.

## Capacity monitoring

Drie commando's geven een volledig beeld van de storage-staat op een node:

```
# pvesm status
Name             Type     Status           Total            Used       Available        %
local             dir     active        73095180         6821756        62534268    9.33%
local-lvm     lvmthin     active       148298752        63280180        85018572   42.67%
local-sata        dir     active       976284752        12288000       914496752    1.26%
```

`pvesm status` is de snelste check. Het toont alle geregistreerde storages met hun totaal, gebruik en percentage. Voor directory-storage is dit accuraat. Voor de thin pool toont het *allocated* versus *free*, wat nuttig is als eerste aanwijzing maar niet hetzelfde als de `Data%`-waarde uit `lvs`.

```
# lvs
  LV     VG  Attr       LSize    Pool Origin Data% Meta%
  data   pve twi-aotz-- 141.43g              42.67  2.14
  root   pve -wi-ao---- 69.37g
  ...
```

`lvs` is de tweede laag. De `Data%` is de harde thin-pool vulling, en `Meta%` is de metadata-pool die thin provisioning zelf bijhoudt. Als `Meta%` richting honderd loopt, raakt de pool zijn administratie kwijt voordat de data-kant vol is. Dat is zeldzaam maar wel dodelijk.

```
# df -h /var/lib/vz /mnt/pve/local-sata
Filesystem                Size  Used Avail Use% Mounted on
/dev/mapper/pve-root       69G  6.5G   60G  10% /
/dev/sdb1                 932G   12G  873G   2% /mnt/pve/local-sata
```

`df -h` geeft de filesystem-waarheid op de directory-storages. Voor `local` is dat dezelfde disk als `pve-root` (samen delend op de NVMe), voor `local-sata` is het de aparte SATA-disk.

Een drempel van tachtig procent op `local-lvm` is het moment waarop er actie komt: uitdunnen, TRIM forceren of disks verhuizen. Tachtig procent op `pve-root` betekent vaak dat logs of templates te lang zijn blijven liggen. Tachtig procent op `local-sata` betekent dat de PBS-datastore richting zijn limiet loopt en dat de retentie strakker moet.

## Backup-flow en storage-koppelingen

De backup-infrastructuur uit [03-backups.nl.md](03-backups.nl.md) raakt alle drie de storage-typen en gebruikt ze op een specifieke manier.

```
            VM-disks op local-lvm                    PBS self-backup
         (Node 1 + Node 2, thin-provisioned)        (vm-180 naar vzdump archief)
                    │                                       │
                    │ Job 1: weekly-backup                   │ Job 2: pbs-self-backup
                    ▼                                       ▼
    ┌─────────────────────────┐                ┌─────────────────────────┐
    │  PBS datastore          │                │  local-sata directory   │
    │  (qcow2 op local-sata)  │                │  (vzdump tar.zst)       │
    └─────────────────────────┘                └─────────────────────────┘
                    │                                       │
                    └──────────────── beide op dezelfde SATA disk ─────┘
```

De enige schijf die de backup-bestanden bevat is de SATA-disk op Node 1. Een fysiek verlies van die disk betekent het verlies van zowel de PBS-datastore als de vzdump-fallback van PBS zelf. Dat is een geaccepteerd risico binnen dit homelab: een tweede fysieke host of een off-site target is niet beschikbaar, en de documentatie in deze repo dient als rebuild-runbook voor de rest.

Vaultwarden krijgt daarboven nog een externe backup-laag (zie toekomstige services-documentatie). Alleen de vault gaat off-site, omdat het verlies van credentials de grootste kater is en tegelijk de kleinste data-set om te versturen.

## Groeipad

Het cluster heeft drie realistische uitbreidingsrichtingen wanneer de huidige disks vollopen.

**Tweede SATA-disk in Node 2.** Op dit moment heeft Node 2 geen bulk-storage. Een tweede SATA-disk daar toevoegen levert een tweede directory-storage op (`local-sata-n2`) die als secundair backup-target kan dienen. Dat geeft een pad om de Job 1 en Job 2 backups fysiek te scheiden: Job 1 naar Node 1 SATA, Job 2 naar Node 2 SATA. Nu delen ze nog dezelfde disk.

**NVMe-upgrade.** De 238 GB NVMe's zijn de bottleneck voor de thin pool. Een upgrade naar 512 GB of 1 TB geeft direct meer ruimte voor VM-disks zonder dat er iets aan de structuur verandert. De migratiestappen zijn: nieuwe disk erbij plaatsen, `pvcreate` en `vgextend pve`, dan `lvextend` op de thin pool. Geen downtime nodig voor de pool-uitbreiding zelf, wel voor de hardware-swap.

**Directory-storage voor grote wegwerp-VMs.** De Windows 10 lab-VM uit [Fase 2 van de roadmap](../docs/roadmap.nl.md) krijgt een 60 GB disk op `local-sata` in plaats van `local-lvm`. Grote oefen-VMs die alleen tijdens sessies draaien horen op trage bulkopslag, niet op de NVMe die de 24/7-containers deelt.

Geen van deze drie is nu urgent. De NVMe-pools staan op 42 procent, de SATA-disk op 2 procent. Het plan is om bij tachtig procent op een van beide actief te worden en niet eerder.

## Resultaat

De storage-laag levert drie dingen:

1. **Snelle rootdisks** voor VMs en containers via de LVM-thin pool op NVMe, met discard en iothread aan zodat de pool netjes blijft.
2. **Bulk-opslag** op de SATA-directory op Node 1 voor backup-data en grote wegwerp-VMs, bewust gescheiden van de primaire workloads.
3. **Voorspelbare monitoring** via `pvesm status` plus `lvs`, met tachtig procent als actiedrempel en de twee-fase backup-setup als fallback als een disk alsnog omvalt.

De asymmetrie tussen Node 1 en Node 2 is geen tekortkoming maar een plaatsingsregel: always-on workloads op Node 1, lab-VMs op Node 2. Elke nieuwe deploy volgt die regel, tenzij er een expliciete reden is om ervan af te wijken.
