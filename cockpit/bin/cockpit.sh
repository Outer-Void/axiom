#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
COCKPIT_DIR="$(cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"

# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/constants.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/shell.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/log.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/platform.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/env.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/runs.sh"
# shellcheck disable=SC1091
. "$COCKPIT_DIR/core/apt.sh"

RUN_DIR=""
STARTED_AT=""
RUN_COMMAND=""
COCKPIT_PLATFORM=""

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

ensure_root_or_sudo() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    return 0
  fi
  log_info "Root privileges are required for this step; checking sudo availability."
  if axiom_command_exists sudo; then
    return 0
  fi
  axiom_die "Root privileges are required for package installation. Please run as root or install sudo." || return 1
}

apt_update_once() {
  local marker="/tmp/cockpit-apt-updated"
  if [ ! -f "$marker" ]; then
    log_info "Starting apt update (this can take time and may block on sudo/network)."
    if ! axiom_apt_update; then
      if [ "$COCKPIT_PLATFORM" = "proot-debian" ]; then
        log_error "sudo apt update failed. Ensure sudo is installed and configured for passwordless use."
      fi
      return 1
    fi
    touch "$marker"
  fi
}

apt_install() {
  local packages=()
  local pkg

  for pkg in "$@"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log_info "Already installed: $pkg"
    else
      packages+=("$pkg")
    fi
  done

  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi

  if [ "$COCKPIT_PLATFORM" != "proot-debian" ]; then
    ensure_root_or_sudo || return 1
  fi
  log_info "Preparing apt install transaction for: ${packages[*]}"
  log_info "Refreshing apt package lists before apt install"
  apt_update_once || return 1

  log_info "Starting apt install for: ${packages[*]}"
  log_info "Waiting on apt install completion..."
  if ! axiom_apt_install "${packages[@]}"; then
    if [ "$COCKPIT_PLATFORM" = "proot-debian" ]; then
      log_error "sudo apt install failed. Ensure sudo is installed and configured for passwordless use."
    fi
    return 1
  fi
}

pkg_install() {
  local packages=()
  local pkg

  for pkg in "$@"; do
    if axiom_command_exists dpkg && dpkg -s "$pkg" >/dev/null 2>&1; then
      log_info "Already installed: $pkg"
    elif ! axiom_command_exists dpkg && pkg list-installed 2>/dev/null | awk -F/ '{print $1}' | grep -qx "$pkg"; then
      log_info "Already installed: $pkg"
    else
      packages+=("$pkg")
    fi
  done

  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi

  axiom_require_command pkg || return 1
  log_info "Installing packages via pkg: ${packages[*]}"
  log_info "Waiting on Termux pkg install completion..."
  if ! pkg install -y "${packages[@]}"; then
    log_error "pkg install failed for: ${packages[*]}"
    return 1
  fi
}

run_as_user() {
  local user="$1"
  shift
  if [ -z "${user:-}" ]; then
    log_error "run_as_user requires a non-empty user"
    return 1
  fi
  if [ "$#" -le 0 ]; then
    log_error "run_as_user requires a command to execute"
    return 1
  fi
  local arg
  for arg in "$@"; do
    case "$arg" in
      *'`'*|*'$('*)
        log_error "run_as_user rejected unsafe argument: $arg"
        return 1
        ;;
    esac
  done
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    if axiom_command_exists sudo; then
      sudo -u "$user" "$@"
    else
      local cmd=("$@")
      su - "$user" -c "$(printf '%s ' "${cmd[@]}")" --
    fi
  else
    "$@"
  fi
}

check_disk_space() {
  local target="${1:-/}"
  local min_kb=$((1024 * 1024))
  local avail_kb
  avail_kb="$(df -Pk "$target" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [ -z "$avail_kb" ] || ! [ "$avail_kb" -ge "$min_kb" ] 2>/dev/null; then
    log_error "Insufficient disk space on ${target}. Require at least 1GB free."
    return 1
  fi
  return 0
}

check_memory_warn() {
  local min_mb=2048
  local mem_kb=""
  if [ -r /proc/meminfo ]; then
    mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  elif axiom_command_exists sysctl; then
    local mem_bytes
    mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
    if [ -n "$mem_bytes" ]; then
      mem_kb=$((mem_bytes / 1024))
    fi
  fi
  if [ -n "$mem_kb" ]; then
    local mem_mb=$((mem_kb / 1024))
    if [ "$mem_mb" -lt "$min_mb" ]; then
      log_warn "Low memory detected (${mem_mb}MB). Provisioning may be slow or unreliable."
    fi
  else
    log_warn "Unable to determine total memory for provisioning checks."
  fi
}

