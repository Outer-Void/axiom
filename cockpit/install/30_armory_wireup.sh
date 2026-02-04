#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [armory] $*"; }
warn() { echo "AXIOM: [armory] WARN: $*" >&2; }
die() { echo "AXIOM: [armory] ERROR: $*" >&2; exit 1; }

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

ARMORY_BIN="$REPO_ROOT/armory/core/bin/armory"
ARMORY_RUN_BIN="$REPO_ROOT/armory/core/bin/armory-run"

[[ -f "$ARMORY_BIN" ]] || die "Missing armory binary: $ARMORY_BIN"
[[ -f "$ARMORY_RUN_BIN" ]] || die "Missing armory-run binary: $ARMORY_RUN_BIN"

for bin in "$ARMORY_BIN" "$ARMORY_RUN_BIN"; do
  if [[ ! -x "$bin" ]]; then
    chmod +x "$bin"
  fi
done

log "Armory core binaries ready"

LOCAL_BIN="$HOME/.local/bin"
if mkdir -p "$LOCAL_BIN" 2>/dev/null; then
  for name in armory armory-run; do
    target="$REPO_ROOT/armory/core/bin/$name"
    link="$LOCAL_BIN/$name"
    if [[ -L "$link" || ! -e "$link" ]]; then
      ln -sf "$target" "$link"
      log "Linked $link -> $target"
    else
      warn "Skipping $link (already exists and is not a symlink)"
    fi
  done
else
  warn "Unable to create $LOCAL_BIN; skipping symlinks"
fi

log "Armory wireup complete"
