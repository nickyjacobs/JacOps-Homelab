---
name: doc-review
description: Delegeer review van een doc naar security-reviewer en dutch-style-reviewer subagents, synthetiseer hun rapporten
allowed-tools: Read
argument-hint: <path>
---

# /doc-review

Volledige review van een doc voordat hij gecommit wordt. Delegeert naar twee read-only subagents en consolideert hun bevindingen.

## Invoer

`$ARGUMENTS` is het pad naar de doc die gereviewed moet worden. Bijvoorbeeld:

- `proxmox/04-storage.nl.md`
- `services/05-vaultwarden.md`

Als geen argument: vraag Nicky welk bestand.

## Uitvoering

### 1. Valideer dat het bestand bestaat

Read het bestand om te bevestigen dat het er is en niet leeg. Als het niet bestaat: stop en meld.

### 2. Bepaal wat er gereviewed moet worden

Op basis van het bestandspad:

- **`*.nl.md` of `*.md`**: beide subagents zijn relevant
- **`*.nl.md` specifiek**: beide subagents, maar dutch-style-reviewer doet het zware werk
- **`*.md` (Engels)**: alleen security-reviewer (dutch-style-reviewer is voor NL)

Als het bestand een NL/EN paar is: review beide kanten in één sessie.

### 3. Delegeer naar `security-reviewer` subagent

Roep de subagent expliciet aan met de file path. De subagent is read-only, draait Haiku (snel), en checkt op:

- Echte IPs buiten de toegestane gateway-conventie
- Volledige MAC-adressen
- Tokens, fingerprints, private keys
- /root/-paden met token-files
- Andere placeholder-overtredingen

Vang de output op.

### 4. Delegeer naar `dutch-style-reviewer` subagent (alleen voor NL)

Voor `*.nl.md` files: roep de subagent aan. Sonnet, kan corrigeren. Checkt op:

- AI-buzzwoorden
- Verboden connectoren
- Em dashes
- Toon-match met `proxmox/02-hardening.nl.md`
- Passief vs actief
- Zinslengte-variatie

Vang de output op.

### 5. Synthetiseer

Voeg de twee rapporten samen tot één review:

```
=== Doc Review: <pad> ===

SECURITY (security-reviewer)
✓ Geen hard issues
or
✗ 2 hard issues, 1 soft warning:
  - regel 42: concrete host-IP `10.0.10.11`
  - regel 87: 44-char base64 lijkt WireGuard key

STIJL (dutch-style-reviewer, alleen voor NL)
✓ Toon matched, geen verboden patronen
or
✗ 3 issues:
  - regel 12: woord "essentieel" (verboden)
  - regel 45: em dash
  - sectie 4: passief, suggestie actief

OVERALL: PASS / FAIL
```

### 6. Rapporteer aan Nicky

Geef de samenvatting plus:

- **PASS**: doc is review-ready, suggereer commit met de juiste files
- **FAIL**: lijst van wat gefixed moet worden, suggestie om de subagents te vragen specifieke regels te corrigeren (via dutch-style-reviewer voor stijl, handmatige edit voor security)

### 7. Optioneel: corrigeren

Als Nicky akkoord is met de bevindingen, kun je `dutch-style-reviewer` opnieuw aanroepen met instructie om voorgestelde fixes door te voeren. Dat is een aparte stap — niet automatisch.

## Wat deze skill NIET doet

- **Geen edits zelf**. Deze skill is read-only. Edits komen van een aparte invocation van dutch-style-reviewer of door Nicky direct
- **Geen commit** of stage. Deze skill is alleen review. Commit blijft handwerk van Nicky
- **Geen `validate.sh` vervangen**. validate.sh is voor placeholder + sync + lint; deze skill is voor diepere review met menselijke nuance

## Anti-hallucinatie discipline

- Vertrouw op de subagents — zij zijn de specialisten. Voeg niet je eigen aannames toe aan hun rapport
- Bij onduidelijkheid in een bevinding: vraag de subagent om extra context, niet zelf raden
- Citeer altijd het regelnummer, nooit "ergens in de doc"
