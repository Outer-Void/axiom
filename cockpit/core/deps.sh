#!/usr/bin/env bash

# =============================================================================
# Dependency Management System
# Tier: Core Library (Integrates with all tiers)
# Description: Manages and validates system dependencies
# Dependencies: core/log.sh, core/platform.sh, core/shell.sh
# Usage: Source in scripts needing dependency validation
# =============================================================================

# Dependency specifications: name:min_version:description:category
declare -a AXIOM_DEPENDENCIES=(
  # ========== CORE DEPENDENCIES (Required) ==========
  "bash:4.0:Shell interpreter:core"
  "git:2.0:Version control system:core"
  "curl:7.0:HTTP client for downloads:core"
  
  # ========== PLATFORM DEPENDENCIES ==========
  # Linux/Debian
  "apt-get:1.0:Package manager (Debian/Ubuntu):platform:debian"
  "dpkg:1.0:Debian package management:platform:debian"
  
  # macOS
  "brew:2.0:Package manager (macOS):platform:macos"
  
  # Termux
  "pkg:0.0:Termux package manager:platform:termux"
  "termux-setup-storage:0.0:Termux storage setup:platform:termux"
  
  # Windows/WSL
  "wsl.exe:0.0:Windows Subsystem for Linux:platform:wsl"
  "powershell.exe:5.0:Windows PowerShell:platform:windows"
  
  # ========== DEVELOPMENT DEPENDENCIES ==========
  "python3:3.8:Python interpreter:dev"
  "python3-venv:3.8:Python virtual environment:dev"
  "pip3:20.0:Python package manager:dev"
  "node:14.0:JavaScript runtime:dev"
  "npm:6.0:Node package manager:dev"
  "zsh:5.0:Z Shell:dev"
  
  # ========== UTILITY DEPENDENCIES ==========
  "jq:1.5:JSON processor:util"
  "fzf:0.20:Fuzzy finder:util"
  "ripgrep:11.0:Fast recursive grep:util"
  "bat:0.12:Syntax highlighting cat:util"
  "fd:7.0:Simple fast find:util"
  "eza:0.9:Modern ls replacement:util"
  "neovim:0.4:Modern Vim editor:util"
  "tmux:3.0:Terminal multiplexer:util"
  
  # ========== OPTIONAL/ENHANCEMENT ==========
  "docker:19.0:Container platform:optional"
  "podman:2.0:Container engine:optional"
  "gh:1.0:GitHub CLI:optional"
  "aws:2.0:AWS CLI:optional"
  "kubectl:1.18:Kubernetes CLI:optional"
)

# Get current platform
_get_current_platform() {
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/platform.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"
    axiom_detect_platform
  else
    # Fallback platform detection
    case "$(uname -s)" in
      Linux*)  echo "linux" ;;
      Darwin*) echo "macos" ;;
      CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
      *)       echo "unknown" ;;
    esac
  fi
}

