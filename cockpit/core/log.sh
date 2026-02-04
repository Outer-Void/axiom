#!/usr/bin/env bash

# Logging helpers.

axiom_log_info() {
  printf '%s\n' "[axiom][info] $*"
}

axiom_log_warn() {
  printf '%s\n' "[axiom][warn] $*" >&2
}

axiom_log_error() {
  printf '%s\n' "[axiom][error] $*" >&2
}

# Print an error and return non-zero (do not exit).
axiom_die() {
  axiom_log_error "$*"
  return 1
}
