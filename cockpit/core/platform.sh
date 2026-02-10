#!/usr/bin/env bash

# Platform detection helpers.

axiom_has_debian_markers() {
  [ -x "/usr/bin/apt" ] && [ -f "/etc/debian_version" ]
}

axiom_has_termux_prefix() {
  if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
    case "$PREFIX" in
      /data/data/com.termux/*) return 0 ;;
    esac
  fi
  return 1
}

axiom_has_termux_proot_context() {
  if [ -n "${PROOT_DISTRIBUTION:-}" ]; then
    return 0
  fi
  if axiom_is_proot; then
    return 0
  fi
  if [ -d "/data/data/com.termux" ]; then
    return 0
  fi
  if [ -e "/etc/resolv.conf" ]; then
    local resolv_path
    resolv_path="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    case "$resolv_path" in
      *proot*|*termux*|*/data/data/com.termux/*) return 0 ;;
    esac
  fi
  return 1
}

axiom_is_termux_native() {
  if [ -n "${TERMUX_VERSION:-}" ]; then
    return 0
  fi
  if [ -x "/data/data/com.termux/files/usr/bin/pkg" ]; then
    return 0
  fi
  if axiom_has_termux_prefix && ! axiom_has_debian_markers; then
    return 0
  fi
  return 1
}

axiom_is_termux() {
  axiom_is_termux_native && return 0
  axiom_has_termux_proot_context && return 0
  return 1
}

axiom_is_wsl() {
  # Method 1: Check kernel release
  local uname_r
  uname_r="$(uname -r 2>/dev/null || true)"
  if printf '%s' "$uname_r" | grep -qi "microsoft\|wsl"; then
    return 0
  fi
  
  # Method 2: Check /proc/version
  if [ -f /proc/version ] && grep -qi "microsoft\|wsl" /proc/version; then
    return 0
  fi
  
  # Method 3: Check for WSL specific environment variables (newer WSL2)
  if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ]; then
    return 0
  fi
  
  # Method 4: Check for Windows executables in PATH
  if command -v wsl.exe >/dev/null 2>&1 || 
     command -v wslpath >/dev/null 2>&1 ||
     command -v cmd.exe >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}

axiom_is_macos() {
  [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]
}

axiom_is_windows() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || true)"
  case "$uname_s" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
  esac
  [ "${OS:-}" = "Windows_NT" ]
}

axiom_is_linux() {
  [ "$(uname -s 2>/dev/null || true)" = "Linux" ]
}

axiom_is_proot() {
  if [ -n "${PROOT:-}" ]; then
    return 0
  fi
  if [ -f /proc/1/cmdline ] && grep -aq "proot" /proc/1/cmdline; then
    return 0
  fi
  if [ -f /proc/self/cmdline ] && grep -aq "proot" /proc/self/cmdline; then
    return 0
  fi
  return 1
}

axiom_is_proot_debian() {
  if ! axiom_has_debian_markers; then
    return 1
  fi
  if axiom_has_termux_proot_context; then
    return 0
  fi
  return 1
}

axiom_is_debian() {
  if ! axiom_has_debian_markers; then
    return 1
  fi
  if axiom_has_termux_proot_context; then
    return 1
  fi
  return 0
}

axiom_detect_platform() {
  if axiom_is_wsl; then
    printf '%s\n' "wsl"
    return 0
  fi
  if axiom_is_proot_debian; then
    printf '%s\n' "proot-debian"
    return 0
  fi
  if axiom_is_termux_native; then
    printf '%s\n' "termux"
    return 0
  fi
  if axiom_is_debian; then
    printf '%s\n' "debian"
    return 0
  fi
  if axiom_is_proot; then
    printf '%s\n' "proot"
    return 0
  fi
  if axiom_is_linux; then
    printf '%s\n' "linux"
    return 0
  fi
  if axiom_is_macos; then
    printf '%s\n' "macos"
    return 0
  fi
  if axiom_is_windows; then
    printf '%s\n' "windows"
    return 0
  fi
  printf '%s\n' "unknown"
}

axiom_platform_summary() {
  local platform arch
  platform="$(axiom_detect_platform)"
  arch="$(uname -m 2>/dev/null || true)"

  if [ -n "$arch" ]; then
    printf '%s %s\n' "$platform" "$arch"
  else
    printf '%s\n' "$platform"
  fi
}
