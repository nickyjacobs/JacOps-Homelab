---
name: writing-style
description: Schrijfstijl en taal-conventies voor alle markdown content in de jacops-homelab repo
paths: ["**/*.md"]
---

# Writing style

Deze regels gelden voor alle markdown in de repo. Toon-anchor: [`proxmox/02-hardening.nl.md`](../../proxmox/02-hardening.nl.md). Bij twijfel over een formulering: lees die file en match de stijl.

## Taal

- **NL is leidend, EN is mirror**. Elke `<naam>.nl.md` heeft een `<naam>.md` als Engelse pendant
- Bij elke wijziging in een NL-bestand hoort een EN-update binnen 24 uur
- Bestandsnaam-conventie: kebab-case, beschrijvend, geen datum-prefix
- Technische termen die in de praktijk Engels zijn blijven Engels: `LVM-thin`, `qcow2`, `vmbr0`, `Proxmox Backup Server`, `WireGuard`, `VLAN-aware bridge`

## Verboden woorden en patronen

Deze worden door `dutch-lint.sh` gevlagd en horen niet in commits. Als je ze toch nodig hebt, herformuleer.

**AI-buzzwoorden** (vermijden):
- `cruciaal`, `essentieel`, `baanbrekend`, `holistisch`, `toonaangevend`
- `geoptimaliseerd`, `state-of-the-art`, `next-level`, `revolutionair`
- `naadloos`, `moeiteloos`, `briljant`

**Overgebruikte connectoren** (vermijden):
- `bovendien`, `echter`, `tevens`, `desalniettemin`, `derhalve`, `voorts`

**Tekens**:
- Geen em dashes (`—`). Splits in twee zinnen, of gebruik gewone gedachtestreepjes
- Geen ellipsen voor effect (`...`). Wel toegestaan in CLI-output of citaten

## Stijl

- **Actieve schrijfstijl** waar mogelijk. Passief alleen om persoonlijke voornaamwoorden te vermijden
- **Korte en lange zinnen afwisselen**. Alleen-korte leest staccato, alleen-lange leest plakkerig
- **Concrete voorbeelden boven abstracte beschrijvingen**. "De thin pool zit op 42 procent" zegt meer dan "de thin pool heeft nog ruimte"
- **Tabellen voor data, code blocks voor configs, paragrafen voor redenering**. Geen lange opsommingen waar een tabel beter werkt
- **Eén H1 per pagina** (de titel). H2 voor secties. H3 alleen waar nodig

## Structuur per pagina

Elk technisch document volgt deze opbouw:

1. **Korte inleiding** (1-2 zinnen) — wat is dit, waarom bestaat het
2. **Uitgangspunt** of context — wat was er voor deze wijziging, waarom was actie nodig
3. **Inhoud in secties** — concreet, met tabellen en voorbeelden
4. **Resultaat** — samenvatting wat er nu staat

Korte pagina's mogen de Uitgangspunt-sectie weglaten. Lange pagina's krijgen optioneel een `## Gerelateerd`-sectie met cross-links.

## Cross-references

- **Binnen de repo**: gewone relatieve markdown links: `[tekst](../proxmox/04-storage.nl.md)`
- **Naar wiki of externe bronnen**: gebruik geen Obsidian-wikilinks. De repo is publiek, niet alle lezers hebben Obsidian
- **Naar de Homelab wiki**: nooit met direct pad in publieke docs. Verwijs in commit-messages of session-logs, niet in publieke docs zelf

## Dual-language synchronisatie

Bij elke wijziging in een NL-bestand:

1. Werk de NL-versie eerst af
2. Open de EN-tegenhanger
3. Pas dezelfde structuur toe (headers, tabellen, code blocks, links)
4. Vertaal de inhoud, niet woord-voor-woord — herformuleer voor natuurlijk Engels
5. Update `updated`-datum in beide files als ze frontmatter hebben

De `/sync-translation` skill helpt hierbij. De `nl-en-drift.sh` hook waarschuwt soft als de pendant ouder dan 7 dagen is.

## Wat deze regel niet doet

- **Geen frontmatter-eis** voor docs in deze repo. Frontmatter is voor LLM-onderhouden corpus (de Homelab wiki), niet voor menselijk leesbare publieke docs
- **Geen wikilinks**. Die horen in de Homelab wiki, niet hier
