#!/usr/bin/env bash
# AXIOM Stage 1 shell environment installer (post cockpit.sh)
# System: AXIOM
# Developer: Justadudeinspace (JADIS)
# Email: theoutervoid@outlook.com
# GitHub: https://github.com/Justadudeinspace
# Repo: https://github.com/Justadudeinspace/axiom

set -euo pipefail
IFS=$'\n\t'

AXIOM_VERSION="1.0.0"
AXIOM_REPO="https://github.com/Justadudeinspace/axiom"
AXIOM_LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/axiom/logs"
AXIOM_LOG_FILE="${AXIOM_LOG_DIR}/axiom-shell-install-$(date +%Y%m%d-%H%M%S).log"
AXIOM_ZSHRC_MARKER_START="### >>> AXIOM SHELL CONFIG >>>"
AXIOM_ZSHRC_MARKER_END="### <<< AXIOM SHELL CONFIG <<<"

SILENT_MODE=0
DEBUG_MODE=0
NO_ZSHRC=0

is_sourced() {
  [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

safe_exit() {
  local status="${1:-0}"
  if is_sourced; then
    return "${status}"
  fi
  exit "${status}"
}

usage() {
  cat <<EOF
AXIOM Stage 1 Shell Environment Installer
Usage: $(basename "$0") [options]

Options:
  --silent        Non-interactive defaults
  --debug         Verbose logging
  --no-zshrc      Skip .zshrc modification
  -h, --help      Show this help

This installer configures zsh, oh-my-zsh, powerlevel10k, and zplug.
Repository: ${AXIOM_REPO}
EOF
}

log_init() {
  mkdir -p "${AXIOM_LOG_DIR}"
  if [[ "${DEBUG_MODE}" -eq 1 ]]; then
    exec 1> >(tee -a "${AXIOM_LOG_FILE}") 2>&1
  else
    exec 1> >(tee -a "${AXIOM_LOG_FILE}") 2>&1
  fi
  echo "[AXIOM] Log started: $(date -Iseconds)"
  echo "[AXIOM] Log file: ${AXIOM_LOG_FILE}"
}

log_info() {
  echo "[AXIOM][INFO] $*"
}

log_warn() {
  echo "[AXIOM][WARN] $*"
}

log_error() {
  echo "[AXIOM][ERROR] $*" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --silent)
        SILENT_MODE=1
        shift
        ;;
      --debug)
        DEBUG_MODE=1
        shift
        ;;
      --no-zshrc)
        NO_ZSHRC=1
        shift
        ;;
      -h|--help)
        usage
        safe_exit 0
        ;;
      *)
        log_warn "Unknown argument: $1"
        shift
        ;;
    esac
  done
}

OS_FAMILY=""
ENVIRONMENT="native"

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] || [[ -n "${PREFIX:-}" && "${PREFIX}" == /data/data/com.termux/files/usr* ]] || [[ -d "/data/data/com.termux/files/usr" ]]
}

detect_platform() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    OS_FAMILY="macos"
    return 0
  fi

  if is_termux; then
    if [[ -f "/etc/os-release" ]] && command -v apt-get >/dev/null 2>&1; then
      ENVIRONMENT="proot"
      OS_FAMILY="debian"
      return 0
    fi
    OS_FAMILY="termux"
    ENVIRONMENT="termux"
    return 0
  fi

  if [[ -f "/etc/os-release" ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* || "${ID_LIKE:-}" == *ubuntu* ]]; then
      OS_FAMILY="debian"
      return 0
    fi
  fi

  OS_FAMILY="unsupported"
}

get_sudo_prefix() {
  if command -v sudo >/dev/null 2>&1 && [[ "${EUID}" -ne 0 ]]; then
    echo "sudo"
  fi
}

apt_get_update() {
  local sudo_prefix
  sudo_prefix=$(get_sudo_prefix)
  if [[ -n "${sudo_prefix}" ]]; then
    ${sudo_prefix} apt-get update
  else
    apt-get update
  fi
}

apt_get_install() {
  local sudo_prefix
  sudo_prefix=$(get_sudo_prefix)
  if [[ -n "${sudo_prefix}" ]]; then
    ${sudo_prefix} apt-get install -y "$@"
  else
    apt-get install -y "$@"
  fi
}

apt_is_package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_install_optional() {
  local pkg="$1"
  if apt_is_package_available "${pkg}"; then
    if apt_get_install "${pkg}"; then
      log_info "Installed optional package: ${pkg}"
    else
      log_warn "Optional package failed: ${pkg}"
    fi
  else
    log_warn "Optional package not available: ${pkg}"
  fi
}

pkg_install_optional() {
  local pkg="$1"
  if pkg install -y "${pkg}"; then
    log_info "Installed optional package: ${pkg}"
  else
    log_warn "Optional package failed: ${pkg}"
  fi
}

install_dependencies() {
  log_info "Installing dependencies for ${OS_FAMILY} (${ENVIRONMENT})"

  case "${OS_FAMILY}" in
    debian)
      apt_get_update
      apt_get_install zsh git curl wget unzip ca-certificates locales fontconfig fzf ripgrep jq
      apt_install_optional bat
      apt_install_optional eza
      apt_install_optional fd-find
      apt_install_optional neofetch
      ;;
    termux)
      pkg update
      pkg install -y zsh git curl wget unzip ca-certificates fontconfig fzf ripgrep jq python3
      pkg_install_optional bat
      pkg_install_optional eza
      pkg_install_optional fd
      pkg_install_optional neofetch
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew update
        brew install zsh git curl wget unzip ca-certificates fontconfig fzf ripgrep jq
        brew install bat eza fd neofetch || true
      else
        log_warn "Homebrew not found. Install dependencies manually: https://brew.sh"
      fi
      ;;
    *)
      log_error "Unsupported platform. Supported: Debian/Ubuntu, Termux, macOS."
      safe_exit 1
      ;;
  esac
}

