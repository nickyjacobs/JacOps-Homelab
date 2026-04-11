#!/usr/bin/env bash
#
# session-start.sh
#
# SessionStart hook. Dumpt git status, huidige roadmap-fase, laatste sessie-log
# en eventuele uncommitted issues naar stdout. Claude leest dit als context bij
# elke sessie-start, zodat de assistent direct grounding heeft in de huidige
# staat van de repo.
#
# Read-only. Geen wijzigingen, geen blokkering.

set -euo pipefail

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$REPO_DIR" 2>/dev/null || exit 0

echo "=== JacOps Homelab — Session Snapshot ==="
echo ""

# Git status
echo "--- git status ---"
if git rev-parse --git-dir > /dev/null 2>&1; then
    git status --short --branch 2>/dev/null || echo "(geen git status beschikbaar)"
else
    echo "(geen git repo)"
fi
echo ""

# Huidige fase uit roadmap.nl.md
if [[ -f "docs/roadmap.nl.md" ]]; then
    echo "--- huidige fase (roadmap.nl.md) ---"
    # Vind de eerste "## Fase" header en de eerste regel onder de Fase die
    # gemarkeerd is als actueel werk (heuristiek: zoek "Komend" of "Volgende")
    grep -nE "^## Fase|^### Komend|^### Gedaan" docs/roadmap.nl.md | head -8 || \
        echo "(geen fase-headers gevonden)"
    echo ""
fi

# Laatste sessie-log
if [[ -d "docs/sessions" ]]; then
    latest_session=$(ls -t docs/sessions/*.md 2>/dev/null | head -1 || true)
    if [[ -n "$latest_session" ]]; then
        echo "--- laatste sessie ---"
        echo "$latest_session"
        # Probeer eerste H1 + eerste 3 bullets te tonen
        head -20 "$latest_session" 2>/dev/null | head -10
        echo ""
    fi
fi

# Recente commits (laatste 5)
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "--- recente commits ---"
    git log --oneline -5 2>/dev/null || echo "(geen log beschikbaar)"
    echo ""
fi

# Eventuele uncommitted .nl.md / .md drift
if git rev-parse --git-dir > /dev/null 2>&1; then
    drift_count=0
    while IFS= read -r f; do
        if [[ "$f" == *.nl.md ]]; then
            en="${f%.nl.md}.md"
            if [[ -f "$en" ]]; then
                nl_mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
                en_mtime=$(stat -f %m "$en" 2>/dev/null || stat -c %Y "$en" 2>/dev/null || echo 0)
                if [[ $((nl_mtime - en_mtime)) -gt 604800 ]]; then
                    drift_count=$((drift_count + 1))
                fi
            fi
        fi
    done < <(git diff --name-only HEAD 2>/dev/null || true)

    if [[ "$drift_count" -gt 0 ]]; then
        echo "--- waarschuwing ---"
        echo "$drift_count NL/EN paar(en) met >7 dagen drift gedetecteerd"
        echo "Suggestie: draai /sync-translation op de relevante paden"
        echo ""
    fi
fi

echo "=== Einde snapshot ==="

exit 0
