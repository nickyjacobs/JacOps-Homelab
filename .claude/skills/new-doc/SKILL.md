---
name: new-doc
description: Scaffold een nieuw NL+EN doc-paar in de juiste sectie van de jacops-homelab repo, met automatische README-updates
allowed-tools: Read, Write, Edit, Grep, Glob
argument-hint: <sectie> <slug>
---

# /new-doc

Scaffold een nieuw NL+EN doc-paar in een van de top-level secties (network, proxmox, services). Maakt beide bestanden, vult correcte headers in, leest een referentie-doc voor toon, en werkt de submap-README en de root-README bij.

## Invoer

`$ARGUMENTS` heeft het format `<sectie> <slug>`. Bijvoorbeeld:

- `proxmox storage-monitoring` → maakt `proxmox/0X-storage-monitoring.{nl.md,md}`
- `services miniflux` → maakt `services/0X-miniflux.{nl.md,md}`
- `network ipv6-rollout` → maakt `network/0X-ipv6-rollout.{nl.md,md}`

Als input ontbreekt: vraag Nicky om sectie en slug.

## Uitvoering

### 1. Valideer de sectie

Geldige secties zijn `network`, `proxmox`, `services`. Andere namen vragen om expliciete goedkeuring (en aanpassing van `.claude/rules/repo-conventions.md`).

### 2. Bepaal het volgende nummer

Gebruik `Glob` op `<sectie>/[0-9][0-9]-*.nl.md` om bestaande docs te vinden. Het volgende nummer is `max + 1`, zero-padded op twee karakters (`08`, `09`, `10`).

### 3. Check op duplicaat

`Glob` op `<sectie>/*-<slug>.nl.md` — als de slug al bestaat (ook met ander nummer), stop en vraag of Nicky een andere slug wil.

### 4. Lees een referentie-doc voor toon

Read één recente doc uit dezelfde sectie (bijvoorbeeld de hoogst-genummerde). Doel: matchen van toon, headers, structuur, lengte. Niet kopiëren, wel als anchor gebruiken.

### 5. Schrijf de NL-versie

Pad: `<sectie>/<NN>-<slug>.nl.md`. Inhoud:

```markdown
# <Titel in het Nederlands>

🇬🇧 [English](<NN>-<slug>.md) | 🇳🇱 Nederlands

Eén of twee zinnen die uitleggen wat dit document is en waarom het bestaat.

## Uitgangspunt

(Optioneel — wat was er voor deze doc, wat is de aanleiding)

## (Inhoud secties komen hier)

## Resultaat

(Samenvatting van wat dit document oplevert)
```

De titel kun je voorstellen op basis van de slug (`storage-monitoring` → "Storage monitoring"), maar vraag Nicky om bevestiging.

### 6. Schrijf de EN-versie

Pad: `<sectie>/<NN>-<slug>.md`. Identieke structuur, Engelse vertaling van de placeholders. Header link wordt:

```markdown
🇬🇧 English | 🇳🇱 [Nederlands](<NN>-<slug>.nl.md)
```

### 7. Update de submap-README

`<sectie>/README.md` en `<sectie>/README.nl.md` hebben een Contents-tabel. Voeg een nieuwe rij toe in de juiste volgorde (alfabetisch of op nummering — check de bestaande structuur):

```markdown
| [<NN>-<slug>.nl.md](<NN>-<slug>.nl.md) | <korte beschrijving> |
```

En de Engelse pendant in `<sectie>/README.md`.

### 8. Update de root-README status-tabel

`README.md` en `README.nl.md` op repo root hebben een Status-sectie met regels per onderwerp. Voeg een rij toe als de nieuwe doc een nieuw onderwerp introduceert. Anders update je de bestaande rij.

### 9. Meld het resultaat

Geef Nicky een korte samenvatting:

- Twee nieuwe files: `<sectie>/<NN>-<slug>.nl.md` en `.md`
- Twee README-updates: submap NL en EN
- Status-tabel update in root README
- Suggestie: open de NL-versie eerst en vul hem in. EN volgt na NL.

## Wat NIET te doen

- **Geen inhoud verzinnen.** De skill scaffold lege placeholders. Echte content komt van Nicky of uit een ingest van een raw bron in de Homelab wiki
- **Geen frontmatter toevoegen.** Docs in deze repo gebruiken geen YAML frontmatter (zie repo-conventions.md)
- **Geen cross-links naar nog-niet-bestaande docs.** Eerst de doc, dan de cross-links
- **Geen wikilinks (`[[...]]`).** Gewone markdown links: `[tekst](pad.md)`

## Anti-hallucinatie discipline

- Lees altijd de referentie-doc uit stap 4 voor je schrijft. Gebruik geen aanname over de toon
- Bij onzekerheid over headers of structuur: vraag Nicky in plaats van te gokken
- Wat de doc UITEINDELIJK gaat behandelen mag Nicky later invullen. Jouw taak is alleen scaffolden
