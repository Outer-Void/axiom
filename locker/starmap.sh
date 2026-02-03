#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
starmap — generate repo tree with ignore filters
Usage: starmap [depth] [path]
EOF
}

DEPTH="${1:-3}"
TARGET="${2:-.}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

cd "$TARGET" 2>/dev/null || { echo "starmap: cannot cd into: $TARGET" >&2; exit 1; }

IGNORE=".git|.venv|__pycache__|.pytest_cache|node_modules|dist|build"

if command -v tree >/dev/null 2>&1; then
  tree -L "$DEPTH" -I "$IGNORE"
else
  echo "starmap: tree not found; fallback to find."
  find . -maxdepth "$DEPTH" -print | sed 's|^\./||' | grep -Ev "^($IGNORE)(/|$)" || true
fi
