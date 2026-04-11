---
name: commit-policy
description: Git commit, push en branch-conventies. Nicky commit altijd zelf, Claude doet maximaal stagen en commit-message voorstellen
---

# Commit policy

Deze repo is publiek. Elke commit is zichtbaar voor altijd op GitHub. Daarom strikte regels.

## Hard rules — wat Claude NIET mag

Deze commando's zijn op de **deny**-lijst in `settings.json`. Ze worden tegengehouden voordat ze draaien:

- `git commit` (in welke vorm dan ook, ook met `--amend`)
- `git push` (in welke vorm dan ook, ook met `--force`)
- `git reset --hard`
- `git rebase` (op gepushte commits)
- `git filter-repo` (history rewrite)
- `git branch -D` (force delete)
- `--no-verify` of `--no-gpg-sign` flags op welk git-commando dan ook

Probeer deze niet te omzeilen via `bash -c`, `eval`, of subshells. De deny-rule pakt elke variant.

## Wat Claude WEL mag

- `git status`
- `git diff` (alle vormen: staged, unstaged, met en zonder paden)
- `git log` (alle vormen)
- `git show`
- `git add <specifieke paden>` — altijd specifieke paden, nooit `git add -A` of `git add .`
- `git restore --staged <pad>` om iets uit staging te halen
- Een commit-message **voorstellen** als tekst, zodat Nicky hem kan kopiëren

## Commit-message format

Wanneer Claude een commit-message voorstelt:

- **Eerste regel**: korte titel, max 70 karakters, imperatief ("Add", "Fix", "Update", niet "Added"). Geen punt aan het einde
- **Lege regel**
- **Body**: paragrafen of bullets met "waarom", niet "wat". De diff toont al wat er is veranderd
- **Geen** `Co-Authored-By: Claude` trailer
- **Geen** `Generated with Claude Code` footer
- **Geen** emoji in commit-messages

Voorbeeld:

```
Add proxmox storage, networking, VM hygiene and monitoring docs

Closes the Phase 0 open item for additional Proxmox documentation
from the roadmap. Four new docs in proxmox/:

- 04-storage: thin provisioning, discard/TRIM, capacity monitoring
- 05-networking: VLAN-aware bridge, firewall layers, corosync
- 06-vm-hygiene: naming, tags, required settings, review flow
- 07-monitoring: reachability vs host metrics, Beszel roadmap

All docs in both NL and EN. READMEs updated with the new entries.
```

## Branches

- **Primary branch**: `main`. Geen `master`, geen `develop` op deze repo
- **Werk in main** voor solo-werk. PR-flow is overdone voor een solo-portfolio
- **Feature branches alleen** als een grotere refactor risico op halve commits oplevert. Naam-conventie: `<onderwerp>-<korte-beschrijving>`

## Stage-discipline

- Stage altijd specifieke paden: `git add proxmox/04-storage.nl.md proxmox/04-storage.md`
- Nooit `git add -A` of `git add .` — pakt per ongeluk untracked files mee zoals lokale notes
- Voor commit: altijd `git status` om te verifiëren wat staged is
- `git diff --cached` om de staged wijzigingen te zien voor de commit-suggestie

## Pre-commit checks

Claude moet altijd voor het stagen:

1. `git status` om de staat te zien
2. `./scripts/validate.sh <pad>` op wijzigingen om placeholder-discipline en NL/EN sync te checken
3. Een mentale check op de twijfelgevallen uit `security-first.md`

Als validate faalt: meld het, los het op, draai opnieuw. Geen "ik commit hem en fix later".

## Pull requests

Voor deze repo: niet in gebruik. Solo-portfolio, alle commits gaan rechtstreeks naar `main` door Nicky. Mocht dat veranderen (samenwerking, externe contributor):

- `gh pr create` is een bash command op de allow-lijst
- Claude mag PR-tekst voorstellen, body opstellen, checklist genereren
- `gh pr merge` blijft op deny — Nicky merget zelf

## Wat te doen bij een fout

- **Per ongeluk een verkeerd bestand staged**: `git restore --staged <pad>`. Lokale wijzigingen blijven
- **Per ongeluk een placeholder gemist en het is staged maar niet gecommit**: stage opnieuw na correctie
- **Per ongeluk een placeholder gemist en het is gecommit maar niet gepushed**: Nicky maakt een nieuwe commit met de fix. Geen `--amend` op shared history
- **Per ongeluk een placeholder gemist en het is gepushed**: stop, meld aan Nicky, log in `lessons-learned.nl.md`. Mogelijk `git filter-repo`-traject voor secret-rotation. Dit is een incident, geen routinecorrectie

## Globale conventie

Deze regels gelden bovenop de globale `~/.claude/CLAUDE.md`-regels van Nicky:

> "Nooit `Co-Authored-By: Claude` of vergelijkbare trailer toevoegen aan commits.
> Nooit "Generated with Claude Code" footer toevoegen.
> Commits zijn van Nicky alleen."

Deze repo herhaalt die regels expliciet omdat het een publieke repo is en de zichtbaarheid permanent is.