check_network() {
  local url="${1:-https://deb.debian.org}"
  if axiom_command_exists curl; then
    curl -fsSL --max-time 5 "$url" >/dev/null 2>&1 && return 0
  elif axiom_command_exists wget; then
    wget -q --spider --timeout=5 "$url" >/dev/null 2>&1 && return 0
  else
    log_warn "Network check skipped: curl/wget not available."
    return 0
  fi
  log_error "Network connectivity check failed for ${url}."
  return 1
}

check_pkg_manager() {
  local mgr="$1"
  if ! axiom_command_exists "$mgr"; then
    log_error "Required package manager not found: $mgr"
    return 1
  fi
  if ! "$mgr" --version >/dev/null 2>&1; then
    log_error "Package manager health check failed: $mgr"
    return 1
  fi
  return 0
}

check_debian_pkg_manager() {
  local require_sudo="$1"
  if ! axiom_command_exists apt; then
    log_error "Required package manager not found: apt"
    return 1
  fi
  if ! apt --version >/dev/null 2>&1; then
    log_error "Package manager health check failed: apt"
    return 1
  fi
  if [ "$require_sudo" = "1" ]; then
    if ! axiom_command_exists sudo; then
      log_error "Required package manager not found: sudo"
      return 1
    fi
    if ! sudo --version >/dev/null 2>&1; then
      log_error "Package manager health check failed: sudo"
      return 1
    fi
  fi
  return 0
}

cockpit_mktemp() {
  if declare -F axiom_mktemp >/dev/null 2>&1; then
    axiom_mktemp
    return 0
  fi
  if axiom_command_exists mktemp; then
    mktemp 2>/dev/null || mktemp -t axiom 2>/dev/null || true
  else
    local tmp_dir tmp_file
    tmp_dir="${TMPDIR:-/tmp}"
    for _ in 1 2 3 4 5; do
      tmp_file="${tmp_dir}/axiom_temp_$$_${RANDOM}_${RANDOM}"
      if (umask 077 && set -o noclobber && : > "$tmp_file") 2>/dev/null; then
        printf '%s\n' "$tmp_file"
        return 0
      fi
    done
  fi
}

configure_locales() {
  log_info "Configuring locales (updating /etc/locale.gen and running locale-gen if available)."
  if [ -f /etc/locale.gen ]; then
    if grep -q '^# en_US.UTF-8 UTF-8' /etc/locale.gen; then
      log_info "Locale step: enabling en_US.UTF-8 in /etc/locale.gen (sudo/root may prompt)."
      if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
      else
        sudo sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
      fi
    fi
    if axiom_command_exists locale-gen; then
      log_info "Locale step: running locale-gen (this can take time)."
      if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        locale-gen
      else
        sudo locale-gen
      fi
    fi
  fi
}

ensure_gh_repo() {
  if axiom_command_exists gh; then
    return 0
  fi
  local keyring="/usr/share/keyrings/githubcli-archive-keyring.gpg"
  local source_list="/etc/apt/sources.list.d/github-cli.list"
  local distro
  distro="$(lsb_release -cs 2>/dev/null || echo stable)"

  if [ ! -f "$keyring" ]; then
    log_info "Bootstrapping GitHub CLI keyring via curl (network + sudo/root required)."
    if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | {
      if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        dd of="$keyring" >/dev/null 2>&1
      else
        sudo dd of="$keyring" >/dev/null 2>&1
      fi
    }; then
      log_error "Failed to fetch/install GitHub CLI keyring."
      return 1
    fi
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      chmod go+r "$keyring"
    else
      sudo chmod go+r "$keyring"
    fi
  fi

  if [ ! -f "$source_list" ]; then
    log_info "Configuring GitHub CLI apt source list (requires sudo/root)."
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages %s main\n' "$(dpkg --print-architecture)" "$keyring" "$distro" >"$source_list"
    else
      printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages %s main\n' "$(dpkg --print-architecture)" "$keyring" "$distro" | sudo tee "$source_list" >/dev/null
    fi
  fi

  log_info "Refreshing apt package lists after GitHub CLI repository changes (apt update may take time)."
  apt_update_once
}

