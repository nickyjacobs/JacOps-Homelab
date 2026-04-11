---
name: security-first
description: Wat wel en niet in de publieke repo mag, placeholder-conventies, en hoe naar secrets verwezen wordt
---

# Security first

Deze repo is publiek (MIT, GitHub) en dient als portfolio + runbook. Echte infrastructuur-details komen er niet in. Deze regel is non-negotiable. Bij twijfel: stop, vraag, escaleer.

## Wel toegestaan

- **Standaard gateway IPs**: `10.0.10.1`, `10.0.40.1`, `10.0.1.1` — de `.1` van elk subnet is een standaard-conventie en niet host-onthullend
- **VLAN-blokken en subnet-notatie**: `10.0.10.0/24`, `10.0.40.0/24`
- **VMIDs**: VM 180, CT 150, CT 151, CT 162. Deze zijn al gepubliceerd in de roadmap
- **Generieke hostnames die al publiek zijn**: `pbs-01`, `srv-01`, `srv-02` zijn naamconventies, geen identificatie van fysieke hardware
- **Configs**: Docker compose-snippets, network interfaces, systemd units, firewall-regels, sysctl-settings
- **Tool-versies en pinning**: `n8n 2.13.4`, `postgres:16.13-alpine` — version-info hoort bij portfolio
- **CLI-uitvoer** en tool-output zonder host-specifieke identificatie

## Niet toegestaan

- **Concrete host-IPs**: `10.0.10.11`, `10.0.10.12`, `10.0.40.150`, etc. Vervang door placeholders zoals `<node-ip>`, `<node1-ip>`, `<ct-ip>`
- **Volledige MAC-adressen**: vervang door masker `BC:24:11:XX:XX:XX`
- **TLS-certificaat-fingerprints** die niet al publiek zijn
- **API-tokens en bearer tokens**: AWS keys, Cloudflare tokens, PBS API-tokens, GitHub PATs, Tavily keys, alles wat herkenbaar token-shape heeft
- **Wachtwoorden** in welke vorm dan ook, ook niet als voorbeeld
- **Hashes van wachtwoorden** (bcrypt, argon2)
- **Private keys**: SSH, GPG, TLS, WireGuard
- **2FA seeds en backup codes**
- **Recovery keys** van Bitwarden, Vaultwarden, hardware wallets
- **Session cookies en JWT tokens**
- **`.env`-bestanden met echte waarden**
- **Werkdata**: PQR-klantnamen, productie-SIEM-configs, tickets, interne PQR-runbooks

## Placeholder-conventie

Bij elke concrete waarde die uit het wel-toegestaan-rijtje valt:

| Echte waarde (niet toegestaan) | Placeholder (toegestaan) |
|--------------------------------|--------------------------|
| `10.0.10.11/24` | `10.0.10.<node-ip>/24` of `<node1-ip>/24` |
| `10.0.10.12` | `10.0.10.<node2-ip>` |
| `10.0.40.150` | `10.0.40.<ct-ip>` |
| `BC:24:11:A3:5F:7E` | `BC:24:11:XX:XX:XX` |
| `ring0_addr: 10.0.10.11` | `ring0_addr: 10.0.10.<node1-ip>` |
| `<echte-token>` | `<REDACTED>` of `<api-token>` |

## Verwijzen naar secrets

Secrets worden bewaard in Vaultwarden (CT 162, gepland). Verwijs bij **naam**, nooit met waarde:

```markdown
goed:
> Het PBS API-token staat in Vaultwarden als `homelab/pbs-pve-sync-token`.

fout:
> Het PBS API-token is `pbs-sync@pbs!pve-backup=d8f3...`.
```

Pattern: `<scope>/<service>-<purpose>`. Voorbeelden:

- `homelab/pbs-pve-sync-token`
- `homelab/vaultwarden-admin-token`
- `homelab/wireguard-client-nicky-iphone-privkey`
- `homelab/forgejo-runner-registration-token`

## Twijfelgevallen

- **Proxmox TLS fingerprints**: behouden — uniek-maar-niet-geheim, en standaard cluster-config
- **Git commit-hashes**: altijd toegestaan
- **Subnet-notatie zonder host**: toegestaan (`10.0.40.0/24` mag, `10.0.40.150` niet)
- **API endpoints zonder auth**: publieke endpoints mogen, geprivilegieerde endpoints als `<host>/api/admin/...`
- **Hostnames in commit-messages**: zelfde regels als in docs

## Geautomatiseerde verdediging

Drie lagen vangen issues op:

1. **`pre-edit-secret-scan.sh`** (PreToolUse hook) — blokkeert HARD bij Edit/Write op markdown bestanden die patronen zoals concrete IPs, tokens, fingerprints bevatten
2. **`post-edit-placeholder.sh`** (PostToolUse hook) — re-scant na de write, zelfde patronen, zelfde hard block
3. **`scripts/validate.sh`** — kan handmatig draaien op elk bestand of subdir

Deze drie zijn deterministisch. CLAUDE.md is advisory en faalt onder context-rot. Dat is waarom de regels in hooks zitten, niet alleen in tekst.

## Als een secret per ongeluk in de wiki belandt

1. **Verwijder de waarde direct** uit het bestand
2. **Roteer het secret** in de originele dienst (Vaultwarden, PVE, PBS, etc.)
3. **Log het incident** in `docs/lessons-learned.nl.md`
4. **Check de git-historie**: als de waarde gecommit is, gebruik `git filter-repo` om hem volledig te verwijderen — vraag Nicky om dit te draaien

Lokale git-historie is moeilijker te wissen dan je denkt. Voorkomen is beter.
