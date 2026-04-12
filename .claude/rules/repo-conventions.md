---
name: repo-conventions
description: Mappenstructuur, naamgeving, README-discipline en roadmap-bewustzijn voor de jacops-homelab repo
---

# Repo conventions

Deze regels beschrijven de structuur van jacops-homelab. Wijken zonder reden veroorzaakt drift en maakt de repo moeilijker te navigeren voor lezers.

## Mappenstructuur (top-level)

```
jacops-homelab/
├── README.md, README.nl.md            # Project-overzicht
├── CONTRIBUTING.md, SECURITY.md       # Standaard repo-meta
├── LICENSE                            # MIT
├── network/                           # Netwerk-architectuur, VLAN, firewall, WireGuard
├── proxmox/                           # Cluster setup, hardening, backups, storage, networking
├── hardware/                          # Cross-cutting fysieke apparatuur: YubiKey
├── services/                          # Per service: n8n, Uptime Kuma, ntfy
├── docs/                              # Roadmap, decisions, lessons-learned, sessions
├── assets/                            # Diagrammen, screenshots, hero images
├── archives/                          # Afgeronde of vervangen content (te creëren bij behoefte)
└── .claude/                           # Claude Code workspace
```

Geen nieuwe top-level mappen zonder expliciete beslissing in `docs/decisions.nl.md`.

## Per-categorie structuur

Elke top-level technische map (`network/`, `proxmox/`, `services/`) volgt:

```
<categorie>/
├── README.md, README.nl.md            # Inhoud-tabel met links naar de docs
├── 01-<onderwerp>.md, 01-<onderwerp>.nl.md
├── 02-<onderwerp>.md, 02-<onderwerp>.nl.md
├── 03-<onderwerp>.md, 03-<onderwerp>.nl.md
├── ...
└── diagrams/                          # Excalidraw, SVG, PNG (optioneel)
```

**Conventies**:

- Nummering met `NN-` prefix (`01-`, `02-`, ..., `10-`, `11-`)
- Kebab-case na het nummer
- README per submap met inhoud-tabel
- NL en EN paren altijd samen aanmaken, nooit één van de twee

## Naamgeving van bestanden

- **Markdown docs**: `<NN>-<slug>.md` en `<NN>-<slug>.nl.md`
- **Diagrammen**: `<NN>-<slug>-<type>.svg`, bijvoorbeeld `01-network-architecture.svg`
- **Session logs**: `YYYY-MM-DD-<slug>.md` in `docs/sessions/` (gitignored)
- **Decisions log**: één bestand `docs/decisions.nl.md` en `docs/decisions.md`, append-only entries gedateerd

Nooit:

- Spaties in bestandsnamen
- Hoofdletters (behalve `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `CLAUDE.md`)
- Datum-prefix in technische docs (gebruik chronologie via git-history of decisions-log)
- `_` in plaats van `-`

## README-discipline

De **root `README.md`** en `README.nl.md` bevatten de status-tabel van het project. Bij elke nieuwe doc of nieuwe service:

1. Werk de status-rij bij (Done/In progress/Planned)
2. Verifieer dat de Navigation-tabel nog klopt
3. Update beide talen tegelijk

De **README per submap** bevat de Contents-tabel met links naar elke doc in die submap. Bij elke nieuwe doc in een submap:

1. Voeg de regel toe
2. Update beide talen
3. Houd de tabel gesorteerd op nummering

## Roadmap-bewustzijn

`docs/roadmap.nl.md` is de bron van waarheid voor wat waar gebouwd wordt. Voor je iets schrijft over een service, lees eerst de actuele fase:

- **Fase 0**: Hardening en docs-afronding (april 2026, voltooid)
- **Fase 1**: Foundation deployments — PBS, Vaultwarden, Forgejo, Forgejo Runner, Miniflux, Beszel, Dockge, ccusage. Volgorde is bindend
- **Fase 2**: eJPT practice stack — DVWA, Metasploitable 2, Windows 10 Eval (parallel aan Fase 1)
- **Fase 3**: Na 17 mei 2026 — Velociraptor, Wazuh, MISP, DFIR-IRIS, Sliver, GOAD, SysReptor

**Schrijf niet over services die nog niet gedeployed zijn alsof ze klaar zijn**. Een doc over Vaultwarden mag bestaan zodra er content is uit een echte deploy, niet daarvoor. Voor planning-content: gebruik `docs/roadmap.nl.md`, niet `services/`.

## Decisions en lessons-learned

`docs/decisions.nl.md` en `docs/lessons-learned.nl.md` zijn append-only.

- **Decisions**: gedateerde entries voor architectuurkeuzes, met context, alternatieven, en gekozen oplossing
- **Lessons learned**: gedateerde entries voor wat geleerd is uit incidenten of hobbels

Nooit oude entries herschrijven. Bij een change-of-mind: nieuwe entry die de oude markeert als `superseded` en verklaart waarom.

## Sessions

`docs/sessions/` is **volledig gitignored**. Sessie-logs zijn lokale running-commentary van wat er tijdens een werk-sessie gebeurde. Ze worden niet publiek gedeeld.

De `/session-log` skill schrijft hier nieuwe bestanden. Format: `YYYY-MM-DD-<slug>.md`.

Wat in een sessie-log hoort:

- Doel van de sessie
- Wat er gedaan is (chronologisch)
- Open items / wat blijft hangen
- Hobbels en lessen
- Volgende stappen

Wat niet in een sessie-log hoort:

- Echte secrets (zelfde regels als de publieke repo, ook al is de file lokaal)
- Werkgerelateerde data

## Frontmatter

Docs in deze repo gebruiken **geen** YAML frontmatter. Frontmatter is voor LLM-onderhouden corpus (de Homelab wiki), niet voor menselijk leesbare publieke docs. Uitzondering: rules in `.claude/rules/` hebben wel frontmatter (Claude Code spec).

## Cross-references

- **Tussen docs in deze repo**: gewone relatieve markdown links
- **Naar README's**: `[README](../README.nl.md)` of `[overview](../README.md)`
- **Naar de Homelab wiki**: niet in publieke docs. De wiki is privé

## Wat te doen bij een grote refactor

Als de structuur substantieel verandert (nieuwe top-level map, hernoeming van een hele subboom):

1. Bespreek met Nicky voor je begint
2. Log de beslissing in `docs/decisions.nl.md`
3. Werk in een aparte branch als de refactor meerdere commits gaat duren
4. Update alle README's en cross-references in dezelfde commit-set als de hernoeming
