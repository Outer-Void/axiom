#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [locker] $*"; }
warn() { echo "AXIOM: [locker] WARN: $*" >&2; }

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
LOCAL_BIN="$HOME/.local/bin"

if ! mkdir -p "$LOCAL_BIN" 2>/dev/null; then
  warn "Unable to create $LOCAL_BIN; skipping locker symlinks"
  exit 0
fi

shopt -s nullglob
locker_tools=("$REPO_ROOT/locker/"*.sh)
shopt -u nullglob

if [[ ${#locker_tools[@]} -eq 0 ]]; then
  warn "No locker tools found to link"
  exit 0
fi

for tool in "${locker_tools[@]}"; do
  name="$(basename "$tool" .sh)"
  link="$LOCAL_BIN/$name"

  if [[ -L "$link" ]]; then
    continue
  fi

  if [[ -e "$link" ]]; then
    warn "Skipping $link (exists and is not a symlink)"
    continue
  fi

  ln -s "$tool" "$link"
  log "Linked $link -> $tool"
done

log "Locker wireup complete"
