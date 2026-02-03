#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
nebula_boot — create/refresh .venv and install deps
Usage: nebula_boot [path]
Notes:
  - Creates .venv if missing
  - Upgrades pip
  - Installs requirements.txt if present
EOF
}

TARGET="${1:-.}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

cd "$TARGET" 2>/dev/null || { echo "nebula_boot: cannot cd into: $TARGET" >&2; exit 1; }

PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || { echo "nebula_boot: $PY not found" >&2; exit 1; }

echo "== NEBULA_BOOT: ENV BOOTSTRAP =="
echo "Path: $(pwd)"
echo "Python: $("$PY" --version 2>/dev/null || true)"

if [ ! -d ".venv" ]; then
  echo "Creating .venv..."
  "$PY" -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip

if [ -f "requirements.txt" ]; then
  echo "Installing requirements.txt..."
  pip install -r requirements.txt
else
  echo "No requirements.txt found; skipping."
fi

echo "Done. Activated venv is ready."
