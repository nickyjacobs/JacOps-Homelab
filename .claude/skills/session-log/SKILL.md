---
name: session-log
description: Maak een nieuw sessie-log bestand in docs/sessions/ met running-commentary template. Sessions zijn gitignored en blijven lokaal
allowed-tools: Read, Write, Edit, Bash(date:*), Bash(git status:*)
argument-hint: <titel>
---

# /session-log

Scaffold een nieuw sessie-log voor running-commentary tijdens werk-sessies. Bestanden in `docs/sessions/` zijn volledig gitignored en blijven lokaal — ze dienen als persoonlijke audit-trail van wat er per sessie is gebeurd.

## Invoer

`$ARGUMENTS` is de titel van de sessie. Bijvoorbeeld:

- `Vaultwarden deploy CT 162`
- `Fase 1.3 Forgejo deploy`
- `Backup verificatie weekend`

Als titel ontbreekt: vraag Nicky om een korte beschrijvende titel.

## Uitvoering

### 1. Bepaal de datum

`Bash(date +%Y-%m-%d)` voor de huidige datum in ISO-formaat.

### 2. Slug van de titel

Maak een kebab-case slug:

- "Vaultwarden deploy CT 162" → `vaultwarden-deploy-ct-162`
- "Fase 1.3 Forgejo deploy" → `fase-1-3-forgejo-deploy`
- "Backup verificatie weekend" → `backup-verificatie-weekend`

Lowercase, spaties en punten naar `-`, geen speciale tekens.

### 3. Bepaal het bestandspad

`docs/sessions/<YYYY-MM-DD>-<slug>.md`

Check of het bestand al bestaat. Zo ja: vraag of Nicky een ander bestand wil (bijvoorbeeld `-deel-2`) of de bestaande wil bewerken.

### 4. Schrijf het sessie-log

Template:

```markdown
# Sessie <YYYY-MM-DD>: <Titel>

## Doel van de sessie

(Wat is het doel van deze sessie? Eén of twee zinnen.)

## Vooraf

- Status van de repo: (uitvoer van git status, als relevant)
- Fase uit roadmap: (welke fase van docs/roadmap.nl.md raakt deze sessie)
- Pre-requirement: (was er iets dat eerst moest)

## Wat er gedaan is

(Chronologisch, running commentary. Bullet points of korte secties.)

### (Sectie 1)

- ...

### (Sectie 2)

- ...

## Open uit deze sessie

- ...

## Hobbels en lessen

(Wat ging niet zoals verwacht? Wat moet de volgende keer anders?)

- ...

## Volgende stappen

(Wat is de logische volgende stap na deze sessie?)

- ...
```

### 5. Optionele git-status snapshot

Als Nicky in een actieve werk-sessie zit met uncommitted wijzigingen, draai `git status --short` en voeg de output toe onder "Vooraf" als context. Skip als het clean is.

### 6. Meld het resultaat

- Pad van het nieuwe sessie-log
- Vermelding dat het bestand gitignored is en lokaal blijft
- Suggestie: open in editor en begin met het invullen van "Doel van de sessie"

## Wat NIET te doen

- **Geen inhoud verzinnen.** Sessie-logs zijn voor wat er ECHT gebeurt, niet voor speculatie
- **Geen secrets in het log.** Ook al is het lokaal, de regels uit `security-first.md` gelden ook hier — vermijd echte tokens, wachtwoorden, private keys. Verwijs bij naam
- **Geen sessions buiten `docs/sessions/`.** Als de gitignore-pattern wijzigt, breekt de privacy

## Anti-hallucinatie discipline

- Vraag bij twijfel over de scope van de sessie
- Vul "Wat er gedaan is" niet vooraf in — dat is voor running commentary tijdens of na de sessie
- Stel geen volgende stappen voor zonder context van wat er in de sessie gebeurt
