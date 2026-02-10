#!/usr/bin/env bash
# AXIOM Stage 1 shell environment installer (post cockpit.sh)
# System: AXIOM
# Developer: Justadudeinspace (JADIS)
# Email: theoutervoid@outlook.com
# GitHub: https://github.com/Justadudeinspace
# Repo: https://github.com/Justadudeinspace/axiom

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
COCKPIT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"

# shellcheck source=../core/constants.sh
source "${COCKPIT_DIR}/core/constants.sh"
# shellcheck source=../core/shell.sh
source "${COCKPIT_DIR}/core/shell.sh"
# shellcheck source=../core/log.sh
source "${COCKPIT_DIR}/core/log.sh"
# shellcheck source=../core/platform.sh
source "${COCKPIT_DIR}/core/platform.sh"
# shellcheck source=../core/env.sh
source "${COCKPIT_DIR}/core/env.sh"
# shellcheck source=../core/runs.sh
source "${COCKPIT_DIR}/core/runs.sh"
# shellcheck source=../core/apt.sh
source "${COCKPIT_DIR}/core/apt.sh"

AXIOM_VERSION="1.0.0"
AXIOM_REPO="${AXIOM_REPO_URL}"
AXIOM_LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/axiom/logs"
AXIOM_LOG_FILE="${AXIOM_LOG_DIR}/axiom-shell-install-$(date +%Y%m%d-%H%M%S).log"
AXIOM_ZSHRC_MARKER_START="### >>> AXIOM SHELL CONFIG >>>"
AXIOM_ZSHRC_MARKER_END="### <<< AXIOM SHELL CONFIG <<<"

SILENT_MODE=0
DEBUG_MODE=0
NO_ZSHRC=0

RUN_DIR=""
RUN_STARTED_AT=""
RUN_COMMAND_LINE=""
RUN_CWD=""

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
  axiom_log_info "Log started: $(date -Iseconds)"
  axiom_log_info "Log file: ${AXIOM_LOG_FILE}"
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
        axiom_log_warn "Unknown argument: $1"
        shift
        ;;
    esac
  done
}

OS_FAMILY=""
ENVIRONMENT="native"
PLATFORM_LABEL=""
LAST_ZSHRC_BACKUP=""

detect_platform() {
  local platform
  platform="$(axiom_detect_platform)"
  PLATFORM_LABEL="${platform}"

  if axiom_is_termux; then
    if [[ -f "/etc/os-release" ]] && axiom_command_exists apt-get; then
      ENVIRONMENT="proot"
      OS_FAMILY="debian"
      return 0
    fi
    OS_FAMILY="termux"
    ENVIRONMENT="termux"
    return 0
  fi

  if [[ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
    PLATFORM_LABEL="wsl2"
  fi

  if [[ -f "/.dockerenv" ]] || grep -qi "container" /proc/1/cgroup 2>/dev/null; then
    ENVIRONMENT="container"
  fi

  if command -v getconf >/dev/null 2>&1; then
    if [[ "$(getconf LONG_BIT 2>/dev/null)" == "32" ]]; then
      axiom_log_warn "32-bit architecture detected; some dependencies may be unavailable."
    fi
  elif [[ "$(uname -m)" =~ i[0-9]86 ]]; then
    axiom_log_warn "32-bit architecture detected; some dependencies may be unavailable."
  fi

  if [[ "${platform}" == "wsl" ]]; then
    platform="linux"
  fi

  if [[ "${platform}" == "linux" ]]; then
    if [[ -f "/etc/os-release" ]]; then
      # shellcheck disable=SC1091
      source /etc/os-release
      if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* || "${ID_LIKE:-}" == *ubuntu* ]]; then
        OS_FAMILY="debian"
        return 0
      fi
    fi
  fi

  if [[ "${platform}" == "macos" ]]; then
    OS_FAMILY="macos"
    return 0
  fi

  OS_FAMILY="unsupported"
}

apt_get_update() {
  run_with_timeout 60 axiom_apt_update
}

apt_get_install() {
  run_with_timeout 300 axiom_apt_install "$@"
}

apt_is_package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_install_optional() {
  local pkg="$1"
  if apt_is_package_available "${pkg}"; then
    if apt_get_install "${pkg}"; then
      axiom_log_info "Installed optional package: ${pkg}"
    else
      axiom_log_warn "Optional package failed: ${pkg}"
    fi
  else
    axiom_log_warn "Optional package not available: ${pkg}"
  fi
}

apt_install_optional_fetch_tool() {
  if apt_is_package_available fastfetch; then
    apt_install_optional fastfetch
  else
    apt_install_optional neofetch
  fi
}

