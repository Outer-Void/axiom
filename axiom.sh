#!/usr/bin/env bash
set -Eeuo pipefail

# axiom.sh — Full systems installer (root orchestrator)
# Builds the entire AXIOM environment in staged order.

############################################
# Helpers
############################################

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
# Pre-flight safety checks
############################################

preflight_checks() {
  log "Running pre-flight safety checks"
  
  # Check disk space (minimum 500MB free)
  local min_space_mb=500
  local available_kb
  available_kb=$(df -k "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
  
  if [ -n "$available_kb" ] && [ "$available_kb" != "0" ]; then
    local available_mb=$((available_kb / 1024))
    if [ $available_mb -lt $min_space_mb ]; then
      log_warn "Low disk space: ${available_mb}MB available, ${min_space_mb}MB recommended"
    else
      log "Disk space: ${available_mb}MB available"
    fi
  fi
  
  # Check for conflicting processes
  local conflicts=()
  for proc in "${conflicts[@]}"; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
      log_warn "Process $proc is running (may cause conflicts)"
    fi
  done
  
  # Validate we're in the correct directory structure
  local required_dirs=("cockpit" "locker" "cockpit/bin" "cockpit/core" "cockpit/config")
  for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      die "Missing required directory: $dir"
    fi
  done
  
  log "Pre-flight checks passed"
}

############################################
# Python virtual environment (root)
############################################

PY_VENV="$REPO_ROOT/py_venv.sh"

if [[ -f "$PY_VENV" ]]; then
  log "Initializing Python virtual environment"
  # MUST be sourced
  # shellcheck source=/dev/null
  . "$PY_VENV"
else
  die "py_venv.sh not found at repo root"
fi

export AXIOM_VENV_ACTIVE=1

############################################
# Config
############################################

DEFAULT_MANIFEST="cockpit/install/MANIFEST"
MANIFEST="${AXIOM_MANIFEST:-$DEFAULT_MANIFEST}"

DRY_RUN="${AXIOM_DRY_RUN:-0}"
NONINTERACTIVE="${AXIOM_NONINTERACTIVE:-0}"

############################################
# CLI args
############################################

usage() {
  cat <<'USAGE'
Usage: ./axiom.sh [options]

Options:
  --manifest <path>     Use a custom manifest file
  --dry-run             Print actions without executing
  --noninteractive      Disable prompts for child scripts
  --skip-preflight      Skip safety checks (not recommended)
  -h, --help            Show help

Env vars:
  AXIOM_MANIFEST=<path>
  AXIOM_DRY_RUN=1
  AXIOM_NONINTERACTIVE=1
USAGE
}

SKIP_PREFLIGHT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      shift
      [[ $# -gt 0 ]] || die "--manifest requires a path"
      MANIFEST="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --noninteractive)
      NONINTERACTIVE="1"
      shift
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

############################################
# Preflight (unless skipped)
############################################

if [[ "$SKIP_PREFLIGHT" == "0" ]]; then
  preflight_checks
else
  log_warn "Skipping pre-flight safety checks"
fi

log "Repo root : $REPO_ROOT"
log "Manifest  : $MANIFEST"

if [[ "$NONINTERACTIVE" == "1" ]]; then
  export AXIOM_NONINTERACTIVE=1
fi

############################################
# Execute staged installers
############################################

run_stage() {
  local rel="$1"
  local path="$REPO_ROOT/$rel"
  local started ended duration

  [[ -z "$rel" || "$rel" =~ ^# ]] && return 0
  [[ -f "$path" ]] || die "Missing installer: $rel"
  [[ -x "$path" ]] || die "Installer not executable: $rel"

  log "==> RUN: $rel"
  started=$(date +%s)

  if [[ "$DRY_RUN" == "1" ]]; then
    log "    (dry-run)"
    return 0
  fi

  # Execute with timeout protection
  timeout 1800 "$path"  # 30 minute timeout
  local exit_code=$?
  
  ended=$(date +%s)
  duration=$((ended - started))
  
  if [[ $exit_code -eq 124 ]]; then
    log_warn "<== TIMEOUT: $rel (exceeded 30 minutes)"
    return 1
  elif [[ $exit_code -ne 0 ]]; then
    log_warn "<== FAILED: $rel (exit code: $exit_code, duration: ${duration}s)"
    return $exit_code
  else
    log "<== OK:  $rel (duration: ${duration}s)"
    return 0
  fi
}

log "Starting AXIOM full install sequence"

# Track overall success
OVERALL_SUCCESS=0
STAGE_COUNT=0
FAILED_STAGES=()

run_stage_list() {
  local stages=("$@")
  local line
  for line in "${stages[@]}"; do
    STAGE_COUNT=$((STAGE_COUNT + 1))
    if ! run_stage "$line"; then
      OVERALL_SUCCESS=1
      FAILED_STAGES+=("$line")
      if [[ "$NONINTERACTIVE" == "1" ]]; then
        log_warn "Stage failed, but continuing due to non-interactive mode"
      else
        printf "Stage failed: %s\nContinue anyway? [y/N] " "$line"
        read -r continue_response
        if [[ ! "$continue_response" =~ ^[Yy]$ ]]; then
          log "Installation aborted by user"
          return 1
        fi
      fi
    fi
  done
  return 0
}

if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if ! run_stage_list "$line"; then
      break
    fi
  done < "$MANIFEST"
else
  log_warn "Manifest not found: $MANIFEST"
  log "Running explicit staged installers instead."
  default_stages=(
    "cockpit/bin/cockpit.sh"
    "cockpit/bin/blux10k.sh"
  )
  run_stage_list "${default_stages[@]}"
fi

############################################
# Installation summary
############################################

log "AXIOM installation sequence completed"

if [[ $OVERALL_SUCCESS -eq 0 ]]; then
  log "✅ SUCCESS: All $STAGE_COUNT stages completed successfully"
else
  log_warn "⚠️  PARTIAL: $STAGE_COUNT stages run, ${#FAILED_STAGES[@]} failed"
  if [[ ${#FAILED_STAGES[@]} -gt 0 ]]; then
    log_warn "Failed stages:"
    for stage in "${FAILED_STAGES[@]}"; do
      log_warn "  - $stage"
    done
  fi
fi

# Final instructions
if [[ -f "$REPO_ROOT/launch.sh" && -x "$REPO_ROOT/launch.sh" ]]; then
  log ""
  log "To launch AXIOM cockpit:"
  log "  ./launch.sh"
fi

exit $OVERALL_SUCCESS
