#!/usr/bin/env bash
set -euo pipefail

# Check whether a command exists in PATH.
axiom_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# True if stdout is a TTY.
axiom_is_tty_stdout() {
  [ -t 1 ]
}

# True if stdin is a TTY.
axiom_is_tty_stdin() {
  [ -t 0 ]
}

# Require a command to exist, otherwise log an error and return non-zero.
axiom_require_command() {
  local cmd="$1"
  if ! axiom_command_exists "$cmd"; then
    axiom_log_error "Missing required command: $cmd"
    return 1
  fi
}

# Idempotent directory creation helper.
axiom_safe_mkdir() {
  local path="$1"
  mkdir -p "$path"
}

# Current UTC time in ISO-8601 format.
axiom_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# mktemp compatibility wrapper (Termux-safe).
axiom_mktemp() {
  if axiom_command_exists mktemp; then
    mktemp
    return 0
  fi

  local tmp_dir tmp_file
  tmp_dir="${TMPDIR:-/tmp}"

  while :; do
    tmp_file="$tmp_dir/axiom_tmp_${RANDOM}_$$"
    if [ ! -e "$tmp_file" ]; then
      (umask 077 && : >"$tmp_file")
      printf '%s\n' "$tmp_file"
      return 0
    fi
  done
}
