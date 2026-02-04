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
# FIXED: Race condition and insecure temp file creation
axiom_mktemp() {
  if axiom_command_exists mktemp; then
    # Use system mktemp if available
    mktemp 2>/dev/null || mktemp -t axiom 2>/dev/null || {
      axiom_log_warn "mktemp failed, using fallback"
      echo "/tmp/axiom_temp_$$"
    }
    return 0
  fi

  local tmp_dir tmp_file
  tmp_dir="${TMPDIR:-/tmp}"
  
  # Safer fallback with better randomness
  for _ in 1 2 3 4 5; do
    tmp_file="${tmp_dir}/axiom_temp_$$_${RANDOM}_${RANDOM}"
    
    # Try to create file atomically with proper permissions
    if (umask 077 && set -o noclobber && : > "$tmp_file") 2>/dev/null; then
      printf '%s\n' "$tmp_file"
      return 0
    fi
  done
  
  # Last resort fallback
  axiom_log_warn "Could not create secure temp file, using unsafe fallback"
  echo "/tmp/axiom_unsafe_$$"
}
