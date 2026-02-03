#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
gravgrep — fast recursive code search (imports/refs)
Usage: gravgrep "pattern" [path]
Examples:
  gravgrep "import blux" .
  gravgrep "from blux"  .
EOF
}

PATTERN="${1:-}"
TARGET="${2:-.}"
[ "$PATTERN" = "-h" ] || [ "$PATTERN" = "--help" ] && { usage; exit 0; }
[ -n "$PATTERN" ] || { usage; exit 1; }

cd "$TARGET" 2>/dev/null || { echo "gravgrep: cannot cd into: $TARGET" >&2; exit 1; }

if command -v rg >/dev/null 2>&1; then
  rg --hidden --glob '!.git/*' --glob '!.venv/*' --glob '!__pycache__/*' --glob '!.pytest_cache/*' "$PATTERN" .
else
  grep -RIn --exclude-dir=.git --exclude-dir=.venv --exclude-dir=__pycache__ --exclude-dir=.pytest_cache "$PATTERN" . || true
fi
