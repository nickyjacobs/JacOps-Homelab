#!/usr/bin/env bash
#
# pre-edit-secret-scan.sh
#
# PreToolUse hook (Edit|Write). Scant de inkomende content op concrete IPs,
# tokens, fingerprints, MAC-adressen en andere placeholder-overtredingen.
# HARD BLOCK: exit 2 bij hits, met duidelijke stderr-output zodat Claude
# zelf kan corrigeren.
#
# Scoped op markdown-bestanden (*.md). Shell scripts en YAML worden niet
# gescand om recursie en false-positives te voorkomen.

set -euo pipefail

# Lees JSON van stdin
input=$(cat)

# Extract file_path en content via Python (robuuste JSON parsing)
file_path=$(echo "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('file_path', ''))
except Exception:
    print('')
")

content=$(echo "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    # Write heeft 'content', Edit heeft 'new_string', MultiEdit heeft 'edits'
    out = tool_input.get('content', '') or tool_input.get('new_string', '')
    if not out and 'edits' in tool_input:
        out = '\n'.join(e.get('new_string', '') for e in tool_input['edits'])
    print(out)
except Exception:
    print('')
")

# Skip als geen file_path
if [[ -z "$file_path" ]]; then
    exit 0
fi

# Alleen markdown scannen — shell scripts en yml zijn buiten scope
if [[ "$file_path" != *.md ]]; then
    exit 0
fi

# Skip als geen content (defensief)
if [[ -z "$content" ]]; then
    exit 0
fi

# Patterns scannen via Python. Content komt via env var omdat pipe-stdin
# door de heredoc wordt overschreven. Geen sys.exit — bash beslist op output.
export SCAN_CONTENT="$content"
hits=$(python3 << 'PYEOF'
import os, re

text = os.environ.get('SCAN_CONTENT', '')
hits = []

# 1. Concrete host-IPs in 10.0.x.0/24, exclusief .0 (subnet), .1/.254 (gateway)
for m in re.finditer(r'\b10\.0\.\d+\.(\d+)\b', text):
    last_octet = int(m.group(1))
    if last_octet not in (0, 1, 254):
        hits.append(('CONCRETE_IP', m.group(0), 'Vervang door <node-ip> of <ct-ip>'))

# 2. Volledige MAC-adressen (geen XX-mask)
for m in re.finditer(r'\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b', text):
    if 'XX' not in m.group(0).upper():
        hits.append(('MAC_ADDRESS', m.group(0), 'Vervang laatste 3 octets door XX:XX:XX'))

# 3. GitHub PAT prefixes (flexibel: 30-40 chars na prefix)
for m in re.finditer(r'(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{30,40}', text):
    hits.append(('GITHUB_PAT', m.group(0)[:20] + '...', 'Vervang door <github-pat>'))

# 4. OpenAI/Tavily-achtige keys
for m in re.finditer(r'\b(sk-|pat-)[A-Za-z0-9]{20,}\b', text):
    hits.append(('API_KEY', m.group(0)[:20] + '...', 'Vervang door <api-key>'))

# 5. JWT tokens
for m in re.finditer(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', text):
    hits.append(('JWT_TOKEN', m.group(0)[:30] + '...', 'Vervang door <jwt-token>'))

# 6. Bearer tokens (>20 char na het Bearer woord)
for m in re.finditer(r'Bearer\s+[A-Za-z0-9_.\-]{20,}', text):
    hits.append(('BEARER_TOKEN', m.group(0)[:30] + '...', 'Vervang door Bearer <token>'))

# 7. Authorization headers met token
for m in re.finditer(r'Authorization:\s*\S{20,}', text):
    hits.append(('AUTH_HEADER', m.group(0)[:30] + '...', 'Vervang token door <token>'))

# 8. Private key markers
for m in re.finditer(r'-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----', text):
    hits.append(('PRIVATE_KEY', m.group(0), 'Verwijder, verwijs naar Vaultwarden bij naam'))

# 9. /root/ paths met token/key files
for m in re.finditer(r'/root/[a-zA-Z0-9_.-]+\.(txt|key|pem|token|secret)', text):
    hits.append(('ROOT_TOKEN_PATH', m.group(0), 'Verwijs naar Vaultwarden in plaats van /root/-pad'))

# 10. Hex-strings >40 chars (mogelijk hash/token, vraagt context)
# Note: Docker image digests (sha256:abc...) kunnen hier false positives geven.
# De whitelist-heuristiek onder (zoeken naar 'commit|hash|sha' in dezelfde tekst)
# dekt commit hashes. Voor Docker digests: voeg 'digest' of 'sha256:' toe in de
# omringende tekst om ze te whitelisten.
for m in re.finditer(r'\b[a-fA-F0-9]{40,}\b', text):
    val = m.group(0)
    # Whitelist git commit hashes (40 char exact, vaak na woord 'commit')
    if len(val) == 40 and re.search(r'(commit|hash|sha)\b.*' + re.escape(val[:8]), text, re.IGNORECASE):
        continue
    hits.append(('HEX_HASH', val[:20] + '...', 'Mogelijk token of fingerprint, verifieer'))

# 11. WireGuard private keys (44-char base64 met = einde)
for m in re.finditer(r'\b[A-Za-z0-9+/]{43}=', text):
    hits.append(('WG_KEY', m.group(0)[:20] + '...', 'WireGuard key vervang door <wireguard-privkey>'))

# 12. Absolute /Users/ paden (macOS username + filesystem leak)
for m in re.finditer(r'/Users/[a-zA-Z0-9_.-]+/', text):
    hits.append(('USER_PATH', m.group(0), 'Vervang door ~/ of <local-path>'))

for tag, snippet, suggestion in hits:
    print(f'[{tag}] {snippet}')
    print(f'   → {suggestion}')
PYEOF
)

if [[ -n "$hits" ]]; then
    echo "[pre-edit-secret-scan] HARD BLOCK op $file_path" >&2
    echo "" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Fix de bovenstaande issues volgens .claude/rules/security-first.md" >&2
    echo "voordat je deze edit opnieuw probeert." >&2
    exit 2
fi

exit 0