install_nodesource_node() {
  if axiom_command_exists node; then
    return 0
  fi
  log_info "Bootstrapping NodeSource repository via curl (network + sudo/root required)."
  if ! curl -fsSL https://deb.nodesource.com/setup_lts.x | {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      bash -
    else
      sudo -E bash -
    fi
  }; then
    log_error "NodeSource repository bootstrap failed."
    return 1
  fi
  apt_install nodejs
}

install_nvm_node() {
  if axiom_command_exists node; then
    return 0
  fi

  local target_user="$1"
  local nvm_dir
  nvm_dir="/home/$target_user/.nvm"
  if [ "$target_user" = "root" ]; then
    nvm_dir="/root/.nvm"
  fi

  if [ ! -d "$nvm_dir" ]; then
    log_info "Installing NVM for user $target_user (curl bootstrap; network required)."
    if ! run_as_user "$target_user" bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"; then
      log_error "NVM install script failed for user $target_user"
      return 1
    fi
  fi

  log_info "Installing Node.js LTS via NVM"
  if ! run_as_user "$target_user" bash -c "source '$nvm_dir/nvm.sh' && nvm install --lts && nvm alias default 'lts/*'"; then
    log_error "Node.js installation via NVM failed for user $target_user"
    return 1
  fi
}

ensure_user() {
  local user="$1"
  if id "$user" >/dev/null 2>&1; then
    log_info "User already exists: $user"
    return 0
  fi

  ensure_root_or_sudo || return 1
  log_info "Creating user account: $user (requires sudo/root)."
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    useradd -m -s /bin/bash "$user"
  else
    sudo useradd -m -s /bin/bash "$user"
  fi
}

ensure_user_sudo() {
  local user="$1"
  ensure_root_or_sudo || return 1

  if axiom_command_exists sudo; then
    log_info "User setup: adding user to sudo group: $user (sudo/root required)."
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      usermod -aG sudo "$user"
    else
      sudo usermod -aG sudo "$user"
    fi
  fi

  if [ "$BLUX_SUDO_PASSWORDLESS" = "1" ]; then
    log_info "User setup: writing sudoers policy for $user (sudo/root required)."
    local sudoers_file="/etc/sudoers.d/cockpit-$user"
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" >"$sudoers_file"
      chmod 440 "$sudoers_file"
    else
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" | sudo tee "$sudoers_file" >/dev/null
      sudo chmod 440 "$sudoers_file"
    fi
  fi
}

summarize_installation() {
  local installed="$1"
  local remaining="$2"
  log_info "Summary:"
  log_info "Installed/available: ${installed:-none}"
  if [ -n "$remaining" ]; then
    log_warn "Remaining: $remaining"
  else
    log_info "No remaining actions detected."
  fi
}

