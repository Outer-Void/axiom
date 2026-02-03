#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[cockpit] %s\n' "$*"
}

warn() {
  printf '[cockpit][warning] %s\n' "$*" >&2
}

die() {
  printf '[cockpit][error] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]
}

is_wsl() {
  [[ -r /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version
}

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_windows_native() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  [[ "${OS:-}" == "Windows_NT" ]]
}

os_release_value() {
  local key="$1"
  if [[ -r /etc/os-release ]]; then
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

  if [[ "$id_like" == *"debian"* ]]; then
    return 0
  fi

  return 1
}

BLUX_USER="blux"
BLUX_INSTALL_EXTRAS="1"
BLUX_NODE_METHOD="nodesource"
BLUX_SUDO_PASSWORDLESS="0"

parse_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    local key value
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    line="${line#export }"
    IFS='=' read -r key value <<< "$line"
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$key" ]] && continue

    value="${value:-}"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    value="${value%"\""}"
    value="${value#"\""}"
    value="${value%"'"}"
    value="${value#"'"}"

    case "$key" in
      BLUX_USER) BLUX_USER="$value" ;;
      BLUX_INSTALL_EXTRAS) BLUX_INSTALL_EXTRAS="$value" ;;
      BLUX_NODE_METHOD) BLUX_NODE_METHOD="$value" ;;
      BLUX_SUDO_PASSWORDLESS) BLUX_SUDO_PASSWORDLESS="$value" ;;
      *) warn "Ignoring unknown config key: $key" ;;
    esac
  done < "$env_file"
}

ensure_root_or_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    return 0
  fi
  if command_exists sudo; then
    return 0
  fi
  die "Root privileges are required for package installation. Please run as root or install sudo."
}

apt_update_once() {
  local marker="/tmp/cockpit-apt-updated"
  if [[ ! -f "$marker" ]]; then
    local apt_cmd=(apt-get)
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
      apt_cmd=(sudo apt-get)
    fi
    log "Updating apt package lists"
    DEBIAN_FRONTEND=noninteractive "${apt_cmd[@]}" update
    touch "$marker"
  fi
}

apt_install() {
  local packages=()
  for pkg in "$@"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log "Already installed: $pkg"
    else
      packages+=("$pkg")
    fi
  done

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  ensure_root_or_sudo
  apt_update_once
  local apt_cmd=(apt-get)
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    apt_cmd=(sudo apt-get)
  fi

  log "Installing packages: ${packages[*]}"
  DEBIAN_FRONTEND=noninteractive "${apt_cmd[@]}" install -y "${packages[@]}"
}

pkg_install() {
  local packages=()
  for pkg in "$@"; do
    if command_exists dpkg && dpkg -s "$pkg" >/dev/null 2>&1; then
      log "Already installed: $pkg"
    elif ! command_exists dpkg && pkg list-installed 2>/dev/null | awk -F/ '{print $1}' | grep -qx "$pkg"; then
      log "Already installed: $pkg"
    else
      packages+=("$pkg")
    fi
  done

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  command_exists pkg || die "Termux pkg tool not found"
  log "Installing packages: ${packages[*]}"
  pkg install -y "${packages[@]}"
}

run_as_user() {
  local user="$1"
  shift
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    if command_exists sudo; then
      sudo -u "$user" "$@"
    else
      su - "$user" -c "$(printf '%q ' "$@")"
    fi
  else
    "$@"
  fi
}

configure_locales() {
  if [[ -f /etc/locale.gen ]]; then
    if grep -q '^# en_US.UTF-8 UTF-8' /etc/locale.gen; then
      if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
      else
        sudo sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
      fi
    fi
    if command_exists locale-gen; then
      if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        locale-gen
      else
        sudo locale-gen
      fi
    fi
  fi
}

ensure_gh_repo() {
  if command_exists gh; then
    return 0
  fi
  local keyring="/usr/share/keyrings/githubcli-archive-keyring.gpg"
  local source_list="/etc/apt/sources.list.d/github-cli.list"
  local distro
  distro="$(lsb_release -cs 2>/dev/null || echo stable)"

  if [[ ! -f "$keyring" ]]; then
    log "Adding GitHub CLI apt repository"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | {
      if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        dd of="$keyring" >/dev/null 2>&1
      else
        sudo dd of="$keyring" >/dev/null 2>&1
      fi
    }
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      chmod go+r "$keyring"
    else
      sudo chmod go+r "$keyring"
    fi
  fi

  if [[ ! -f "$source_list" ]]; then
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages %s main\n' "$(dpkg --print-architecture)" "$keyring" "$distro" > "$source_list"
    else
      printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages %s main\n' "$(dpkg --print-architecture)" "$keyring" "$distro" | sudo tee "$source_list" >/dev/null
    fi
  fi

  apt_update_once
}

