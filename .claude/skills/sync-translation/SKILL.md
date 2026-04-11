---
name: sync-translation
description: Synchroniseer een NL+EN doc-paar — vergelijk structuur, vlag drift, stel sync-edits voor
allowed-tools: Read, Write, Edit, Grep
argument-hint: <path>
---

# /sync-translation

Houd een NL+EN doc-paar synchroon in structuur en inhoud. Werkt op één pair per invocation.

## Invoer

`$ARGUMENTS` is het pad naar één van de twee files in het paar. De skill bepaalt de partner zelf:

- `proxmox/04-storage.nl.md` → partner is `proxmox/04-storage.md`
- `proxmox/04-storage.md` → partner is `proxmox/04-storage.nl.md`

Als geen argument: vraag Nicky welk paar hij wil syncen.

## Uitvoering

### 1. Valideer beide bestanden bestaan

Als de partner ontbreekt: stop en meld het. Suggestie: maak het ontbrekende bestand met `/new-doc` als een nieuwe scaffold, of vraag of dit een bewuste keuze is.

### 2. Read beide files volledig

Niet alleen scannen — volledig lezen.

### 3. Vergelijk structuur

Lijst de headers (H1, H2, H3) in volgorde voor beide bestanden. Vergelijk:

- Aantal headers gelijk?
- Headers in dezelfde volgorde?
- Vertaling consistent (geen "Storage" in NL waar "Storage" wordt gebruikt in EN)?

Vergelijk vervolgens:

- Aantal tabellen
- Aantal code blocks
- Aantal links per pagina
- Lengte van elke sectie (regels)

### 4. Identificeer drift

Drift-typen:

- **Structurele drift**: een sectie bestaat in NL maar niet in EN (of omgekeerd)
- **Inhoudelijke drift**: een tabel heeft andere rijen, een code-block heeft andere config, een paragraaf is veranderd in één maar niet in de ander
- **Datum-drift**: één van de twee is recenter aangepast (uit `git log` of `Bash(date)` op modtime)
- **Link-drift**: een interne link wijst naar een file die niet bestaat in de andere taal

### 5. Rapporteer

```
=== Sync rapport: proxmox/04-storage.nl.md ↔ proxmox/04-storage.md ===

NL: 245 regels, 8 secties, 4 tabellen, 3 code blocks, laatst gewijzigd 2026-04-11
EN: 240 regels, 8 secties, 4 tabellen, 3 code blocks, laatst gewijzigd 2026-04-09

Drift gevonden:

1. STRUCTUREEL: Sectie "## Groeipad" in NL heeft 3 sub-bullets (NVMe upgrade,
   tweede SATA, directory storage). EN heeft 2 sub-bullets (mist "directory
   storage" punt).

2. INHOUDELIJK: Tabel "Disk-indeling" in NL heeft 953 GB voor SATA, EN heeft
   1 TB. NL is meer accuraat (gemeten waarde, niet marketing).

3. STIJL: NL gebruikt "thin pool" 5x, EN wisselt tussen "thin pool" en
   "thin-pool" met streepje. Kies één.
```

### 6. Stel sync-edits voor

Voor elke drift:

- **Klein** (typo, datum-update, link-fix): suggereer de fix, vraag Nicky om akkoord, voer uit met Edit
- **Gemiddeld** (één tabel-rij toevoegen, één paragraaf vertalen): toon de voorgestelde tekst, vraag akkoord per blok
- **Groot** (hele sectie ontbreekt): vraag of Nicky de inhoud zelf wil schrijven, of dat jij een eerste vertaling mag voorstellen op basis van de andere taal

### 7. Apply

Per akkoord van Nicky: doe de Edit. Niet meerdere drift-issues tegelijk fixen — één per keer, met expliciet akkoord.

### 8. Meld het resultaat

- Aantal drift-issues gevonden
- Aantal opgelost in deze sessie
- Aantal openstaand
- Suggestie: draai `./scripts/validate.sh <pad>` om te bevestigen dat NL/EN sync-check nu groen is

## Welke richting is leidend

NL is de leidende taal voor deze repo (zie `repo-conventions.md`). Bij conflict tussen NL en EN:

- Als NL recenter is gewijzigd: NL is leidend
- Als EN recenter is gewijzigd: vraag Nicky welke versie de juiste is — soms heeft hij iets in EN gefixed dat ook NL moet raken
- Bij gelijke datums maar inhoudelijke drift: vraag

## Wat NIET te doen

- **Niet woord-voor-woord vertalen.** Vertaal natuurlijk, en pas formulering aan voor de doeltaal
- **Niet zonder akkoord wijzigen.** Elke Edit vraagt expliciete akkoord, zelfs typos
- **Geen nieuwe content introduceren** die in geen van de twee versies staat. Alleen syncen wat al bestaat in één van de twee

## Anti-hallucinatie discipline

- Vergelijk altijd de daadwerkelijke inhoud, niet wat je verwacht dat erin staat
- Geen aannames over welke versie "correct" is zonder beide te lezen
- Bij twijfel over een vertaling: vraag Nicky
