#!/usr/bin/env bash
set -Eeuo pipefail

# launch.sh — Root Overwatch runner
# Activates AXIOM venv, then launches overwatch.sh

die() { echo "AXIOM: ERROR: $*" >&2; exit 1; }
log() { echo "AXIOM: $*"; }
log_warn() { echo "AXIOM: WARN: $*" >&2; }

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
# Validate environment
############################################

validate_environment() {
  log "Validating AXIOM environment"
  
  # Check for required directories
  local required_dirs=("cockpit" "cockpit/bin" "cockpit/core" "cockpit/config")
  for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      die "Missing required directory: $dir"
    fi
  done
  
  # Check for required core files
  local required_core_files=("constants.sh" "log.sh" "platform.sh")
  for file in "${required_core_files[@]}"; do
    if [ ! -f "cockpit/core/$file" ]; then
      die "Missing core library: cockpit/core/$file"
    fi
  done
  
  log "Environment validation passed"
}

validate_environment

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
  log_warn "py_venv.sh not found at repo root"
  log_warn "Attempting to continue without virtual environment"
fi

export AXIOM_RUNTIME=1

############################################
# Locate overwatch.sh with fallback order
############################################

CANDIDATES=(
  "$REPO_ROOT/cockpit/overwatch.sh"
  "$REPO_ROOT/overwatch.sh"
  "$REPO_ROOT/cockpit/bin/overwatch.sh"
)

OVERWATCH=""

for c in "${CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then
    OVERWATCH="$c"
    log "Found overwatch.sh at: $c"
    break
  fi
done

# If still not found, search recursively (but avoid .git directories)
if [[ -z "$OVERWATCH" ]]; then
  log "Searching for overwatch.sh..."
  while IFS= read -r f; do
    OVERWATCH="$f"
    log "Found overwatch.sh at: $f"
    break
  done < <(
    find "$REPO_ROOT" \
      -name ".git" -prune -o \
      -type f -name "overwatch.sh" -print 2>/dev/null | head -1
  )
fi

[[ -n "$OVERWATCH" ]] || die "Could not locate overwatch.sh"

# Validate it's executable
if [[ ! -x "$OVERWATCH" ]]; then
  log_warn "overwatch.sh is not executable, attempting to fix..."
  chmod +x "$OVERWATCH" 2>/dev/null || {
    die "overwatch.sh is not executable and cannot be made executable: $OVERWATCH"
  }
fi

# Verify it's a valid shell script
if ! head -n 1 "$OVERWATCH" | grep -q "^#!"; then
  die "overwatch.sh does not appear to be a valid script: $OVERWATCH"
fi

############################################
# Launch with proper cleanup handling
############################################

cleanup() {
  log "Cleaning up AXIOM runtime"
  # Kill any remaining background processes
  jobs -p | xargs -r kill -9 2>/dev/null || true
  # Reset terminal if possible
  tput cnorm 2>/dev/null || true
  stty sane 2>/dev/null || true
}

# Set up traps
trap cleanup EXIT INT TERM

log "Launching Overwatch: $OVERWATCH"

# Check if we should pass any arguments
if [[ $# -gt 0 ]]; then
  log "Passing arguments to overwatch: $*"
  exec "$OVERWATCH" "$@"
else
  exec "$OVERWATCH"
fi

# exec should replace this process, so we should never reach here
die "Failed to exec overwatch.sh"
