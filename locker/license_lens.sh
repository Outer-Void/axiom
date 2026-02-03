#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
license_lens — generate dependency license report (pip-licenses)
Usage: license_lens [output.md]
Notes:
  - Installs pip-licenses into active environment if missing
EOF
}

OUT="${1:-licenses.md}"
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

PY="python3"
if [ -f ".venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
  PY="python"
fi

command -v "$PY" >/dev/null 2>&1 || { echo "license_lens: python not found" >&2; exit 1; }

if ! "$PY" -m pip show pip-licenses >/dev/null 2>&1; then
  echo "Installing pip-licenses..."
  "$PY" -m pip install --quiet pip-licenses
fi

echo "Generating license report -> $OUT"
pip-licenses --format=markdown > "$OUT"
echo "Done."
