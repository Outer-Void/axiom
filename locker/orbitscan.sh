#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
orbitscan — repo overview snapshot
Usage: orbitscan [path]
EOF
}

TARGET="${1:-.}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

cd "$TARGET" 2>/dev/null || { echo "orbitscan: cannot cd into: $TARGET" >&2; exit 1; }

echo "== ORBITSCAN: REPO OVERVIEW =="
echo "Path: $(pwd)"
echo "User: $(whoami)"
echo

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "-- Git --"
  echo "Branch: $(git branch --show-current 2>/dev/null || echo 'n/a')"
  echo "Status:"
  git status --short || true
else
  echo "-- Git --"
  echo "Not a git repo (or git missing)."
fi
echo

echo "-- Size offenders (top 15 dirs/files) --"
if command -v du >/dev/null 2>&1; then
  du -ah . 2>/dev/null | sort -hr | head -n 15 || true
else
  echo "du not found."
fi
echo

echo "-- Common env/cache markers (maxdepth 4) --"
find . -maxdepth 4 \( -name ".venv" -o -name "__pycache__" -o -name ".pytest_cache" -o -name "node_modules" \) 2>/dev/null | sed 's|^\./||' || true
