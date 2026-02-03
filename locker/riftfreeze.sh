#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
riftfreeze — dependency drift detector (pip freeze diff)
Usage:
  riftfreeze baseline     # write baseline.txt from current env
  riftfreeze check        # diff current.txt vs baseline.txt
Env:
  Uses active venv if present; otherwise uses system python.
EOF
}

CMD="${1:-}"
[ "$CMD" = "-h" ] || [ "$CMD" = "--help" ] && { usage; exit 0; }
[ -n "$CMD" ] || { usage; exit 1; }

PY="python3"
if [ -f ".venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
  PY="python"
fi

command -v "$PY" >/dev/null 2>&1 || { echo "riftfreeze: python not found" >&2; exit 1; }

case "$CMD" in
  baseline)
    "$PY" -m pip freeze > baseline.txt
    echo "Wrote baseline.txt"
    ;;
  check)
    "$PY" -m pip freeze > current.txt
    if [ ! -f baseline.txt ]; then
      echo "riftfreeze: baseline.txt not found. Run: riftfreeze baseline" >&2
      exit 1
    fi
    echo "== DRIFT REPORT =="
    diff -u baseline.txt current.txt || true
    ;;
  *)
    usage
    exit 1
    ;;
esac