install_oh_my_zsh() {
  log_info "Installing oh-my-zsh"
  local omz_dir="$HOME/.oh-my-zsh"

  if [[ -d "${omz_dir}/.git" ]]; then
    log_info "Updating oh-my-zsh"
    if ! git -C "${omz_dir}" pull --ff-only; then
      log_warn "oh-my-zsh update failed"
    fi
    return 0
  fi

  if [[ -d "${omz_dir}" ]]; then
    log_warn "oh-my-zsh directory exists without git metadata; skipping clone"
    return 0
  fi

  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "${omz_dir}"
}

install_powerlevel10k() {
  log_info "Installing powerlevel10k"
  local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

  if [[ -d "${theme_dir}/.git" ]]; then
    log_info "Updating powerlevel10k"
    if ! git -C "${theme_dir}" pull --ff-only; then
      log_warn "powerlevel10k update failed"
    fi
    return 0
  fi

  if [[ -d "${theme_dir}" ]]; then
    log_warn "powerlevel10k directory exists without git metadata; skipping clone"
    return 0
  fi

  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${theme_dir}"
}

install_zplug() {
  log_info "Installing zplug"
  local zplug_home="${ZPLUG_HOME:-$HOME/.zplug}"

  if [[ -d "${zplug_home}/.git" ]]; then
    log_info "Updating zplug"
    if ! git -C "${zplug_home}" pull --ff-only; then
      log_warn "zplug update failed"
    fi
    return 0
  fi

  if [[ -d "${zplug_home}" ]]; then
    log_warn "zplug directory exists without git metadata; skipping clone"
    return 0
  fi

  git clone --depth=1 https://github.com/zplug/zplug "${zplug_home}"
}

render_zshrc_block() {
  cat <<'EOF'
### >>> AXIOM SHELL CONFIG >>>
# AXIOM shell configuration block
# System: AXIOM
# Developer: Justadudeinspace (JADIS)
# Email: theoutervoid@outlook.com
# GitHub: https://github.com/Justadudeinspace
# Repo: https://github.com/Justadudeinspace/axiom

# Powerlevel10k instant prompt (keep near top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# zplug initialization and plugins
export ZPLUG_HOME="${ZPLUG_HOME:-$HOME/.zplug}"
if [[ -f "$ZPLUG_HOME/init.zsh" ]]; then
  source "$ZPLUG_HOME/init.zsh"

  zplug "zsh-users/zsh-autosuggestions"
  zplug "zsh-users/zsh-syntax-highlighting"
  zplug "zsh-users/zsh-completions"
  zplug "Aloxaf/fzf-tab"

  if ! zplug check --verbose; then
    zplug install --verbose
  fi
  zplug load
fi

autoload -Uz compinit
compinit

if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
### <<< AXIOM SHELL CONFIG <<<
EOF
}

backup_zshrc() {
  local zshrc_file="$HOME/.zshrc"
  if [[ -f "${zshrc_file}" ]]; then
    local backup="${zshrc_file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "${zshrc_file}" "${backup}"
    log_info "Backed up .zshrc to ${backup}"
  fi
}

ensure_zshrc_block() {
  local zshrc_file="$HOME/.zshrc"
  local block
  block="$(render_zshrc_block)"

  if [[ ! -f "${zshrc_file}" ]]; then
    printf '%s\n' "${block}" > "${zshrc_file}"
    return 0
  fi

  if grep -qF "${AXIOM_ZSHRC_MARKER_START}" "${zshrc_file}"; then
    local tmp
    tmp="$(mktemp)"
    awk -v start="${AXIOM_ZSHRC_MARKER_START}" -v end="${AXIOM_ZSHRC_MARKER_END}" -v block="${block}" '
      $0 == start {print block; in_block=1; next}
      $0 == end {in_block=0; next}
      !in_block {print}
    ' "${zshrc_file}" > "${tmp}"
    mv "${tmp}" "${zshrc_file}"
  else
    printf '\n%s\n' "${block}" >> "${zshrc_file}"
  fi
}

run_zplug_install() {
  if [[ "${NO_ZSHRC}" -eq 1 ]]; then
    log_warn "Skipping zplug install because --no-zshrc was set"
    return 0
  fi

  if command -v zsh >/dev/null 2>&1; then
    log_info "Installing zplug plugins"
    ZPLUG_HOME="${ZPLUG_HOME:-$HOME/.zplug}" zsh -lc 'source ~/.zshrc; zplug install --verbose'
  else
    log_warn "zsh not available to run zplug install"
  fi
}

print_banner() {
  cat <<EOF
AXIOM Stage 1 Shell Environment Installer
System: AXIOM
Developer: Justadudeinspace (JADIS)
Contact: theoutervoid@outlook.com
Repo: ${AXIOM_REPO}
EOF
}

main() {
  parse_args "$@"
  log_init
  print_banner

  detect_platform
  if [[ "${OS_FAMILY}" == "unsupported" ]]; then
    log_error "Unsupported platform detected."
    safe_exit 1
  fi

  install_dependencies
  install_oh_my_zsh
  install_powerlevel10k
  install_zplug

  if [[ "${NO_ZSHRC}" -eq 0 ]]; then
    backup_zshrc
    ensure_zshrc_block
  else
    log_warn "Skipping .zshrc modification (--no-zshrc)"
  fi

  run_zplug_install

  log_info "AXIOM shell environment ready."
  log_info "Restart your terminal or run: exec zsh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
