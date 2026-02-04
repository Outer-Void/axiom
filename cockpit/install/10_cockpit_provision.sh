#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [cockpit] $*"; }
die() { echo "AXIOM: [cockpit] ERROR: $*" >&2; exit 1; }

resolve_repo_root() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  local script_dir
  script_dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  cd -P "$script_dir/../.." >/dev/null 2>&1 && pwd
}

REPO_ROOT="$(resolve_repo_root)"
COCKPIT="$REPO_ROOT/cockpit/bin/cockpit.sh"

[[ -x "$COCKPIT" ]] || die "Missing or non-executable: $COCKPIT"

log "Starting cockpit provisioning"
"$COCKPIT"
log "Cockpit provisioning complete"
