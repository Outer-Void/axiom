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
# Python virtual environment (must be first)
############################################

PY_VENV="$REPO_ROOT/py_venv.sh"

if [[ ! -f "$PY_VENV" ]]; then
  die "py_venv.sh not found at repo root: $PY_VENV"
fi

log "Initializing Python virtual environment"
# MUST be sourced
# shellcheck source=/dev/null
set +u
if ! . "$PY_VENV"; then
  set -u
  die "Failed to source py_venv.sh"
fi
set -u

venv_dir="${VIRTUAL_ENV:-}"

if ! python - <<'PY' >/dev/null 2>&1
import os
import pathlib
import sys
repo_root = pathlib.Path(os.environ.get("REPO_ROOT", "")).resolve()
sys_prefix = pathlib.Path(sys.prefix).resolve()
venv = os.environ.get("VIRTUAL_ENV", "")
venv_ok = bool(venv) and pathlib.Path(venv).resolve() == sys_prefix
inside_repo_venv = bool(repo_root) and sys_prefix == (repo_root / ".venv").resolve()
raise SystemExit(0 if (venv_ok or inside_repo_venv) else 1)
PY
then
  die "Virtual environment sanity check failed (expected active VIRTUAL_ENV or python from .venv)"
fi

if [[ -z "$venv_dir" || ! -d "$venv_dir" ]]; then
  log "VIRTUAL_ENV is not set; using python interpreter from $REPO_ROOT/.venv"
fi

export AXIOM_VENV_ACTIVE=1

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
# Config
############################################

DRY_RUN="${AXIOM_DRY_RUN:-0}"
NONINTERACTIVE="${AXIOM_NONINTERACTIVE:-0}"

############################################
# CLI args
############################################

usage() {
  cat <<'USAGE'
Usage: ./axiom.sh [options]

Options:
  --dry-run             Print actions without executing
  --noninteractive      Disable prompts for child scripts
  --skip-preflight      Skip safety checks (not recommended)
  -h, --help            Show help

Env vars:
  AXIOM_DRY_RUN=1
  AXIOM_NONINTERACTIVE=1
USAGE
}

SKIP_PREFLIGHT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
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

export AXIOM_NONINTERACTIVE="${AXIOM_NONINTERACTIVE:-1}"
NONINTERACTIVE="$AXIOM_NONINTERACTIVE"

############################################
# Execute staged installers
############################################

run_stage() {
  local rel="$1"
  local timeout_seconds="$2"
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

  local exit_code
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$path"
    exit_code=$?
  else
    log_warn "Timeout command not available; running without timeout for $rel"
    "$path"
    exit_code=$?
  fi

  ended=$(date +%s)
  duration=$((ended - started))

  log "==> DONE: $rel (exit code: $exit_code, duration: ${duration}s)"

  if [[ $exit_code -eq 124 ]]; then
    log_warn "<== TIMEOUT: $rel (exceeded ${timeout_seconds}s)"
    return 1
  elif [[ $exit_code -ne 0 ]]; then
    log_warn "<== FAILED: $rel (exit code: $exit_code, duration: ${duration}s)"
    return $exit_code
  fi

  log "<== OK:  $rel (duration: ${duration}s)"
  return 0
}

log "Starting AXIOM full install sequence"

default_stage_list=(
  "cockpit/bin/cockpit.sh"
  "cockpit/bin/blux10k.sh"
  "cockpit/bin/axiom_env.sh"
)

manifest_path="$REPO_ROOT/cockpit/install/MANIFEST"
stage_list=()

if [[ -f "$manifest_path" ]]; then
  log "Loading install manifest: $manifest_path"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ -f "$REPO_ROOT/$line" ]]; then
      stage_list+=("$line")
    else
      log_warn "Manifest stage missing, skipping: $line"
    fi
  done < "$manifest_path"

  if [[ ${#stage_list[@]} -eq 0 ]]; then
    die "Manifest present but no valid stages found: $manifest_path"
  fi
else
  log_warn "Manifest not found, using built-in stage list"
  stage_list=("${default_stage_list[@]}")
fi

STAGE_COUNT=0

for stage in "${stage_list[@]}"; do
  STAGE_COUNT=$((STAGE_COUNT + 1))
  log "Heartbeat: preparing to run stage $stage"
  if ! run_stage "$stage" 1800; then
    log_warn "Stage failed: $stage"
    exit 1
  fi
  log "Heartbeat: completed stage $stage"
done

############################################
# Installation summary
############################################

log "AXIOM installation sequence completed"

log "✅ SUCCESS: All $STAGE_COUNT stages completed successfully"

# Final instructions
if [[ -f "$REPO_ROOT/launch.sh" && -x "$REPO_ROOT/launch.sh" ]]; then
  log ""
  log "To launch AXIOM cockpit:"
  log "  ./launch.sh"
fi

exit 0
