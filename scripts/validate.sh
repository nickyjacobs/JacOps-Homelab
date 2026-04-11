#!/usr/bin/env bash
#
# scripts/validate.sh
#
# Verification gate voor jacops-homelab docs. Combineert:
#   1. Placeholder check (concrete IPs, tokens, secrets)
#   2. NL/EN sync check (paren bestaan, niet meer dan 7 dagen drift)
#   3. Dutch lint (AI-buzzwoorden, em dashes, verboden connectoren)
#
# Anthropic best practice: "verification is the single highest-leverage thing
# you can do." Markeer geen taak als compleet voordat dit script PASS geeft.
#
# Gebruik:
#   ./scripts/validate.sh                  # alle gewijzigde files
#   ./scripts/validate.sh <pad>            # specifiek bestand
#   ./scripts/validate.sh <directory>      # alle .md in directory recursief

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

target="${1:-}"
exit_code=0
hard_count=0
soft_count=0

# ============================================================
# Bepaal welke files te scannen
# ============================================================

declare -a files

if [[ -z "$target" ]]; then
    # Geen argument: alle gewijzigde files uit git
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done < <(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null | sort -u)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "Geen gewijzigde files. Geef een pad als argument om handmatig te scannen."
        exit 0
    fi
elif [[ -d "$target" ]]; then
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$target" -name '*.md' -not -path './.git/*' -not -path './archives/*' -not -path './docs/sessions/*')
elif [[ -f "$target" ]]; then
    files+=("$target")
else
    echo "Pad bestaat niet: $target" >&2
    exit 1
fi

# Filter alleen .md (en .nl.md) — geen sh of yaml
declare -a md_files
for f in "${files[@]}"; do
    [[ "$f" == *.md ]] && md_files+=("$f")
done

if [[ ${#md_files[@]} -eq 0 ]]; then
    echo "Geen markdown files om te scannen."
    exit 0
fi

echo "==> Scanning ${#md_files[@]} markdown file(s)"
echo ""

# ============================================================
# 1. Placeholder check (HARD)
# ============================================================

echo "==> 1. Placeholder check"

for f in "${md_files[@]}"; do
    [[ ! -f "$f" ]] && continue

    hits=$(python3 << PYEOF
import re

with open("$f", 'r') as fh:
    text = fh.read()

hits = []

for m in re.finditer(r'\b10\.0\.\d+\.(\d+)\b', text):
    last_octet = int(m.group(1))
    if last_octet not in (1, 254):
        hits.append(('CONCRETE_IP', m.group(0)))

for m in re.finditer(r'\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b', text):
    if 'XX' not in m.group(0).upper():
        hits.append(('MAC', m.group(0)))

for m in re.finditer(r'(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{30,40}', text):
    hits.append(('GITHUB_PAT', m.group(0)[:20] + '...'))

for m in re.finditer(r'\b(sk-|pat-)[A-Za-z0-9]{20,}\b', text):
    hits.append(('API_KEY', m.group(0)[:20] + '...'))

for m in re.finditer(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}', text):
    hits.append(('JWT', m.group(0)[:30] + '...'))

for m in re.finditer(r'Bearer\s+[A-Za-z0-9_.\-]{20,}', text):
    hits.append(('BEARER', m.group(0)[:30] + '...'))

for m in re.finditer(r'-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----', text):
    hits.append(('PRIVATE_KEY', m.group(0)))

for m in re.finditer(r'/root/[a-zA-Z0-9_.-]+\.(txt|key|pem|token|secret)', text):
    hits.append(('ROOT_PATH', m.group(0)))

for m in re.finditer(r'\b[A-Za-z0-9+/]{43}=', text):
    hits.append(('WG_KEY', m.group(0)[:20] + '...'))

for tag, val in hits:
    print(f'  [{tag}] {val}')
PYEOF
)

    if [[ -n "$hits" ]]; then
        echo "  FAIL: $f"
        echo "$hits"
        hard_count=$((hard_count + 1))
        exit_code=1
    fi
done

if [[ "$hard_count" -eq 0 ]]; then
    echo "  PASS"
fi
echo ""

# ============================================================
# 2. NL/EN sync check (HARD voor missing pair, SOFT voor drift)
# ============================================================

echo "==> 2. NL/EN sync check"

sync_issues=0
for f in "${md_files[@]}"; do
    [[ "$f" != *.nl.md ]] && continue
    en="${f%.nl.md}.md"

    if [[ ! -f "$en" ]]; then
        echo "  FAIL: $f mist EN-tegenhanger ($en)"
        sync_issues=$((sync_issues + 1))
        hard_count=$((hard_count + 1))
        exit_code=1
        continue
    fi

    nl_mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    en_mtime=$(stat -f %m "$en" 2>/dev/null || stat -c %Y "$en" 2>/dev/null || echo 0)

    if [[ "$nl_mtime" -gt 0 ]] && [[ "$en_mtime" -gt 0 ]]; then
        diff=$((nl_mtime - en_mtime))
        if [[ "$diff" -gt 604800 ]]; then
            days=$((diff / 86400))
            echo "  WARN: $en is ${days} dagen ouder dan $f"
            sync_issues=$((sync_issues + 1))
            soft_count=$((soft_count + 1))
        fi
    fi
done

if [[ "$sync_issues" -eq 0 ]]; then
    echo "  PASS"
fi
echo ""

# ============================================================
# 3. Dutch lint (SOFT)
# ============================================================

echo "==> 3. Dutch lint"

lint_issues=0
for f in "${md_files[@]}"; do
    [[ "$f" != *.nl.md ]] && continue
    [[ ! -f "$f" ]] && continue

    file_hits=0

    if grep -nE '\b(cruciaal|essentieel|baanbrekend|holistisch|toonaangevend|geoptimaliseerd|naadloos|moeiteloos)\b' "$f" > /tmp/validate-hits 2>/dev/null; then
        echo "  WARN: $f bevat AI-buzzwoorden:"
        head -3 /tmp/validate-hits | sed 's/^/    /'
        file_hits=1
    fi

    if grep -nE '\b(bovendien|echter|tevens|desalniettemin|derhalve|voorts)\b' "$f" > /tmp/validate-hits 2>/dev/null; then
        echo "  WARN: $f bevat verboden connectoren:"
        head -3 /tmp/validate-hits | sed 's/^/    /'
        file_hits=1
    fi

    # Em dashes alleen in proza tellen — tabel-cellen mogen `—` als leeg-marker
    if awk '/—/ && !/^[[:space:]]*\|/ {print NR": "$0}' "$f" > /tmp/validate-hits 2>/dev/null && [[ -s /tmp/validate-hits ]]; then
        echo "  WARN: $f bevat em dashes in proza:"
        head -3 /tmp/validate-hits | sed 's/^/    /'
        file_hits=1
    fi

    if [[ "$file_hits" -eq 1 ]]; then
        lint_issues=$((lint_issues + 1))
        soft_count=$((soft_count + 1))
    fi
done

rm -f /tmp/validate-hits

if [[ "$lint_issues" -eq 0 ]]; then
    echo "  PASS"
fi
echo ""

# ============================================================
# Verdict
# ============================================================

echo "==> Verdict"
echo "  Hard issues: $hard_count"
echo "  Soft issues: $soft_count"

if [[ "$exit_code" -eq 0 ]]; then
    echo "  PASS — geen hard issues"
else
    echo "  FAIL — fix de hard issues voordat je commit"
fi

exit $exit_code