provision_debian() {
  check_disk_space "/" || return 1
  check_memory_warn
  check_network "https://deb.debian.org" || return 1
  local require_sudo=1
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ "$COCKPIT_PLATFORM" != "proot-debian" ]; then
    require_sudo=0
  fi
  if [ "$COCKPIT_PLATFORM" = "proot-debian" ]; then
    require_sudo=1
  fi
  check_debian_pkg_manager "$require_sudo" || return 1

  local installed_list=()
  local remaining_list=()
  local user_created=0
  local nvm_used=0
  local needs_relogin=0

  local essentials=(
    sudo
    ca-certificates
    curl
    wget
    git
    gnupg
    lsb-release
    locales
    tzdata
    build-essential
    pkg-config
    unzip
    zip
    jq
  )

  local dev_tools=(
    zsh
    python3
    python3-venv
    python3-pip
    ruby-full
  )

  local extras=(
    ripgrep
    fd-find
    fzf
    bat
    neovim
    tmux
  )

  log_info "Provisioning Debian essentials (apt may prompt for sudo credentials)."
  apt_install "${essentials[@]}"
  log_info "Provisioning Debian development tools."
  apt_install "${dev_tools[@]}"

  if [ "$BLUX_INSTALL_EXTRAS" = "1" ]; then
    apt_install "${extras[@]}"
  fi

  configure_locales

  log_info "Ensuring GitHub CLI apt repository is configured."
  ensure_gh_repo
  apt_install gh

  if [ "$BLUX_NODE_METHOD" = "nvm" ]; then
    local target_user="$BLUX_USER"
    nvm_used=1
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
      target_user="${USER:-$BLUX_USER}"
    else
      if ! id "$BLUX_USER" >/dev/null 2>&1; then
        user_created=1
      fi
      ensure_user "$BLUX_USER"
    fi
    install_nvm_node "$target_user"
  else
    install_nodesource_node
  fi

  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    if ! id "$BLUX_USER" >/dev/null 2>&1; then
      user_created=1
    fi
    ensure_user "$BLUX_USER"
    ensure_user_sudo "$BLUX_USER"
  fi

  local check_packages=("${essentials[@]}" "${dev_tools[@]}")
  if [ "$BLUX_INSTALL_EXTRAS" = "1" ]; then
    check_packages+=("${extras[@]}")
  fi

  local pkg
  for pkg in "${check_packages[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      installed_list+=("$pkg")
    else
      remaining_list+=("$pkg")
    fi
  done

  if axiom_command_exists gh; then
    installed_list+=("gh")
  else
    remaining_list+=("gh")
  fi

  if axiom_command_exists node; then
    installed_list+=("nodejs")
  else
    remaining_list+=("nodejs")
  fi

  if axiom_command_exists sudo; then
    installed_list+=("sudo")
  else
    remaining_list+=("sudo")
  fi

  local installed="${installed_list[*]}"
  local remaining="${remaining_list[*]}"
  summarize_installation "$installed" "$remaining"

  if [ "$user_created" -eq 1 ]; then
    needs_relogin=1
    log_info "To use the new user, run: su - $BLUX_USER"
  fi
  if [ "$nvm_used" -eq 1 ]; then
    needs_relogin=1
    log_info "To use Node.js with NVM, reload your shell or run: source ~/.nvm/nvm.sh"
  fi

  if [ "${#remaining_list[@]}" -ne 0 ]; then
    log_warn "Provisioning incomplete. Please review the remaining items above."
    return 1
  fi

  if [ "$needs_relogin" -eq 1 ]; then
    log_info "Complete the steps above, then re-run your shell if needed."
  fi

  return 0
}

create_debian_provision_script() {
  local temp_file
  temp_file="$(cockpit_mktemp)"
  if [ -z "$temp_file" ] || [ ! -f "$temp_file" ]; then
    log_error "Failed to create temporary provision script."
    return 1
  fi
  if ! chmod 700 "$temp_file"; then
    log_error "Failed to set permissions on provision script."
    return 1
  fi
  trap "rm -f '${temp_file}' 2>/dev/null || true" EXIT INT TERM
  if ! cp "$SCRIPT_DIR/cockpit.sh" "$temp_file"; then
    log_error "Failed to populate provision script."
    return 1
  fi
  if [ ! -s "$temp_file" ]; then
    log_error "Provision script is empty or missing after creation."
    return 1
  fi
  chmod 700 "$temp_file"
  printf '%s\n' "$temp_file"
}

