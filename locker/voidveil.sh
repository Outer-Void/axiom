#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
voidveil — ensure standard .gitignore entries (idempotent)
Usage: voidveil [path]
EOF
}

TARGET="${1:-.}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

cd "$TARGET" 2>/dev/null || { echo "voidveil: cannot cd into: $TARGET" >&2; exit 1; }

GI=".gitignore"
touch "$GI"

add_line() {
  local line="$1"
  grep -qxF "$line" "$GI" 2>/dev/null || echo "$line" >> "$GI"
}

echo "== VOIDVEIL: UPDATING $GI =="

add_line "__pycache__/"
add_line ".pytest_cache/"
add_line ".venv/"
add_line ".env"
add_line "dist/"
add_line "build/"
add_line ".mypy_cache/"
add_line ".ruff_cache/"
add_line ".DS_Store"
add_line "node_modules/"

echo "Done. Current $GI entries ensured."
