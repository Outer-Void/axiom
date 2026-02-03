#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
warpdrive — universal task runner (test/lint/run)
Usage: warpdrive {test|lint|run} [args...]
Behavior:
  - Prefers local venv if .venv exists
  - test: pytest
  - lint: ruff .
  - run : python main.py (fallback: python -m app)
EOF
}

CMD="${1:-}"
[ "$CMD" = "-h" ] || [ "$CMD" = "--help" ] && { usage; exit 0; }
shift || true

if [ -f ".venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

case "$CMD" in
  test)
    command -v pytest >/dev/null 2>&1 || { echo "warpdrive: pytest not found" >&2; exit 1; }
    pytest "$@"
    ;;
  lint)
    command -v ruff >/dev/null 2>&1 || { echo "warpdrive: ruff not found" >&2; exit 1; }
    ruff . "$@"
    ;;
  run)
    if [ -f "main.py" ]; then
      python main.py "$@"
    elif [ -d "app" ]; then
      python -m app "$@"
    else
      echo "warpdrive: no main.py or app module found" >&2
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
