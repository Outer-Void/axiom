#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
ARMORY_BIN="$REPO_DIR/core/bin/armory"

usage() {
  cat <<'USAGE'
Usage: armory.sh [command]

Convenience shim for armory/core/bin/armory.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -eq 0 ]; then
  exec "$ARMORY_BIN" help
fi

exec "$ARMORY_BIN" "$@"
