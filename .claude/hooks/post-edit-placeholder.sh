#!/usr/bin/env bash
#
# post-edit-placeholder.sh
#
# PostToolUse hook (Edit|Write). Re-scant het bestand vanaf disk na de write.
# Vangt issues die de pre-edit hook miste door variabele expansie of
# multi-step writes. Zelfde patterns als pre-edit.
#
# HARD BLOCK: exit 2 bij hits. Roll-back is niet automatisch — Claude leest
# de stderr en moet zelf corrigeren via een nieuwe Edit.

set -euo pipefail

input=$(cat)

file_path=$(echo "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(tool_input.get('file_path', ''))
except Exception:
    print('')
")

# Skip als geen file_path
if [[ -z "$file_path" ]]; then
    exit 0
fi

# Alleen markdown
if [[ "$file_path" != *.md ]]; then
    exit 0
fi

# Bestand moet bestaan
if [[ ! -f "$file_path" ]]; then
    exit 0
fi

# Scan het file vanaf disk
hits=$(python3 << PYEOF
import sys, re

with open("$file_path", 'r') as f:
    text = f.read()

hits = []

# Zelfde patterns als pre-edit-secret-scan.sh
for m in re.finditer(r'\b10\.0\.\d+\.(\d+)\b', text):
    last_octet = int(m.group(1))
    if last_octet not in (1, 254):
        hits.append(('CONCRETE_IP', m.group(0), 'Vervang door <node-ip> of <ct-ip>'))

for m in re.finditer(r'\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b', text):
    if 'XX' not in m.group(0).upper():
        hits.append(('MAC_ADDRESS', m.group(0), 'Vervang door BC:24:11:XX:XX:XX'))

for m in re.finditer(r'(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{30,40}', text):
    hits.append(('GITHUB_PAT', m.group(0)[:20] + '...', 'Vervang door <github-pat>'))

for m in re.finditer(r'\b(sk-|pat-)[A-Za-z0-9]{20,}\b', text):
    hits.append(('API_KEY', m.group(0)[:20] + '...', 'Vervang door <api-key>'))

for m in re.finditer(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', text):
    hits.append(('JWT_TOKEN', m.group(0)[:30] + '...', 'Vervang door <jwt-token>'))

for m in re.finditer(r'Bearer\s+[A-Za-z0-9_.\-]{20,}', text):
    hits.append(('BEARER_TOKEN', m.group(0)[:30] + '...', 'Vervang door Bearer <token>'))

for m in re.finditer(r'Authorization:\s*\S{20,}', text):
    hits.append(('AUTH_HEADER', m.group(0)[:30] + '...', 'Vervang door <token>'))

for m in re.finditer(r'-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----', text):
    hits.append(('PRIVATE_KEY', m.group(0), 'Verwijder, verwijs naar Vaultwarden'))

for m in re.finditer(r'/root/[a-zA-Z0-9_.-]+\.(txt|key|pem|token|secret)', text):
    hits.append(('ROOT_TOKEN_PATH', m.group(0), 'Verwijs naar Vaultwarden bij naam'))

for m in re.finditer(r'\b[a-fA-F0-9]{40,}\b', text):
    val = m.group(0)
    if len(val) == 40 and re.search(r'(commit|hash|sha)\b.*' + re.escape(val[:8]), text, re.IGNORECASE):
        continue
    hits.append(('HEX_HASH', val[:20] + '...', 'Mogelijk token of fingerprint, verifieer'))

for m in re.finditer(r'\b[A-Za-z0-9+/]{43}=', text):
    hits.append(('WG_KEY', m.group(0)[:20] + '...', 'WireGuard key, vervang door <wireguard-privkey>'))

for tag, snippet, suggestion in hits:
    print(f'[{tag}] {snippet}')
    print(f'   → {suggestion}')
PYEOF
)

if [[ -n "$hits" ]]; then
    echo "[post-edit-placeholder] HARD BLOCK op $file_path" >&2
    echo "" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Fix de bovenstaande issues. De wijziging is geschreven maar valt buiten" >&2
    echo "de placeholder-discipline uit .claude/rules/security-first.md." >&2
    exit 2
fi

exit 0