proot_distro_has_debian() {
  if ! axiom_command_exists proot-distro; then
    return 1
  fi

  if proot-distro list-installed >/dev/null 2>&1; then
    if proot-distro list-installed 2>/dev/null | awk '{print $1}' | grep -qx debian; then
      return 0
    fi
  fi

  if proot-distro login debian -c 'exit 0' >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

provision_termux() {
  check_disk_space "/" || return 1
  check_memory_warn
  check_network "https://packages.termux.org" || return 1
  check_pkg_manager pkg || return 1

  log_info "Ensuring Termux baseline dependencies"
  local packages=(
    python3
    git
    curl
    ca-certificates
    coreutils
    bash
    proot-distro
  )
  pkg_install "${packages[@]}"

  axiom_require_command proot-distro || return 1

  if proot_distro_has_debian; then
    log_info "Debian proot-distro already provisioned"
  else
    log_info "Provisioning Debian via proot-distro"
    proot-distro install debian
  fi

  log_info "Running Debian provisioning inside proot"
  local temp_script
  temp_script="$(create_debian_provision_script)"
  if ! proot-distro login debian -- env \
    BLUX_USER="$BLUX_USER" \
    BLUX_INSTALL_EXTRAS="$BLUX_INSTALL_EXTRAS" \
    BLUX_NODE_METHOD="$BLUX_NODE_METHOD" \
    BLUX_SUDO_PASSWORDLESS="$BLUX_SUDO_PASSWORDLESS" \
    bash -s <"$temp_script"; then
    log_warn "Debian provisioning failed inside proot."
    rm -f "$temp_script"
    return 1
  fi
  rm -f "$temp_script"

  log_info "Debian provisioning completed in Termux."
  log_info "To enter Debian: proot-distro login debian"
}

provision_macos() {
  check_disk_space "/" || return 1
  check_memory_warn
  check_network "https://brew.sh" || return 1

  local installed_list=()
  local remaining_list=()
  local needs_xcode=0

  if ! axiom_command_exists xcode-select; then
    remaining_list+=("xcode-select")
    needs_xcode=1
  else
    if ! xcode-select -p >/dev/null 2>&1; then
      log_warn "Xcode Command Line Tools not installed. Run: xcode-select --install"
      remaining_list+=("xcode-cli-tools")
      needs_xcode=1
    else
      installed_list+=("xcode-cli-tools")
    fi
  fi

  if ! axiom_command_exists brew; then
    log_info "Homebrew not found. Installing Homebrew."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if ! axiom_command_exists brew; then
    axiom_die "Homebrew installation failed." || return 1
  fi

  local brew_packages=(
    git
    curl
    wget
    python3
    node
    ruby
    gh
    zsh
    jq
    tmux
    neovim
    ripgrep
    fd
    fzf
    bat
  )

  local pkg
  for pkg in "${brew_packages[@]}"; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      installed_list+=("$pkg")
    else
      brew install "$pkg"
      if brew list --formula "$pkg" >/dev/null 2>&1; then
        installed_list+=("$pkg")
      else
        remaining_list+=("$pkg")
      fi
    fi
  done

  summarize_installation "${installed_list[*]}" "${remaining_list[*]}"

  if [ "${#remaining_list[@]}" -ne 0 ]; then
    log_warn "Provisioning incomplete on macOS."
    if [ "$needs_xcode" -eq 1 ]; then
      log_info "Finish by running: xcode-select --install"
      log_info "After installation completes, re-run this script."
    fi
    return 1
  fi
  return 0
}

provision_windows() {
  check_disk_space "/" || return 1
  check_memory_warn
  check_network "https://aka.ms" || return 1

  log_info "Detected Windows native environment"
  if axiom_command_exists wsl.exe || axiom_command_exists wsl; then
    local wsl_cmd
    if axiom_command_exists wsl.exe; then
      wsl_cmd="wsl.exe"
    else
      wsl_cmd="wsl"
    fi

    if "$wsl_cmd" -l -q >/dev/null 2>&1; then
      local distro
      distro="$("$wsl_cmd" -l -q | tr -d '\r' | grep -iE 'debian|ubuntu' | head -n1)"
      if [ -z "$distro" ]; then
        log_warn "No Debian/Ubuntu distro found in WSL. Attempting to install Debian."
        if "$wsl_cmd" --install -d Debian >/dev/null 2>&1; then
          distro="Debian"
        else
          axiom_die "WSL Debian install failed. Please run: wsl --install -d Debian" || return 1
        fi
      fi

      log_info "Running Debian provisioning inside WSL ($distro)"
      local temp_script
      temp_script="$(create_debian_provision_script)"
      if ! "$wsl_cmd" -d "$distro" -- env \
        BLUX_USER="$BLUX_USER" \
        BLUX_INSTALL_EXTRAS="$BLUX_INSTALL_EXTRAS" \
        BLUX_NODE_METHOD="$BLUX_NODE_METHOD" \
        BLUX_SUDO_PASSWORDLESS="$BLUX_SUDO_PASSWORDLESS" \
        bash -s <"$temp_script"; then
        log_warn "Debian provisioning failed inside WSL."
        rm -f "$temp_script"
        return 1
      fi
      rm -f "$temp_script"
      return 0
    fi

    axiom_die "WSL is installed but unavailable. Please start WSL once and try again." || return 1
  fi

  log_warn "WSL not available. Install WSL2 and Debian/Ubuntu first."
  log_warn "Steps:"
  log_warn "  1. Run: wsl --install -d Debian"
  log_warn "  2. Open the Debian app to finish setup"
  log_warn "  3. Re-run this script inside WSL"
  return 1
}

os_release_value() {
  local key="$1"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "$key" in
      ID) printf '%s' "${ID:-}" ;;
      ID_LIKE) printf '%s' "${ID_LIKE:-}" ;;
    esac
  fi
}

