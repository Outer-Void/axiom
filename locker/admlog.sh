#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
admlog — create an architecture decision log entry
Usage: admlog "Title of decision" [path]
Creates:
  docs/decisions/YYYYMMDD_HHMM_title.md
EOF
}

TITLE="${1:-}"
TARGET="${2:-.}"
[ "$TITLE" = "-h" ] || [ "$TITLE" = "--help" ] && { usage; exit 0; }
[ -n "$TITLE" ] || { usage; exit 1; }

cd "$TARGET" 2>/dev/null || { echo "admlog: cannot cd into: $TARGET" >&2; exit 1; }

mkdir -p docs/decisions

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g'
}

TS="$(date +"%Y%m%d_%H%M")"
SLUG="$(slugify "$TITLE")"
FILE="docs/decisions/${TS}_${SLUG}.md"

cat > "$FILE" <<EOF
# Decision: $TITLE

**Date:** $(date -u +"%Y-%m-%d %H:%M UTC")
**Status:** proposed | accepted | superseded

## Context
- What problem are we solving?
- What constraints exist (Termux/proot, licensing, portability, etc.)?

## Decision
- What did we choose?

## Consequences
- What gets better?
- What gets worse?
- What becomes easier/harder?

## Alternatives Considered
- Option A:
- Option B:

EOF

echo "Created: $FILE"
