#!/usr/bin/env bash
set -euo pipefail

ARMORY_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ARMORY_RUN_BIN="$ARMORY_DIR/core/bin/armory-run"

usage() {
  cat <<'USAGE'
Usage: armory_run.sh -- <command> [args...]

Convenience shim for armory/core/bin/armory-run.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

exec "$ARMORY_RUN_BIN" "$@"