is_debian_like() {
  local id_like id
  id="$(os_release_value ID)"
  id_like="$(os_release_value ID_LIKE)"

  case "$id" in
    debian|ubuntu|linuxmint|pop|raspbian) return 0 ;;
  esac

  if [ -n "$id_like" ] && [ "${id_like#*debian}" != "$id_like" ]; then
    return 0
  fi

  return 1
}

provision_non_debian_linux() {
  check_disk_space "/" || return 1
  check_memory_warn
  check_network "https://www.kernel.org" || return 1

  log_warn "Non-Debian Linux detected. Attempting best-effort native install."

  local installed_list=()
  local remaining_list=()

  local packages=(
    git
    curl
    wget
    python3
    ruby
    nodejs
    zsh
    jq
    tmux
  )

  if axiom_command_exists dnf; then
    log_info "Installing packages with dnf (may wait on sudo/password prompts)."
    sudo dnf install -y "${packages[@]}" || true
  elif axiom_command_exists yum; then
    log_info "Installing packages with yum (may wait on sudo/password prompts)."
    sudo yum install -y "${packages[@]}" || true
  elif axiom_command_exists pacman; then
    log_info "Installing packages with pacman (may wait on sudo/password prompts)."
    sudo pacman -Sy --noconfirm "${packages[@]}" || true
  elif axiom_command_exists zypper; then
    log_info "Installing packages with zypper (may wait on sudo/password prompts)."
    sudo zypper install -y "${packages[@]}" || true
  else
    log_warn "No supported package manager found."
  fi

  local pkg
  for pkg in "${packages[@]}"; do
    if axiom_command_exists "$pkg"; then
      installed_list+=("$pkg")
    else
      remaining_list+=("$pkg")
    fi
  done

  summarize_installation "${installed_list[*]}" "${remaining_list[*]}"
  log_warn "For full Debian provisioning, use a Debian container/chroot or switch to a Debian-based distro."
  return 1
}

load_config() {
  local env_file
  env_file="$(axiom_config_dir)/.env"
  axiom_load_env_file "$env_file"

  BLUX_USER="$(axiom_env_get BLUX_USER "blux")"
  BLUX_INSTALL_EXTRAS="$(axiom_env_bool BLUX_INSTALL_EXTRAS "1")"
  BLUX_NODE_METHOD="$(axiom_env_get BLUX_NODE_METHOD "nodesource")"
  BLUX_SUDO_PASSWORDLESS="$(axiom_env_bool BLUX_SUDO_PASSWORDLESS "0")"

  export BLUX_USER
  export BLUX_INSTALL_EXTRAS
  export BLUX_NODE_METHOD
  export BLUX_SUDO_PASSWORDLESS
}

finalize_run() {
  local exit_code="$1"
  local ended_at
  ended_at="$(axiom_now_utc)"

  if [ -n "${RUN_DIR:-}" ]; then
    axiom_runs_write_metadata "$RUN_DIR" "setup" "cockpit" "$RUN_COMMAND" "$exit_code" "$STARTED_AT" "$ended_at" "$(pwd -P)"
  fi
}

main() {
  RUN_COMMAND="$(printf '%q ' "$0" "$@")"
  STARTED_AT="$(axiom_now_utc)"
  RUN_DIR="$(axiom_runs_create_dir "setup" "cockpit")"
  trap 'finalize_run "$?"' EXIT

  load_config

  log_info "Starting cockpit provisioning"

  local platform
  platform="$(axiom_detect_platform)"
  COCKPIT_PLATFORM="$platform"

  case "$platform" in
    proot-debian)
      log_info "Detected proot-distro Debian (distinct from Termux native)"
      ;;
    termux)
      log_info "Detected Termux environment"
      provision_termux
      return $?
      ;;
    windows)
      provision_windows
      return $?
      ;;
    macos)
      log_info "Detected macOS environment"
      provision_macos
      return $?
      ;;
    wsl)
      log_info "Detected WSL environment"
      ;;
    debian)
      log_info "Detected Debian environment"
      ;;
    linux|proot)
      log_info "Detected Linux environment"
      ;;
    *)
      log_warn "Unknown platform detected. Proceeding with Linux defaults."
      ;;
  esac

  if is_debian_like; then
    provision_debian
    return $?
  fi

  provision_non_debian_linux
}

main "$@"
