#!/usr/bin/env bash
#
# post-edit-dutch-lint.sh
#
# PostToolUse hook (Edit|Write op *.nl.md). SOFT WARNING bij AI-buzzwoorden,
# verboden connectoren en em dashes. Exit 0, alleen stderr-output.
#
# Doel: DutchQuill schrijfregels signaleren zonder de workflow te blokkeren.

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

if [[ -z "$file_path" ]]; then
    exit 0
fi

# Alleen voor *.nl.md
if [[ "$file_path" != *.nl.md ]]; then
    exit 0
fi

if [[ ! -f "$file_path" ]]; then
    exit 0
fi

# AI-buzzwoorden
buzzwoorden_pattern='\b(cruciaal|essentieel|baanbrekend|holistisch|toonaangevend|geoptimaliseerd|naadloos|moeiteloos|state-of-the-art)\b'

# Verboden connectoren
connectoren_pattern='\b(bovendien|echter|tevens|desalniettemin|derhalve|voorts)\b'

# Em dashes
em_dash_pattern='—'

issues_found=0

if grep -niE "$buzzwoorden_pattern" "$file_path" > /tmp/dutch-lint-hits 2>/dev/null; then
    echo "[dutch-lint] AI-buzzwoorden in $file_path:" >&2
    head -5 /tmp/dutch-lint-hits >&2
    issues_found=1
fi

if grep -niE "$connectoren_pattern" "$file_path" > /tmp/dutch-lint-hits 2>/dev/null; then
    echo "[dutch-lint] Verboden connectoren in $file_path:" >&2
    head -5 /tmp/dutch-lint-hits >&2
    issues_found=1
fi

# Em dashes alleen in proza, niet in tabel-rijen (waar `|...| — |` als leeg-marker
# een gangbare conventie is). Skip regels die met optionele whitespace + `|` beginnen.
if awk '/—/ && !/^[[:space:]]*\|/ {print NR": "$0}' "$file_path" > /tmp/dutch-lint-hits 2>/dev/null && [[ -s /tmp/dutch-lint-hits ]]; then
    echo "[dutch-lint] Em dashes (—) in proza in $file_path:" >&2
    head -5 /tmp/dutch-lint-hits >&2
    issues_found=1
fi

if [[ "$issues_found" -eq 1 ]]; then
    echo "" >&2
    echo "Zie .claude/rules/writing-style.md voor verboden patronen." >&2
    echo "Soft warning — wijziging gaat door, fix wanneer mogelijk." >&2
fi

rm -f /tmp/dutch-lint-hits

exit 0
