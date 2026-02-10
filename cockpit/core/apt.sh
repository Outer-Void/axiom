#!/usr/bin/env bash

# Hardened apt-get wrapper for proot/container stability.

axiom_is_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ]
}

axiom_apt_prefix() {
  if axiom_is_root; then
    echo "apt-get"
  else
    echo "sudo env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get"
  fi
}

axiom_apt_common_opts() {
  # Critical for proot / container stability.
  echo "-y -o Dpkg::Use-Pty=0 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o APT::Color=0"
}

axiom_apt_log() {
  if declare -F axiom_log_info >/dev/null 2>&1; then
    axiom_log_info "$*"
  else
    printf '%s\n' "[axiom][info] $*"
  fi
}

axiom_apt_update() {
  local prefix
  local opts
  prefix="$(axiom_apt_prefix)"
  opts="$(axiom_apt_common_opts)"
  # shellcheck disable=SC2086
  $prefix $opts update
}

axiom_apt_install() {
  local prefix
  local opts
  prefix="$(axiom_apt_prefix)"
  opts="$(axiom_apt_common_opts)"
  axiom_apt_log "Note: dpkg triggers (libc-bin/ldconfig) can take a while on proot."
  # shellcheck disable=SC2086
  if ! $prefix $opts install --no-install-recommends "$@"; then
    if declare -F axiom_log_error >/dev/null 2>&1; then
      axiom_log_error "Recovery: sudo dpkg --configure -a && sudo apt-get -f install -y"
    else
      printf '%s\n' "[axiom][error] Recovery: sudo dpkg --configure -a && sudo apt-get -f install -y" >&2
    fi
    return 1
  fi
}
