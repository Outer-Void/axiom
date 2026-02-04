#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [shell-env] $*"; }
die() { echo "AXIOM: [shell-env] ERROR: $*" >&2; exit 1; }

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
BLUX="$REPO_ROOT/cockpit/bin/blux10k.sh"

[[ -x "$BLUX" ]] || die "Missing or non-executable: $BLUX"

log "Starting shell environment setup"
"$BLUX"
log "Shell environment setup complete"
