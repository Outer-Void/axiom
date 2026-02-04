#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "AXIOM: [preflight] $*"; }
die() { echo "AXIOM: [preflight] ERROR: $*" >&2; exit 1; }

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
log "Repo root: $REPO_ROOT"

required_files=(
  "$REPO_ROOT/py_venv.sh"
  "$REPO_ROOT/cockpit/bin/overwatch.sh"
  "$REPO_ROOT/cockpit/bin/cockpit.sh"
  "$REPO_ROOT/cockpit/bin/blux10k.sh"
)

missing=()
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    missing+=("$file")
  fi
done

shopt -s nullglob
armory_libs=("$REPO_ROOT/armory/core/lib/"*.sh)
shopt -u nullglob

if [[ ${#armory_libs[@]} -eq 0 ]]; then
  missing+=("$REPO_ROOT/armory/core/lib/*.sh")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '%s\n' "AXIOM: [preflight] Missing required files:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

log "Ensuring executable permissions"

chmod_targets=(
  "$REPO_ROOT/axiom.sh"
  "$REPO_ROOT/launch.sh"
  "$REPO_ROOT/armory/core/bin/armory"
  "$REPO_ROOT/armory/core/bin/armory-run"
)

shopt -s nullglob
chmod_targets+=("$REPO_ROOT/cockpit/bin/"*.sh)
chmod_targets+=("$REPO_ROOT/armory/"*.sh)
chmod_targets+=("$REPO_ROOT/cockpit/install/"*.sh)
shopt -u nullglob

for target in "${chmod_targets[@]}"; do
  if [[ -e "$target" && ! -x "$target" ]]; then
    chmod +x "$target"
  fi
done

log "Preflight complete"
