---
name: placeholder-check
description: Handmatige scan op echte IPs, tokens, secrets en andere placeholder-overtredingen in een bestand of subdir
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*)
argument-hint: [path]
---

# /placeholder-check

Handmatige scan-skill bovenop de hooks. De `pre-edit-secret-scan.sh` en `post-edit-placeholder.sh` hooks vangen 95% bij elke write. Deze skill is voor:

- Een complete pre-commit scan op alle gewijzigde bestanden
- Een audit van een specifieke doc vóór review
- Een sanity-check na een grote refactor

## Invoer

`$ARGUMENTS` is optioneel:

- **Geen argument**: scan alle gewijzigde bestanden uit `git diff --name-only HEAD` plus de staged files
- **Path naar bestand**: scan dat ene bestand
- **Path naar directory**: scan alle `.md` files in die directory recursief

## Uitvoering

### 1. Bepaal scope

Geen argument:

```
files=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null)
files=$(echo "$files" | sort -u | grep -E '\.(md|sh|yml|yaml|json)$')
```

Met argument:

- Bestand: scan dat bestand
- Directory: `Glob` op `<dir>/**/*.md`

### 2. Patterns die je scant op

**Hard blocks** (worden door hooks ook gevangen, hier voor consistentie):

| Pattern | Beschrijving |
|---------|-------------|
| `\b10\.0\.[0-9]+\.([2-9]\|[1-9][0-9]+)\b` | Concrete host-IPs in 10.0.x.0/24, exclusief `.1` (gateway-conventie) |
| `\b[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}\b` | Volledige MAC-adressen (zonder XX-mask) |
| `(SHA256:[A-Za-z0-9+/=]{40,}\|[a-f0-9]{40,})` | TLS fingerprints, hex-hashes >40 char |
| `\b(ghp_\|gho_\|ghu_\|ghs_\|ghr_)[A-Za-z0-9]{36}\b` | GitHub PAT prefixes |
| `\b(sk-\|pat-)[A-Za-z0-9]{20,}\b` | OpenAI/Tavily key prefixes |
| `\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.` | JWT tokens |
| `Bearer [A-Za-z0-9_.\-]{20,}` | Bearer token headers |
| `Authorization: \S+` | Authorization headers in code blocks |
| `BEGIN (RSA \|EC \|OPENSSH \|PGP )?PRIVATE KEY` | Private key markers |
| `/root/[a-zA-Z0-9_.-]+\.(txt\|key\|pem\|token)` | Token-paden in /root/ |

**Soft warnings** (rapporteer maar block niet):

| Pattern | Beschrijving |
|---------|-------------|
| `\bfingerprint\b` zonder placeholder | Mogelijk niet-publieke fingerprint |
| `\b(password\|wachtwoord)\s*[:=]\s*\S+` | Password-patronen, ook als comment |
| `[A-Za-z0-9+/]{44}=` | 44-char base64 (mogelijk WireGuard key) |

### 3. Rapporteer

Per hit:

```
[HARD] proxmox/04-storage.nl.md:42 — Concrete host-IP gevonden
  > address 10.0.10.11/24
  Suggestie: vervang door `10.0.10.<node-ip>` of `<node1-ip>`

[SOFT] services/n8n.md:18 — base64 string lijkt WireGuard key
  > prikey = abc...xyz=
  Suggestie: verwijder of vervang door `<wireguard-privkey>`
```

### 4. Samenvattend

- Aantal hard hits: X
- Aantal soft hits: Y
- Bestanden gescand: Z
- Suggestie: bij hard hits, fix voordat je commit. Bij soft hits, beoordeel handmatig

### 5. Exit

Als hard hits: meld duidelijk dat de check heeft gefaald. Stel voor welke wijzigingen nodig zijn voordat de commit door kan.

Als geen hits: meld "PASS — geen issues gevonden". Optioneel: hoeveel regels gescand, hoeveel bestanden.

## Wat NIET te doen

- **Niet automatisch fixen.** Deze skill is read-only voor de scan. Fixes komen via Edit-calls die Nicky goedkeurt
- **Niet de hooks vervangen.** De hooks vangen real-time. Deze skill is voor batch-scans
- **Geen false-positives suppressen** zonder Nicky's akkoord. Als een pattern triggert op iets wat veilig is, leg het uit en vraag of de pattern aangepast moet worden in de hook

## Anti-hallucinatie discipline

- Verzin geen patterns die niet in de lijst staan. Als Nicky een specifiek pattern wil toevoegen, dat hoort in `pre-edit-secret-scan.sh`, niet ad-hoc in de skill-output
- Geen aannames over wat een echte secret is. Een 30-char string kan een random ID zijn of een token. Bij twijfel: rapporteer als soft, niet als hard