# Compare version numbers
_compare_versions() {
  local v1="$1"
  local v2="$2"
  
  # Simple numeric comparison for common cases
  if [[ "$v1" =~ ^[0-9]+(\.[0-9]+)*$ ]] && [[ "$v2" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    local IFS=.
    local i ver1=($v1) ver2=($v2)
    
    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
      local num1=${ver1[i]:-0}
      local num2=${ver2[i]:-0}
      if ((num1 > num2)); then
        echo "greater"
        return 0
      elif ((num1 < num2)); then
        echo "less"
        return 0
      fi
    done
    echo "equal"
    return 0
  fi
  
  # Fallback string comparison
  if [[ "$v1" > "$v2" ]]; then
    echo "greater"
  elif [[ "$v1" < "$v2" ]]; then
    echo "less"
  else
    echo "equal"
  fi
}

# Extract version from command output
_extract_version() {
  local cmd="$1"
  local output
    
  case "$cmd" in
    bash)
      output="$("$cmd" --version 2>/dev/null | head -1)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1
      ;;
    git)
      output="$("$cmd" --version 2>/dev/null)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1
      ;;
    curl|wget)
      output="$("$cmd" --version 2>/dev/null | head -1)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+' | head -1
      ;;
    python3|python)
      output="$("$cmd" --version 2>/dev/null)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1
      ;;
    node)
      output="$("$cmd" --version 2>/dev/null)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/v//'
      ;;
    npm)
      output="$("$cmd" --version 2>/dev/null)"
      echo "$output" | head -1
      ;;
    docker|podman)
      output="$("$cmd" --version 2>/dev/null | head -1)"
      echo "$output" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1
      ;;
    *)
      # Generic version extraction
      if "$cmd" --version >/dev/null 2>&1; then
        output="$("$cmd" --version 2>/dev/null | head -1)"
        echo "$output" | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)*' | head -1
      elif "$cmd" -v >/dev/null 2>&1; then
        output="$("$cmd" -v 2>/dev/null | head -1)"
        echo "$output" | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)*' | head -1
      elif "$cmd" version >/dev/null 2>&1; then
        output="$("$cmd" version 2>/dev/null | head -1)"
        echo "$output" | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)*' | head -1
      else
        echo "0.0"
      fi
      ;;
  esac
}

# Check dependencies by category
axiom_check_dependencies() {
  local category="${1:-all}"
  local platform="$(_get_current_platform)"
  local missing=()
  local outdated=()
  local optional_missing=()
  
  for dep_spec in "${AXIOM_DEPENDENCIES[@]}"; do
    IFS=':' read -r dep min_version description dep_category dep_platform <<< "$dep_spec"
    
    # Skip if platform doesn't match (unless no platform specified)
    if [ -n "$dep_platform" ] && [ "$dep_platform" != "$platform" ]; then
      continue
    fi
    
    # Skip if category doesn't match
    if [ "$category" != "all" ] && [ "$dep_category" != "$category" ]; then
      continue
    fi
    
    # Check if command exists
    if ! command -v "$dep" >/dev/null 2>&1; then
      if [ "$dep_category" = "core" ]; then
        missing+=("$dep:$description")
      elif [ "$dep_category" = "optional" ]; then
        optional_missing+=("$dep:$description")
      else
        missing+=("$dep:$description")
      fi
      continue
    fi
    
    # Check version if specified and not "0.0"
    if [[ "$min_version" =~ ^[0-9] ]] && [ "$min_version" != "0.0" ]; then
      local current_version
      current_version="$(_extract_version "$dep")"
      
      if [ -n "$current_version" ] && [ "$current_version" != "0.0" ]; then
        local comparison
        comparison="$(_compare_versions "$current_version" "$min_version")"
        
        if [ "$comparison" = "less" ]; then
          outdated+=("$dep: installed=$current_version, required=$min_version")
        fi
      fi
    fi
  done
  
  # Report results
  if [ ${#missing[@]} -gt 0 ]; then
    axiom_log_warn "Missing dependencies ($category):"
    for item in "${missing[@]}"; do
      IFS=':' read -r cmd desc <<< "$item"
      axiom_log_info "  ✗ $cmd - $desc"
    done
  fi
  
  if [ ${#outdated[@]} -gt 0 ]; then
    axiom_log_warn "Outdated dependencies ($category):"
    for item in "${outdated[@]}"; do
      axiom_log_info "  ⚠ $item"
    done
  fi
  
  if [ ${#optional_missing[@]} -gt 0 ] && [ "$category" = "all" ]; then
    axiom_log_info "Optional dependencies available:"
    for item in "${optional_missing[@]}"; do
      IFS=':' read -r cmd desc <<< "$item"
      axiom_log_info "  ○ $cmd - $desc"
    done
  fi
  
  # Return status
  if [ ${#missing[@]} -gt 0 ]; then
    return 1
  fi
  return 0
}

# Get installation command for a dependency
axiom_get_install_command() {
  local dep="$1"
  local platform="$(_get_current_platform)"
  
  case "$platform" in
    termux)
      echo "pkg install $dep"
      ;;
    debian|ubuntu|linux)
      case "$dep" in
        python3-venv) echo "sudo apt install python3-venv" ;;
        docker) echo "curl -fsSL https://get.docker.com | sh" ;;
        podman) echo "sudo apt install podman" ;;
        gh) echo "type -p curl >/dev/null || sudo apt install curl -y; curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install gh -y" ;;
        *) echo "sudo apt install $dep" ;;
      esac
      ;;
    macos)
      case "$dep" in
        python3-venv) echo "python3 -m ensurepip --upgrade && python3 -m pip install virtualenv" ;;
        *) echo "brew install $dep" ;;
      esac
      ;;
    wsl)
      echo "sudo apt install $dep"
      ;;
    *)
      echo "# Install $dep manually for $platform"
      ;;
  esac
}