pkg_install_optional() {
  local pkg="$1"
  if pkg install -y "${pkg}"; then
    axiom_log_info "Installed optional package: ${pkg}"
  else
    axiom_log_warn "Optional package failed: ${pkg}"
  fi
}

run_with_timeout() {
  local timeout_s="$1"
  shift
  if axiom_command_exists timeout; then
    timeout "${timeout_s}" "$@"
  else
    "$@"
  fi
}

retry_command() {
  local attempts="$1"
  shift
  local attempt=1
  while [[ "${attempt}" -le "${attempts}" ]]; do
    if "$@"; then
      return 0
    fi
    axiom_log_warn "Command failed (attempt ${attempt}/${attempts}): $*"
    attempt=$((attempt + 1))
  done
  return 1
}

install_dependencies() {
  axiom_log_info "Installing dependencies for ${OS_FAMILY} (${ENVIRONMENT}) [${PLATFORM_LABEL}]"

  case "${OS_FAMILY}" in
    debian)
      if ! retry_command 3 apt_get_update; then
        axiom_log_warn "apt-get update failed after retries; continuing."
      fi
      if ! retry_command 3 apt_get_install zsh git curl wget unzip ca-certificates locales fontconfig fzf ripgrep jq; then
        axiom_log_warn "apt-get install failed after retries; continuing."
      fi
      apt_install_optional bat
      apt_install_optional eza
      apt_install_optional fd-find
      apt_install_optional_fetch_tool
      ;;
    termux)
      if ! retry_command 3 run_with_timeout 60 pkg update; then
        axiom_log_warn "pkg update failed after retries; continuing."
      fi
      if ! retry_command 3 run_with_timeout 300 pkg install -y zsh git curl wget unzip ca-certificates fontconfig fzf ripgrep jq python3; then
        axiom_log_warn "pkg install failed after retries; continuing."
      fi
      pkg_install_optional bat
      pkg_install_optional eza
      pkg_install_optional fd
      pkg_install_optional neofetch
      ;;
    macos)
      if axiom_command_exists brew; then
        brew update
        brew install zsh git curl wget unzip ca-certificates fontconfig fzf ripgrep jq
        brew install bat eza fd neofetch || true
      else
        axiom_log_warn "Homebrew not found. Install dependencies manually: https://brew.sh"
      fi
      ;;
    *)
      axiom_log_error "Unsupported platform. Supported: Debian/Ubuntu, Termux, macOS."
      safe_exit 1
      ;;
  esac
}

install_oh_my_zsh() {
  axiom_log_info "Installing oh-my-zsh"
  local omz_dir="$HOME/.oh-my-zsh"

  if [[ -d "${omz_dir}/.git" ]]; then
    axiom_log_info "Updating oh-my-zsh"
    if ! git -C "${omz_dir}" pull --ff-only; then
      axiom_log_warn "oh-my-zsh update failed"
    fi
    return 0
  fi

  if [[ -d "${omz_dir}" ]]; then
    axiom_log_warn "oh-my-zsh directory exists without git metadata; skipping clone"
    return 0
  fi

  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "${omz_dir}"
}

install_powerlevel10k() {
  axiom_log_info "Installing powerlevel10k"
  local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

  if [[ -d "${theme_dir}/.git" ]]; then
    axiom_log_info "Updating powerlevel10k"
    if ! git -C "${theme_dir}" pull --ff-only; then
      axiom_log_warn "powerlevel10k update failed"
    fi
    return 0
  fi

  if [[ -d "${theme_dir}" ]]; then
    axiom_log_warn "powerlevel10k directory exists without git metadata; skipping clone"
    return 0
  fi

  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${theme_dir}"
}

install_zplug() {
  axiom_log_info "Installing zplug"
  local zplug_home="${ZPLUG_HOME:-$HOME/.zplug}"

  if [[ -d "${zplug_home}/.git" ]]; then
    axiom_log_info "Updating zplug"
    if ! git -C "${zplug_home}" pull --ff-only; then
      axiom_log_warn "zplug update failed"
    fi
    return 0
  fi

  if [[ -d "${zplug_home}" ]]; then
    axiom_log_warn "zplug directory exists without git metadata; skipping clone"
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

  if ! zplug check; then
    zplug install
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
    axiom_log_info "Backed up .zshrc to ${backup}"
    LAST_ZSHRC_BACKUP="${backup}"
  fi
}

