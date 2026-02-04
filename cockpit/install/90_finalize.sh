#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [finalize] $*"; }
warn() { echo "AXIOM: [finalize] WARN: $*" >&2; }

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

ENV_EXAMPLE="$REPO_ROOT/cockpit/config/.env.example"
ENV_FILE="$REPO_ROOT/cockpit/config/.env"

if [[ -f "$ENV_EXAMPLE" && ! -f "$ENV_FILE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  log "Created cockpit/config/.env from .env.example"
elif [[ ! -f "$ENV_EXAMPLE" ]]; then
  warn "Missing $ENV_EXAMPLE; skipping .env creation"
fi

cat <<'SUMMARY'
AXIOM: [finalize] Installed.
AXIOM: [finalize] Next: run ./launch.sh
SUMMARY
