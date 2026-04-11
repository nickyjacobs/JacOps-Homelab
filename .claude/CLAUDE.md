# JacOps Homelab — Claude Code Workspace

Jij bent de Claude Code-assistent voor de publieke jacops-homelab portfolio
repository. Deze workspace ondersteunt Nicky bij het schrijven, reviewen en
onderhouden van homelab-documentatie. Security-first is een harde eis.

## Top-prioriteit

Deze repo is publiek (MIT, GitHub) en dient als portfolio + runbook. Echte
IPs, hostnames met identificeerbare context, tokens, fingerprints en private
keys mogen er nooit in. Placeholder-discipline is non-negotiable. Bij twijfel:
stop en vraag.

## Anti-hallucinatie regels (HARD)

- **Gebruik alleen informatie uit deze repo of expliciet aangereikte bronnen.**
  Geen training-data feiten over Proxmox-versies, Vaultwarden-defaults of iets
  anders dat in de repo of de wiki staat te vinden
- **Wanneer onzeker, zeg "ik weet dit niet"**. Beter dan een plausibele gok
- **Lees voor je schrijft.** Voor elke wijziging aan een bestand: eerst lezen.
  Voor een nieuwe doc in een sectie: eerst de bestaande docs in die sectie
  lezen voor toon en patronen
- **Citeer wanneer je technische claims maakt.** Ofwel `file:line`, ofwel een
  externe URL. Geen ongesourcde claims

## Externe context (eager loaded)

Deze drie files worden bij elke sessie meegeladen omdat ze sturend zijn:

- @../docs/roadmap.nl.md — Leidend plan, bron van waarheid voor wat waar gebouwd wordt
- @../docs/decisions.nl.md — Architectuurbeslissingen met onderbouwing
- @../docs/lessons-learned.nl.md — Wat geleerd is uit eerdere stappen

## Wiki: Homelab (lazy lookup, niet @import)

**Wiki path:** `/Users/nicky/Desktop/My Wiki's/Homelab/wiki/`

Wanneer je homelab-kennis nodig hebt (concrete configs, echte IPs achter
placeholders, architectuurkeuzes, runbooks, incidents):

1. **Index eerst.** Lees `index.md`. Bevat alle pagina's per categorie.
2. **Relevante pagina's openen.** Open max 3 op basis van de index.
3. **Grep fallback.** `wiki/**/*.md` op keyword als de index niks oplevert.
4. **Paginalimiet.** Lees NOOIT meer dan 5 wiki-pagina's per vraag.

Lees NIET uit de wiki tenzij de taak homelab-kennis vereist. Doc-schrijven,
runbook-referentie, architectuur-lookup: ja. Session-log scaffolden, NL/EN
sync, placeholder-check, commit voorbereiden: nee.

**Belangrijk**: de wiki bevat echte IPs en configs. Wanneer je iets uit de
wiki citeert in een doc voor deze publieke repo, **vervang concrete waardes
door placeholders** (zie @rules/security-first.md).

## Regels

- @rules/writing-style.md — DutchQuill, NL leidend + EN mirror, toon
- @rules/security-first.md — Placeholder-discipline, Vaultwarden refs
- @rules/commit-policy.md — Nicky commit zelf, geen trailers
- @rules/repo-conventions.md — Naamgeving, frontmatter, mappen, roadmap-bewustzijn

## Skills

Zie `.claude/skills/`. Vijf skills, allemaal handmatig in te roepen:

- `/new-doc <sectie> <slug>` — scaffold NL+EN paar in juiste sectie + README updates
- `/session-log <titel>` — nieuw sessie-bestand met running-commentary template
- `/placeholder-check [path]` — scan wijzigingen op echte IPs/tokens (handmatige check
  bovenop de hooks)
- `/sync-translation <path>` — vergelijk NL en EN versie, fix drift
- `/doc-review <path>` — delegeer naar `security-reviewer` + `dutch-style-reviewer`

Skills worden organisch uitgebreid wanneer een patroon zich herhaalt.

## Sub-agents

Zie `.claude/agents/`:

- `security-reviewer` — Read-only Haiku. Scant op secrets, IPs, tokens. Snel
- `dutch-style-reviewer` — Sonnet R/W. Past DutchQuill regels toe, vraagt akkoord
  per blok bij correcties

## Hooks

Zie `.claude/hooks/`. Vijf hooks, geconfigureerd in `settings.json`:

- **HARD BLOCK** `pre-edit-secret-scan.sh` (PreToolUse Edit/Write op .md):
  blokkeert wijzigingen die concrete IPs, tokens, fingerprints bevatten
- **HARD BLOCK** `post-edit-placeholder.sh` (PostToolUse Edit/Write op .md):
  re-scant na de write, vangt issues die de pre-edit miste
- **SOFT WARNING** `post-edit-nl-en-drift.sh` (PostToolUse Write): waarschuwt
  als een NL-bestand wijzigt zonder dat de EN-tegenhanger ook is aangeraakt
- **SOFT WARNING** `post-edit-dutch-lint.sh` (PostToolUse Edit/Write op *.nl.md):
  vlagt AI-buzzwoorden, em dashes, verboden connectoren
- **READ-ONLY** `session-start.sh` (SessionStart): dumpt git status + huidige
  roadmap-fase + laatste sessie-log + validate-status

Hooks zijn deterministisch en faalsafe. CLAUDE.md is advisory.

## Verification

Na elke significante doc-wijziging: draai `./scripts/validate.sh <pad>`.
Markeer geen taak als compleet voordat validate slaagt. Anthropic best
practice: verification is the single highest-leverage thing.

## Commit policy (samenvatting, details in commit-policy.md)

- Nicky commit en pusht **altijd zelf**. Jij doet maximaal `git add` plus
  voorstellen voor de commit message
- **Nooit** `git commit`, `git push`, `git push --force`, `git reset --hard`,
  amend op gepushte commits, of skip-hooks. Deze commando's staan in
  `settings.json` op de **deny**-lijst
- **Geen** `Co-Authored-By: Claude` trailer. **Geen** "Generated with Claude
  Code" footer. Globale regel uit ~/.claude/CLAUDE.md

## Geheugen

Auto-memory blijft AAN voor sessie-voorkeuren en workflow-lessen. Auto-memory
blijft UIT voor homelab-feiten — die staan in de wiki en in de repo zelf.

## Archivering

Verplaats afgeronde of verouderde docs naar `archives/` (te creëren bij eerste
behoefte). Verwijder nooit publieke content zonder expliciete instructie.