# Install missing dependencies interactively
axiom_install_missing_dependencies() {
  local category="${1:-core}"
  local platform="$(_get_current_platform)"
  
  axiom_log_info "Checking $category dependencies for $platform..."
  
  # Create temp arrays to track what we need
  local missing=()
  local outdated=()
  
  # Check dependencies
  for dep_spec in "${AXIOM_DEPENDENCIES[@]}"; do
    IFS=':' read -r dep min_version description dep_category dep_platform <<< "$dep_spec"
    
    # Skip if not in requested category
    if [ "$category" != "all" ] && [ "$dep_category" != "$category" ]; then
      continue
    fi
    
    # Skip if platform specific and doesn't match
    if [ -n "$dep_platform" ] && [ "$dep_platform" != "$platform" ]; then
      continue
    fi
    
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep:$description:$dep_category")
      continue
    fi
    
    # Check version
    if [[ "$min_version" =~ ^[0-9] ]] && [ "$min_version" != "0.0" ]; then
      local current_version
      current_version="$(_extract_version "$dep")"
      
      if [ -n "$current_version" ]; then
        local comparison
        comparison="$(_compare_versions "$current_version" "$min_version")"
        
        if [ "$comparison" = "less" ]; then
          outdated+=("$dep:$current_version:$min_version:$description")
        fi
      fi
    fi
  done
  
  # Install missing dependencies
  if [ ${#missing[@]} -gt 0 ]; then
    axiom_log_info "Installing ${#missing[@]} missing dependencies..."
    
    for item in "${missing[@]}"; do
      IFS=':' read -r dep description category <<< "$item"
      
      axiom_log_info "Installing $dep ($description)..."
      local install_cmd
      install_cmd="$(axiom_get_install_command "$dep")"
      
      if [[ "$install_cmd" =~ ^# ]]; then
        axiom_log_warn "Manual installation required: $install_cmd"
      else
        if eval "$install_cmd"; then
          axiom_log_info "✓ Successfully installed $dep"
        else
          axiom_log_error "Failed to install $dep"
          return 1
        fi
      fi
    done
  else
    axiom_log_info "✓ All $category dependencies are installed"
  fi
  
  # Report outdated dependencies
  if [ ${#outdated[@]} -gt 0 ]; then
    axiom_log_warn "The following dependencies are outdated:"
    for item in "${outdated[@]}"; do
      IFS=':' read -r dep current required description <<< "$item"
      axiom_log_info "  $dep: $current < $required ($description)"
    done
  fi
  
  return 0
}

# Generate dependency report
axiom_dependency_report() {
  local platform="$(_get_current_platform)"
  local output_file="${1:-}"
  
  axiom_log_info "Generating dependency report for $platform..."
  
  local report=""
  report+="# AXIOM Dependency Report\n"
  report+="Generated: $(date)\n"
  report+="Platform: $platform\n"
  report+="System: $(uname -a)\n\n"
  
  report+="## Dependency Status\n\n"
  
  for dep_spec in "${AXIOM_DEPENDENCIES[@]}"; do
    IFS=':' read -r dep min_version description category dep_platform <<< "$dep_spec"
    
    # Skip if platform specific and doesn't match
    if [ -n "$dep_platform" ] && [ "$dep_platform" != "$platform" ]; then
      continue
    fi
    
    if command -v "$dep" >/dev/null 2>&1; then
      local current_version
      current_version="$(_extract_version "$dep")"
      local status="✓"
      
      if [[ "$min_version" =~ ^[0-9] ]] && [ "$min_version" != "0.0" ]; then
        local comparison
        comparison="$(_compare_versions "$current_version" "$min_version")"
        
        if [ "$comparison" = "less" ]; then
          status="⚠"
        fi
      fi
      
      report+="- $status **$dep** v$current_version"
      if [ "$min_version" != "0.0" ]; then
        report+=" (min: v$min_version)"
      fi
      report+=" - $description [$category]\n"
    else
      report+="- ✗ **$dep** MISSING"
      if [ "$min_version" != "0.0" ]; then
        report+=" (min: v$min_version)"
      fi
      report+=" - $description [$category]\n"
    fi
  done
  
  report+="\n## Installation Summary\n\n"
  report+="Legend: ✓ Installed, ⚠ Outdated, ✗ Missing\n"
  
  if [ -n "$output_file" ]; then
    echo -e "$report" > "$output_file"
    axiom_log_info "Report saved to: $output_file"
  else
    echo -e "$report"
  fi
}

# Quick health check
axiom_health_check() {
  axiom_log_info "Running AXIOM health check..."
  
  local checks=0
  local passed=0
  
  # Check core dependencies
  checks=$((checks + 1))
  if axiom_check_dependencies "core" >/dev/null 2>&1; then
    axiom_log_info "✓ Core dependencies: OK"
    passed=$((passed + 1))
  else
    axiom_log_warn "✗ Core dependencies: Missing"
  fi
  
  # Check dev dependencies
  checks=$((checks + 1))
  if axiom_check_dependencies "dev" >/dev/null 2>&1; then
    axiom_log_info "✓ Development dependencies: OK"
    passed=$((passed + 1))
  else
    axiom_log_info "⚠ Development dependencies: Partial"
    passed=$((passed + 1))  # Dev deps are not critical
  fi
  
  # Check disk space
  checks=$((checks + 1))
  local available_mb
  available_mb=$(df -m . 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
  if [ "$available_mb" -gt 100 ]; then
    axiom_log_info "✓ Disk space: ${available_mb}MB available"
    passed=$((passed + 1))
  else
    axiom_log_warn "⚠ Disk space: Only ${available_mb}MB available"
    passed=$((passed + 1))  # Warn but don't fail
  fi
  
  # Report
  axiom_log_info "Health check: $passed/$checks passed"
  
  if [ $passed -eq $checks ]; then
    axiom_log_info "✅ System is healthy"
    return 0
  elif [ $passed -ge $((checks - 1)) ]; then
    axiom_log_info "⚠️ System has minor issues"
    return 0
  else
    axiom_log_warn "❌ System has critical issues"
    return 1
  fi
}

# Main function for standalone usage
main() {
  local action="${1:-check}"
  
  case "$action" in
    check)
      axiom_check_dependencies "all"
      ;;
    install)
      axiom_install_missing_dependencies "core"
      ;;
    report)
      axiom_dependency_report
      ;;
    health)
      axiom_health_check
      ;;
    help|--help|-h)
      cat <<EOF
AXIOM Dependency Manager

Usage: deps.sh [command]

Commands:
  check     Check all dependencies (default)
  install   Install missing core dependencies
  report    Generate detailed dependency report
  health    Run system health check
  help      Show this help message

Examples:
  ./deps.sh check
  ./deps.sh install
  ./deps.sh report > dependencies.md
EOF
      ;;
    *)
      axiom_log_error "Unknown command: $action"
      axiom_log_info "Use 'help' for usage information"
      return 1
      ;;
  esac
}

# If script is executed directly, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
