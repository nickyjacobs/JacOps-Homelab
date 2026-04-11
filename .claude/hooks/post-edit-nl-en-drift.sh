#!/usr/bin/env bash
#
# post-edit-nl-en-drift.sh
#
# PostToolUse hook (Write). Waarschuwt SOFT als een NL-bestand gewijzigd
# wordt zonder dat de EN-tegenhanger ook recent is aangeraakt. Exit 0,
# alleen stderr-output.
#
# Doel: drift voorkomen tussen NL-leidende en EN-mirror documenten.

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

# Alleen voor *.nl.md files
if [[ "$file_path" != *.nl.md ]]; then
    exit 0
fi

# Bepaal de EN-tegenhanger
en_path="${file_path%.nl.md}.md"

# Check 1: bestaat de tegenhanger?
if [[ ! -f "$en_path" ]]; then
    echo "[nl-en-drift] WARN: Mist EN-tegenhanger voor $file_path" >&2
    echo "  Verwacht: $en_path" >&2
    echo "  Suggestie: maak het bestand aan, of draai /sync-translation" >&2
    exit 0
fi

# Check 2: is de tegenhanger ouder dan 7 dagen vergeleken met de NL-versie?
nl_mtime=$(stat -f %m "$file_path" 2>/dev/null || stat -c %Y "$file_path" 2>/dev/null || echo 0)
en_mtime=$(stat -f %m "$en_path" 2>/dev/null || stat -c %Y "$en_path" 2>/dev/null || echo 0)

if [[ "$nl_mtime" -eq 0 ]] || [[ "$en_mtime" -eq 0 ]]; then
    exit 0
fi

age_diff=$((nl_mtime - en_mtime))
seven_days=$((7 * 24 * 60 * 60))

if [[ "$age_diff" -gt "$seven_days" ]]; then
    days=$((age_diff / 86400))
    echo "[nl-en-drift] WARN: $en_path is ${days} dagen ouder dan $file_path" >&2
    echo "  Suggestie: draai /sync-translation $file_path om drift te fixen" >&2
fi

exit 0
