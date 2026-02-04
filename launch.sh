#!/usr/bin/env bash
set -Eeuo pipefail

# launch.sh — Root Overwatch runner
# Activates AXIOM venv, then launches overwatch.sh

die() { echo "AXIOM: ERROR: $*" >&2; exit 1; }
log() { echo "AXIOM: $*"; }

############################################
# Resolve repo root
############################################

resolve_self() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

REPO_ROOT="$(resolve_self)"
cd "$REPO_ROOT" || die "Failed to cd to repo root: $REPO_ROOT"

############################################
# Activate Python virtual environment
############################################

PY_VENV="$REPO_ROOT/py_venv.sh"

if [[ -f "$PY_VENV" ]]; then
  log "Activating AXIOM Python virtual environment"
  # MUST be sourced
  # shellcheck source=/dev/null
  . "$PY_VENV"
else
  die "py_venv.sh not found at repo root"
fi

export AXIOM_RUNTIME=1

############################################
# Locate overwatch.sh
############################################

CANDIDATES=(
  "$REPO_ROOT/cockpit/bin/overwatch.sh"
  "$REPO_ROOT/cockpit/overwatch.sh"
  "$REPO_ROOT/overwatch.sh"
)

OVERWATCH=""

for c in "${CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then
    OVERWATCH="$c"
    break
  fi
done

if [[ -z "$OVERWATCH" ]]; then
  while IFS= read -r f; do
    OVERWATCH="$f"
    break
  done < <(
    find "$REPO_ROOT" \
      -path "$REPO_ROOT/.git" -prune -o \
      -maxdepth 5 -type f -name "overwatch.sh" -print 2>/dev/null || true
  )
fi

[[ -n "$OVERWATCH" ]] || die "Could not locate overwatch.sh in expected locations"
[[ -x "$OVERWATCH" ]] || die "overwatch.sh is not executable: $OVERWATCH"

############################################
# Launch
############################################

log "Launching Overwatch"
exec "$OVERWATCH" "$@"