ensure_zshrc_block() {
  local zshrc_file="$HOME/.zshrc"
  local block
  block="$(render_zshrc_block)"

  if [[ -f "${zshrc_file}" ]]; then
    if [[ -z "${LAST_ZSHRC_BACKUP}" || ! -r "${LAST_ZSHRC_BACKUP}" ]]; then
      axiom_log_warn "Backup verification failed; skipping .zshrc modification."
      return 1
    fi
    if [[ ! -w "${zshrc_file}" ]]; then
      axiom_log_warn ".zshrc is not writable; skipping modification."
      return 1
    fi
    if [[ "$(wc -c < "${zshrc_file}" 2>/dev/null || echo 0)" -gt $((10 * 1024 * 1024)) ]]; then
      axiom_log_warn ".zshrc exceeds 10MB; skipping modification."
      return 0
    fi
  else
    if [[ ! -w "${HOME}" ]]; then
      axiom_log_warn "Home directory is not writable; skipping .zshrc creation."
      return 1
    fi
  fi

  if [[ ! -f "${zshrc_file}" ]]; then
    printf '%s\n' "${block}" > "${zshrc_file}"
    return 0
  fi

  if grep -qF "${AXIOM_ZSHRC_MARKER_START}" "${zshrc_file}"; then
    local tmp
    tmp="$(axiom_mktemp)"
    awk -v start="${AXIOM_ZSHRC_MARKER_START}" -v end="${AXIOM_ZSHRC_MARKER_END}" -v block="${block}" '
      $0 == start {print block; in_block=1; next}
      $0 == end {in_block=0; next}
      !in_block {print}
    ' "${zshrc_file}" > "${tmp}"
    if ! mv "${tmp}" "${zshrc_file}"; then
      axiom_log_warn "Failed to update .zshrc; attempting rollback."
      if [[ -n "${LAST_ZSHRC_BACKUP}" && -r "${LAST_ZSHRC_BACKUP}" ]]; then
        cp "${LAST_ZSHRC_BACKUP}" "${zshrc_file}" && axiom_log_warn "Rollback complete."
      fi
      return 1
    fi
  else
    if ! printf '\n%s\n' "${block}" >> "${zshrc_file}"; then
      axiom_log_warn "Failed to append to .zshrc; attempting rollback."
      if [[ -n "${LAST_ZSHRC_BACKUP}" && -r "${LAST_ZSHRC_BACKUP}" ]]; then
        cp "${LAST_ZSHRC_BACKUP}" "${zshrc_file}" && axiom_log_warn "Rollback complete."
      fi
      return 1
    fi
  fi
}

run_zplug_install() {
  if [[ "${NO_ZSHRC}" -eq 1 ]]; then
    axiom_log_warn "Skipping zplug install because --no-zshrc was set"
    return 0
  fi

  if axiom_command_exists zsh; then
    axiom_log_info "Installing zplug plugins"
    ZPLUG_HOME="${ZPLUG_HOME:-$HOME/.zplug}" zsh -lc 'source ~/.zshrc; if ! zplug check; then zplug install; fi'
  else
    axiom_log_warn "zsh not available to run zplug install"
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

record_run_metadata() {
  local exit_code="$1"
  local ended_at
  ended_at="$(axiom_now_utc)"
  axiom_runs_write_metadata "${RUN_DIR}" "setup" "blux10k" "${RUN_COMMAND_LINE}" "${exit_code}" "${RUN_STARTED_AT}" "${ended_at}" "${RUN_CWD}"
}

main() {
  parse_args "$@"
  log_init
  print_banner

  RUN_DIR="$(axiom_runs_create_dir "setup" "blux10k")"
  RUN_STARTED_AT="$(axiom_now_utc)"
  RUN_CWD="$(pwd -P)"
  printf -v RUN_COMMAND_LINE '%q ' "$0" "$@"
  RUN_COMMAND_LINE="${RUN_COMMAND_LINE% }"
  trap 'record_run_metadata "$?"' EXIT

  detect_platform
  if [[ "${OS_FAMILY}" == "unsupported" ]]; then
    axiom_log_error "Unsupported platform detected."
    safe_exit 1
  fi

  axiom_runs_write_output "${RUN_DIR}" "install zsh"
  install_dependencies
  axiom_runs_write_output "${RUN_DIR}" "install oh-my-zsh"
  install_oh_my_zsh
  axiom_runs_write_output "${RUN_DIR}" "install powerlevel10k"
  install_powerlevel10k
  axiom_runs_write_output "${RUN_DIR}" "install zplug"
  install_zplug

  if [[ "${NO_ZSHRC}" -eq 0 ]]; then
    backup_zshrc
    ensure_zshrc_block
    axiom_runs_write_output "${RUN_DIR}" "update .zshrc"
  else
    axiom_log_warn "Skipping .zshrc modification (--no-zshrc)"
  fi

  run_zplug_install

  axiom_log_info "AXIOM shell environment ready."
  axiom_log_info "Restart your terminal or run: exec zsh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
