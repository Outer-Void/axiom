#!/usr/bin/env bash
# AXIOM Stage 2: blux10k prerequisite/version gate.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
COCKPIT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"

# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/constants.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/shell.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/log.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/platform.sh"
# shellcheck disable=SC1091
. "${COCKPIT_DIR}/core/runs.sh"

BLUX10K_MIN_VERSION="${BLUX10K_MIN_VERSION:-2.0.0}"
BLUX10K_REPO_URL="${BLUX10K_REPO_URL:-https://github.com/Outer-Void/blux10k.git}"
BLUX10K_INSTALL_DIR="${BLUX10K_INSTALL_DIR:-$HOME/.blux10k}"

RUN_DIR=""
RUN_STARTED_AT=""

log_info() {
  axiom_log_info "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[info] $*"
  fi
}

log_warn() {
  axiom_log_warn "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[warn] $*"
  fi
}

log_error() {
  axiom_log_error "$*"
  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_output "$RUN_DIR" "[error] $*"
  fi
}

print_manual_fallback_block() {
  local installer_hint="$1"
  cat <<EOF
============================================================
AXIOM did not freeze.
AXIOM intentionally stopped stage 2 for safety (fail-closed).

Reason:
- blux10k installer interactivity could not be guaranteed safely.
- Hidden prompt automation is intentionally refused.

Run this manual command with visible prompts:
  cd "$BLUX10K_INSTALL_DIR"
  $installer_hint

After completion, re-run:
  ./axiom.sh
============================================================
EOF
}

version_ge() {
  local left="$1"
  local right="$2"
  if [ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | head -n1)" = "$right" ]; then
    return 0
  fi
  return 1
}

read_blux_version() {
  local version_file="$BLUX10K_INSTALL_DIR/VERSION"
  if [ -f "$version_file" ]; then
    tr -d '[:space:]' <"$version_file"
    return 0
  fi
  return 1
}

has_blux_ready_signal() {
  if [ "${BLUX10K_READY:-0}" = "1" ]; then
    return 0
  fi

  local file
  for file in "$HOME/.zshrc" "$HOME/.zshrc.local" "$HOME/.zprofile"; do
    if [ -f "$file" ] && grep -Eq '(^|[[:space:]])BLUX10K_READY=1([[:space:]]|$)' "$file"; then
      return 0
    fi
  done

  return 1
}

run_blux_version_check() {
  local check_script="$BLUX10K_INSTALL_DIR/scripts/check_version.sh"

  [ -f "$check_script" ] || return 1

  if bash "$check_script" "$BLUX10K_MIN_VERSION" >/dev/null 2>&1; then
    return 0
  fi

  local installed
  installed="$(read_blux_version 2>/dev/null || true)"
  if [ -n "$installed" ] && version_ge "$installed" "$BLUX10K_MIN_VERSION"; then
    return 0
  fi

  return 1
}

blux_foundation_ready() {
  [ -f "$BLUX10K_INSTALL_DIR/VERSION" ] || return 1
  [ -f "$BLUX10K_INSTALL_DIR/scripts/check_version.sh" ] || return 1
  has_blux_ready_signal || return 1
  run_blux_version_check || return 1
  return 0
}

script_supports_noninteractive_flag() {
  local installer="$1"
  [ -f "$installer" ] || return 1
  grep -Eq -- '(^|[^A-Za-z0-9_])--noninteractive([^A-Za-z0-9_]|$)' "$installer"
}

run_known_noninteractive_installer() {
  local installer="$1"
  local label="$2"

  if ! script_supports_noninteractive_flag "$installer"; then
    log_error "$label does not advertise --noninteractive support."
    print_manual_fallback_block "bash \"$installer\""
    return 1
  fi

  log_info "Running $label in explicit noninteractive mode"
  log_info "If this fails, run manually: bash $installer --noninteractive"
  if ! AXIOM_NONINTERACTIVE=1 bash "$installer" --noninteractive; then
    log_error "$label failed with --noninteractive."
    print_manual_fallback_block "bash \"$installer\" --noninteractive"
    return 1
  fi

  return 0
}

run_blux_installer() {
  local installer

  if [ -x "$BLUX10K_INSTALL_DIR/install.sh" ]; then
    installer="$BLUX10K_INSTALL_DIR/install.sh"
    run_known_noninteractive_installer "$installer" "blux10k install.sh"
    return $?
  fi

  if [ -x "$BLUX10K_INSTALL_DIR/cp_dotfiles.sh" ]; then
    installer="$BLUX10K_INSTALL_DIR/cp_dotfiles.sh"
    run_known_noninteractive_installer "$installer" "blux10k cp_dotfiles.sh"
    return $?
  fi

  log_error "No supported blux10k installer entrypoint found under $BLUX10K_INSTALL_DIR"
  print_manual_fallback_block "ls -la \"$BLUX10K_INSTALL_DIR\""
  return 1
}

install_or_update_blux10k() {
  if [ ! -d "$BLUX10K_INSTALL_DIR/.git" ]; then
    rm -rf "$BLUX10K_INSTALL_DIR"
    log_info "Cloning blux10k into $BLUX10K_INSTALL_DIR"
    git clone "$BLUX10K_REPO_URL" "$BLUX10K_INSTALL_DIR"
  else
    log_info "Updating existing blux10k checkout"
    git -C "$BLUX10K_INSTALL_DIR" fetch --all --tags --prune
    git -C "$BLUX10K_INSTALL_DIR" pull --ff-only
  fi

  if ! run_blux_installer; then
    log_error "Unable to run blux10k installer safely in noninteractive mode."
    print_manual_fallback_block "bash install.sh"
    return 1
  fi

  run_blux_version_check
}

main() {
  RUN_STARTED_AT="$(date -Iseconds)"
  RUN_DIR="$(axiom_runs_create_dir "install" "blux10k")"

  log_info "Checking blux10k foundation (min version: ${BLUX10K_MIN_VERSION})"

  if blux_foundation_ready; then
    local current_version
    current_version="$(read_blux_version || echo unknown)"
    log_info "blux10k v2.0 foundation is confirmed (installed: ${current_version})"
  else
    log_warn "blux10k foundation missing or stale; installing/updating"
    install_or_update_blux10k

    if ! blux_foundation_ready; then
      log_error "blux10k prerequisite gate failed after install/update"
      axiom_runs_write_metadata "$RUN_DIR" "install" "blux10k" "$0" "1" "$RUN_STARTED_AT" "$(date -Iseconds)" "$(pwd -P)"
      exit 1
    fi

    local verified_version
    verified_version="$(read_blux_version || echo unknown)"
    log_info "blux10k v2.0 foundation is confirmed (installed: ${verified_version})"
  fi

  axiom_runs_write_metadata "$RUN_DIR" "install" "blux10k" "$0" "0" "$RUN_STARTED_AT" "$(date -Iseconds)" "$(pwd -P)"
}

main "$@"