install_nodesource_node() {
  if command_exists node; then
    return 0
  fi
  log "Configuring NodeSource Node.js repository"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      bash -
    else
      sudo -E bash -
    fi
  }
  apt_install nodejs
}

install_nvm_node() {
  if command_exists node; then
    return 0
  fi

  local target_user="$1"
  local nvm_dir
  nvm_dir="/home/$target_user/.nvm"
  if [[ "${target_user}" == "root" ]]; then
    nvm_dir="/root/.nvm"
  fi

  if [[ ! -d "$nvm_dir" ]]; then
    log "Installing NVM for user $target_user"
    run_as_user "$target_user" bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
  fi

  log "Installing Node.js LTS via NVM"
  run_as_user "$target_user" bash -c "source '$nvm_dir/nvm.sh' && nvm install --lts && nvm alias default 'lts/*'"
}

ensure_user() {
  local user="$1"
  if id "$user" >/dev/null 2>&1; then
    log "User already exists: $user"
    return 0
  fi

  ensure_root_or_sudo
  log "Creating user: $user"
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    useradd -m -s /bin/bash "$user"
  else
    sudo useradd -m -s /bin/bash "$user"
  fi
}

ensure_user_sudo() {
  local user="$1"
  ensure_root_or_sudo

  if command_exists sudo; then
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      usermod -aG sudo "$user"
    else
      sudo usermod -aG sudo "$user"
    fi
  fi

  if [[ "$BLUX_SUDO_PASSWORDLESS" == "1" ]]; then
    log "Enabling passwordless sudo for $user"
    local sudoers_file="/etc/sudoers.d/cockpit-$user"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "$sudoers_file"
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
  log "Summary:"
  log "Installed/available: ${installed:-none}"
  if [[ -n "$remaining" ]]; then
    warn "Remaining: $remaining"
  else
    log "No remaining actions detected."
  fi
}

provision_debian() {
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

  apt_install "${essentials[@]}"
  apt_install "${dev_tools[@]}"

  if [[ "$BLUX_INSTALL_EXTRAS" == "1" ]]; then
    apt_install "${extras[@]}"
  fi

  configure_locales

  ensure_gh_repo
  apt_install gh

  if [[ "$BLUX_NODE_METHOD" == "nvm" ]]; then
    local target_user="$BLUX_USER"
    nvm_used=1
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
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

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    if ! id "$BLUX_USER" >/dev/null 2>&1; then
      user_created=1
    fi
    ensure_user "$BLUX_USER"
    ensure_user_sudo "$BLUX_USER"
  fi

  local check_packages=("${essentials[@]}" "${dev_tools[@]}")
  if [[ "$BLUX_INSTALL_EXTRAS" == "1" ]]; then
    check_packages+=("${extras[@]}")
  fi

  for pkg in "${check_packages[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      installed_list+=("$pkg")
    else
      remaining_list+=("$pkg")
    fi
  done

  if command_exists gh; then
    installed_list+=("gh")
  else
    remaining_list+=("gh")
  fi

  if command_exists node; then
    installed_list+=("nodejs")
  else
    remaining_list+=("nodejs")
  fi

  if command_exists sudo; then
    installed_list+=("sudo")
  else
    remaining_list+=("sudo")
  fi

  local installed="${installed_list[*]}"
  local remaining="${remaining_list[*]}"
  summarize_installation "$installed" "$remaining"

  if [[ $user_created -eq 1 ]]; then
    needs_relogin=1
    log "To use the new user, run: su - $BLUX_USER"
  fi
  if [[ $nvm_used -eq 1 ]]; then
    needs_relogin=1
    log "To load NVM for Node.js, run: source ~/.nvm/nvm.sh"
  fi

  if [[ ${#remaining_list[@]} -ne 0 ]]; then
    warn "Provisioning incomplete. Please review the remaining items above."
    return 1
  fi

  if [[ $needs_relogin -eq 1 ]]; then
    log "Complete the steps above, then re-run your shell if needed."
  fi

  return 0
}

render_debian_provision_script() {
  cat <<'EOS'
set -euo pipefail
EOS
  declare -f log warn die command_exists ensure_root_or_sudo apt_update_once apt_install configure_locales ensure_gh_repo install_nodesource_node run_as_user install_nvm_node ensure_user ensure_user_sudo summarize_installation provision_debian
  cat <<'EOS'
provision_debian
EOS
}

proot_distro_has_debian() {
  if ! command_exists proot-distro; then
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
  log "Ensuring Termux baseline dependencies"
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

  if ! command_exists proot-distro; then
    die "proot-distro is required but not available."
  fi

  if proot_distro_has_debian; then
    log "Debian proot-distro already provisioned"
  else
    log "Provisioning Debian via proot-distro"
    proot-distro install debian
  fi

  log "Running Debian provisioning inside proot"
  if ! proot-distro login debian -- env \
    BLUX_USER="$BLUX_USER" \
    BLUX_INSTALL_EXTRAS="$BLUX_INSTALL_EXTRAS" \
    BLUX_NODE_METHOD="$BLUX_NODE_METHOD" \
    BLUX_SUDO_PASSWORDLESS="$BLUX_SUDO_PASSWORDLESS" \
    bash -lc "$(render_debian_provision_script)"; then
    warn "Debian provisioning failed inside proot."
    return 1
  fi

  log "Debian provisioning completed in Termux."
  log "To enter Debian: proot-distro login debian"
}

provision_macos() {
  local installed_list=()
  local remaining_list=()
  local needs_xcode=0

  if ! command_exists xcode-select; then
    remaining_list+=("xcode-select")
    needs_xcode=1
  else
    if ! xcode-select -p >/dev/null 2>&1; then
      warn "Xcode Command Line Tools not installed. Run: xcode-select --install"
      remaining_list+=("xcode-cli-tools")
      needs_xcode=1
    else
      installed_list+=("xcode-cli-tools")
    fi
  fi

  if ! command_exists brew; then
    log "Homebrew not found. Installing Homebrew."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if ! command_exists brew; then
    die "Homebrew installation failed."
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

  if [[ ${#remaining_list[@]} -ne 0 ]]; then
    warn "Provisioning incomplete on macOS."
    if [[ $needs_xcode -eq 1 ]]; then
      log "Finish by running: xcode-select --install"
      log "After installation completes, re-run this script."
    fi
    return 1
  fi
  return 0
}

provision_windows() {
  log "Detected Windows native environment"
  if command_exists wsl.exe || command_exists wsl; then
    local wsl_cmd
    if command_exists wsl.exe; then
      wsl_cmd="wsl.exe"
    else
      wsl_cmd="wsl"
    fi

    if "$wsl_cmd" -l -q >/dev/null 2>&1; then
      local distro
      distro="$($wsl_cmd -l -q | tr -d '\r' | grep -iE 'debian|ubuntu' | head -n1)"
      if [[ -z "$distro" ]]; then
        warn "No Debian/Ubuntu distro found in WSL. Attempting to install Debian."
        if "$wsl_cmd" --install -d Debian >/dev/null 2>&1; then
          distro="Debian"
        else
          die "WSL Debian install failed. Please run: wsl --install -d Debian"
        fi
      fi

      log "Running Debian provisioning inside WSL ($distro)"
      if ! "$wsl_cmd" -d "$distro" -- env \
        BLUX_USER="$BLUX_USER" \
        BLUX_INSTALL_EXTRAS="$BLUX_INSTALL_EXTRAS" \
        BLUX_NODE_METHOD="$BLUX_NODE_METHOD" \
        BLUX_SUDO_PASSWORDLESS="$BLUX_SUDO_PASSWORDLESS" \
        bash -lc "$(render_debian_provision_script)"; then
        warn "Debian provisioning failed inside WSL."
        return 1
      fi
      return 0
    fi

    die "WSL is installed but unavailable. Please start WSL once and try again."
  fi

  warn "WSL not available. Install WSL2 and Debian/Ubuntu first."
  warn "Steps:"
  warn "  1. Run: wsl --install -d Debian"
  warn "  2. Open the Debian app to finish setup"
  warn "  3. Re-run this script inside WSL"
  return 1
}

provision_non_debian_linux() {
  warn "Non-Debian Linux detected. Attempting best-effort native install."

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

  if command_exists dnf; then
    sudo dnf install -y "${packages[@]}" || true
  elif command_exists yum; then
    sudo yum install -y "${packages[@]}" || true
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm "${packages[@]}" || true
  elif command_exists zypper; then
    sudo zypper install -y "${packages[@]}" || true
  else
    warn "No supported package manager found."
  fi

  for pkg in "${packages[@]}"; do
    if command_exists "$pkg"; then
      installed_list+=("$pkg")
    else
      remaining_list+=("$pkg")
    fi
  done

  summarize_installation "${installed_list[*]}" "${remaining_list[*]}"
  warn "For full Debian provisioning, use a Debian container/chroot or switch to a Debian-based distro."
  return 1
}

main() {
  parse_env_file "cockpit/config/.env"

  if is_termux; then
    log "Detected Termux environment"
    provision_termux
    return $?
  fi

  if is_windows_native; then
    provision_windows
    return $?
  fi

  if is_macos; then
    log "Detected macOS environment"
    provision_macos
    return $?
  fi

  if is_wsl; then
    log "Detected WSL environment"
  else
    log "Detected Linux environment"
  fi

  if is_debian_like; then
    provision_debian
    return $?
  fi

  provision_non_debian_linux
}

main "$@"
