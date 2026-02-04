#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Configuration Validation System
# Tier: Core Library (Integrates with Tier 2+)
# Description: Validates configuration files and system structure
# Dependencies: core/log.sh, core/constants.sh, core/env.sh
# Usage: Source in scripts needing validation
# =============================================================================

# Load core libraries if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/log.sh" ]; then
  source "$(dirname "${BASH_SOURCE[0]}")/log.sh"
else
  # Fallback logging functions
  axiom_log_info() { echo "[info] $*"; }
  axiom_log_warn() { echo "[warn] $*" >&2; }
  axiom_log_error() { echo "[error] $*" >&2; }
fi

# Validate a single configuration line
_validate_config_line() {
  local line="$1"
  local line_num="$2"
  local errors_ref="$3"
  local warnings_ref="$4"
  
  # Remove leading/trailing whitespace for validation
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  
  # Skip empty lines and comments
  if [ -z "$trimmed" ] || [[ "$trimmed" =~ ^# ]]; then
    return 0
  fi
  
  # Check for export keyword (optional but consistent)
  if [[ "$trimmed" =~ ^export[[:space:]]+ ]]; then
    trimmed="${trimmed#export}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  fi
  
  # Must contain equals sign
  if [[ ! "$trimmed" =~ = ]]; then
    eval "$errors_ref+=(\"Line $line_num: Missing '=' in assignment\")"
    return 1
  fi
  
  # Extract variable name and value
  local var_name="${trimmed%%=*}"
  local value="${trimmed#*=}"
  
  # Trim whitespace from var_name
  var_name="${var_name%"${var_name##*[![:space:]]}"}"
  
  # Validate variable name
  if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    eval "$errors_ref+=(\"Line $line_num: Invalid variable name '$var_name'\")"
    return 1
  fi
  
  # Check for spaces around equals (warning)
  if [[ "$line" =~ [[:space:]]= ]] || [[ "$line" =~ =[[:space:]] ]]; then
    eval "$warnings_ref+=(\"Line $line_num: Spaces around '=' (recommend removing)\")"
  fi
  
  # Check for unclosed quotes
  local single_quotes
  local double_quotes
  single_quotes=$(echo "$value" | tr -cd "'" | wc -c)
  double_quotes=$(echo "$value" | tr -cd '"' | wc -c)
  
  if [ $((single_quotes % 2)) -ne 0 ]; then
    eval "$errors_ref+=(\"Line $line_num: Unclosed single quote\")"
    return 1
  fi
  
  if [ $((double_quotes % 2)) -ne 0 ]; then
    eval "$errors_ref+=(\"Line $line_num: Unclosed double quote\")"
    return 1
  fi
  
  # Validate specific known variables
  case "$var_name" in
    OPENAI_API_KEY)
      # Remove quotes for validation
      local clean_value="${value#\"}"
      clean_value="${clean_value%\"}"
      clean_value="${clean_value#\'}"
      clean_value="${clean_value%\'}"
      
      if [ ${#clean_value} -lt 20 ]; then
        eval "$warnings_ref+=(\"Line $line_num: OPENAI_API_KEY appears too short\")"
      fi
      
      if [[ "$clean_value" =~ ^sk-[a-zA-Z0-9]{20,}$ ]]; then
        : # Valid format
      elif [[ "$clean_value" =~ ^[a-zA-Z0-9]{20,}$ ]]; then
        eval "$warnings_ref+=(\"Line $line_num: OPENAI_API_KEY may be missing 'sk-' prefix\")"
      else
        eval "$warnings_ref+=(\"Line $line_num: OPENAI_API_KEY format appears unusual\")"
      fi
      ;;
    
    OPENAI_BASE_URL)
      local clean_value="${value#\"}"
      clean_value="${clean_value%\"}"
      clean_value="${clean_value#\'}"
      clean_value="${clean_value%\'}"
      
      if [[ ! "$clean_value" =~ ^https?:// ]]; then
        eval "$errors_ref+=(\"Line $line_num: OPENAI_BASE_URL must start with http:// or https://\")"
      fi
      
      if [[ "$clean_value" =~ /$ ]]; then
        eval "$warnings_ref+=(\"Line $line_num: OPENAI_BASE_URL has trailing slash (may cause issues)\")"
      fi
      ;;
    
    OPENAI_MODEL)
      local clean_value="${value#\"}"
      clean_value="${clean_value%\"}"
      clean_value="${clean_value#\'}"
      clean_value="${clean_value%\'}"
      
      local valid_models=(
        "gpt-4o" "gpt-4o-mini" "gpt-4" "gpt-4-turbo" 
        "gpt-3.5-turbo" "text-davinci-003" "dall-e"
      )
      
      local is_valid=0
      for model in "${valid_models[@]}"; do
        if [ "$clean_value" = "$model" ]; then
          is_valid=1
          break
        fi
      done
      
      if [ $is_valid -eq 0 ]; then
        eval "$warnings_ref+=(\"Line $line_num: OPENAI_MODEL '$clean_value' is not a standard model name\")"
      fi
      ;;
    
    BLUX_USER)
      local clean_value="${value#\"}"
      clean_value="${clean_value%\"}"
      clean_value="${clean_value#\'}"
      clean_value="${clean_value%\'}"
      
      if [[ ! "$clean_value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        eval "$warnings_ref+=(\"Line $line_num: BLUX_USER '$clean_value' should be lowercase, no special chars\")"
      fi
      
      if [ "$clean_value" = "root" ] || [ "$clean_value" = "admin" ]; then
        eval "$warnings_ref+=(\"Line $line_num: BLUX_USER '$clean_value' is a privileged name\")"
      fi
      ;;
    
    AXIOM_LOG_LEVEL)
      local clean_value="${value#\"}"
      clean_value="${clean_value%\"}"
      clean_value="${clean_value#\'}"
      clean_value="${clean_value%\'}"
      
      local valid_levels=("debug" "info" "warn" "error" "silent")
      local is_valid=0
      
      for level in "${valid_levels[@]}"; do
        if [ "$clean_value" = "$level" ]; then
          is_valid=1
          break
        fi
      done
      
      if [ $is_valid -eq 0 ]; then
        eval "$warnings_ref+=(\"Line $line_num: AXIOM_LOG_LEVEL '$clean_value' must be one of: ${valid_levels[*]}\")"
      fi
      ;;
  esac
  
  return 0
}

# Validate configuration file
axiom_validate_config() {
  local config_file="${1:-}"
  local strict="${2:-0}"
  
  if [ -z "$config_file" ]; then
    # Try to find config file
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/constants.sh" ]; then
      source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
      config_file="$(axiom_config_dir)/.env"
    else
      axiom_log_error "No config file specified and cannot locate AXIOM constants"
      return 1
    fi
  fi
  
  if [ ! -f "$config_file" ]; then
    axiom_log_error "Config file not found: $config_file"
    
    # Check for example file
    local example_file="${config_file}.example"
    if [ -f "$example_file" ]; then
      axiom_log_info "Example config exists: $example_file"
      axiom_log_info "Copy it: cp '$example_file' '$config_file'"
    fi
    
    return 1
  fi
  
  axiom_log_info "Validating config file: $config_file"
  
  local errors=()
  local warnings=()
  local line_num=0
  
  # Read file line by line
  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    
    _validate_config_line "$line" "$line_num" "errors[@]" "warnings[@]"
  done < "$config_file"
  
  # Check file permissions (warning only)
  local perms
  perms=$(stat -c "%a" "$config_file" 2>/dev/null || stat -f "%Lp" "$config_file" 2>/dev/null || echo "644")
  
  if [ "$perms" != "600" ] && [ "$perms" != "640" ]; then
    warnings+=("File permissions are $perms (recommend 600 for .env files)")
  fi
  
  # Report results
  if [ ${#errors[@]} -gt 0 ]; then
    axiom_log_error "Found ${#errors[@]} error(s):"
    for error in "${errors[@]}"; do
      axiom_log_info "  ✗ $error"
    done
  else
    axiom_log_info "✓ No syntax errors found"
  fi
  
  if [ ${#warnings[@]} -gt 0 ]; then
    axiom_log_warn "Found ${#warnings[@]} warning(s):"
    for warning in "${warnings[@]}"; do
      axiom_log_info "  ⚠ $warning"
    done
  else
    axiom_log_info "✓ No warnings"
  fi
  
  # Check for required variables
  _validate_required_variables "$config_file" "errors" "warnings"
  
  # Final validation status
  if [ ${#errors[@]} -gt 0 ]; then
    axiom_log_error "Config validation FAILED"
    if [ "$strict" = "1" ]; then
      return 1
    fi
  else
    axiom_log_info "✅ Config validation PASSED"
  fi
  
  return 0
}

# Validate required variables
_validate_required_variables() {
  local config_file="$1"
  local errors_ref="$2"
  local warnings_ref="$3"
  
  # Define required variables by context
  local -A required_vars
  required_vars["OPENAI_API_KEY"]="Required for AI features"
  required_vars["BLUX_USER"]="Required for user provisioning"
  
  # Optional but recommended
  local -A recommended_vars
  recommended_vars["OPENAI_MODEL"]="Recommended: gpt-4o-mini"
  recommended_vars["OPENAI_BASE_URL"]="Recommended: https://api.openai.com/v1"
  
  # Load the config file to check variables
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/env.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
    
    # Temporarily unset variables to check if they're in file
    local saved_vars=()
    for var in "${!required_vars[@]}" "${!recommended_vars[@]}"; do
      saved_vars["$var"]="${!var:-}"
      unset "$var" 2>/dev/null || true
    done
    
    # Load config file
    axiom_load_env_file "$config_file"
    
    # Check required variables
    for var in "${!required_vars[@]}"; do
      if [ -z "${!var:-}" ]; then
        eval "$errors_ref+=(\"Missing required variable: $var - ${required_vars[$var]}\")"
      fi
    done
    
    # Check recommended variables
    for var in "${!recommended_vars[@]}"; do
      if [ -z "${!var:-}" ]; then
        eval "$warnings_ref+=(\"Missing recommended variable: $var - ${recommended_vars[$var]}\")"
      fi
    done
    
    # Restore variables
    for var in "${!saved_vars[@]}"; do
      if [ -n "${saved_vars[$var]}" ]; then
        export "$var=${saved_vars[$var]}"
      fi
    done
  fi
}

# Validate directory structure
axiom_validate_structure() {
  local root_dir="${1:-}"
  
  if [ -z "$root_dir" ]; then
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/constants.sh" ]; then
      source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
      root_dir="$(axiom_repo_root)"
    else
      axiom_log_error "Cannot determine root directory"
      return 1
    fi
  fi
  
  axiom_log_info "Validating AXIOM structure at: $root_dir"
  
  local required_dirs=(
    "$root_dir/cockpit"
    "$root_dir/cockpit/bin"
    "$root_dir/cockpit/core"
    "$root_dir/cockpit/config"
    "$root_dir/cockpit/runs"
    "$root_dir/locker"
  )
  
  local required_files=(
    "$root_dir/axiom.sh"
    "$root_dir/launch.sh"
    "$root_dir/py_venv.sh"
    "$root_dir/README.md"
    "$root_dir/cockpit/core/constants.sh"
    "$root_dir/cockpit/core/log.sh"
    "$root_dir/cockpit/config/.env.example"
  )
  
  local missing_dirs=()
  local missing_files=()
  
  # Check directories
  for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      missing_dirs+=("$dir")
    fi
  done
  
  # Check files
  for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
      missing_files+=("$file")
    fi
  done
  
  # Report results
  if [ ${#missing_dirs[@]} -gt 0 ]; then
    axiom_log_error "Missing ${#missing_dirs[@]} directory(es):"
    for dir in "${missing_dirs[@]}"; do
      axiom_log_info "  ✗ $dir"
    done
  else
    axiom_log_info "✓ All directories present"
  fi
  
  if [ ${#missing_files[@]} -gt 0 ]; then
    axiom_log_error "Missing ${#missing_files[@]} file(s):"
    for file in "${missing_files[@]}"; do
      axiom_log_info "  ✗ $file"
    done
  else
    axiom_log_info "✓ All core files present"
  fi
  
  # Check directory permissions
  local dir_perms_issues=()
  for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
      if [ ! -w "$dir" ]; then
        dir_perms_issues+=("$dir (not writable)")
      fi
    fi
  done
  
  if [ ${#dir_perms_issues[@]} -gt 0 ]; then
    axiom_log_warn "Permission issues:"
    for issue in "${dir_perms_issues[@]}"; do
      axiom_log_info "  ⚠ $issue"
    done
  fi
  
  # Final status
  if [ ${#missing_dirs[@]} -gt 0 ] || [ ${#missing_files[@]} -gt 0 ]; then
    axiom_log_error "Structure validation FAILED"
    return 1
  else
    axiom_log_info "✅ Structure validation PASSED"
    return 0
  fi
}

# Validate script headers
axiom_validate_script_headers() {
  local script_dir="${1:-}"
  
  if [ -z "$script_dir" ]; then
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/constants.sh" ]; then
      source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
      script_dir="$(axiom_repo_root)"
    else
      axiom_log_error "Cannot determine script directory"
      return 1
    fi
  fi
  
  axiom_log_info "Validating script headers in: $script_dir"
  
  local scripts=()
  local issues=()
  
  # Find all shell scripts
  while IFS= read -r -d '' script; do
    scripts+=("$script")
  done < <(find "$script_dir" -name "*.sh" -type f -print0 2>/dev/null)
  
  # Check each script
  for script in "${scripts[@]}"; do
    local header_ok=1
    
    # Check shebang
    if ! head -1 "$script" | grep -q "^#!/usr/bin/env bash"; then
      issues+=("$script: Missing or incorrect shebang")
      header_ok=0
    fi
    
    # Check for set options
    if ! head -5 "$script" | grep -q "set -"; then
      issues+=("$script: Missing 'set' options for error handling")
      header_ok=0
    fi
    
    # Check for tier annotation (optional)
    if ! head -20 "$script" | grep -qi "tier.*[0-9]"; then
      issues+=("$script: Missing tier annotation (Tier 1/2/3)")
    fi
    
    # Check executable bit
    if [ ! -x "$script" ]; then
      issues+=("$script: Not executable (chmod +x)")
    fi
  done
  
  # Report results
  if [ ${#issues[@]} -gt 0 ]; then
    axiom_log_warn "Found ${#issues[@]} script header issue(s):"
    for issue in "${issues[@]}"; do
      axiom_log_info "  ⚠ $issue"
    done
    return 1
  else
    axiom_log_info "✅ All ${#scripts[@]} scripts have proper headers"
    return 0
  fi
}

# Generate validation report
axiom_validation_report() {
  local output_file="${1:-}"
  local timestamp
  timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
  
  axiom_log_info "Generating AXIOM validation report..."
  
  local report=""
  report+="# AXIOM Validation Report\n"
  report+="Generated: $timestamp\n"
  report+="System: $(uname -a)\n\n"
  
  # Create temp file for output capture
  local temp_file
  temp_file="$(mktemp 2>/dev/null || echo "/tmp/axiom_validate_$$.tmp")"
  
  # Run all validations
  report+="## 1. Structure Validation\n\n"
  if axiom_validate_structure > "$temp_file" 2>&1; then
    report+="✅ PASSED\n\n"
  else
    report+="❌ FAILED\n"
    report+="\`\`\`\n$(cat "$temp_file")\n\`\`\`\n\n"
  fi
  
  report+="## 2. Configuration Validation\n\n"
  if axiom_validate_config > "$temp_file" 2>&1; then
    report+="✅ PASSED\n\n"
  else
    report+="⚠ WARNINGS\n"
    report+="\`\`\`\n$(cat "$temp_file")\n\`\`\`\n\n"
  fi
  
  report+="## 3. Script Headers Validation\n\n"
  if axiom_validate_script_headers > "$temp_file" 2>&1; then
    report+="✅ PASSED\n\n"
  else
    report+="⚠ WARNINGS\n"
    report+="\`\`\`\n$(cat "$temp_file")\n\`\`\`\n\n"
  fi
  
  # Clean up
  rm -f "$temp_file"
  
  # Add recommendations
  report+="## 4. Recommendations\n\n"
  report+="1. **Backup Configuration**: Always backup .env before changes\n"
  report+="2. **Review Warnings**: Address warnings before production use\n"
  report+="3. **Regular Validation**: Run validation after major changes\n"
  report+="4. **Documentation**: Update README.md when adding new features\n\n"
  
  report+="## 5. Next Steps\n\n"
  report+="- Fix any errors reported above\n"
  report+="- Review warnings for potential improvements\n"
  report+="- Run \`axiom.sh --dry-run\` to test installation\n"
  report+="- Consult documentation for troubleshooting\n"
  
  # Output report
  if [ -n "$output_file" ]; then
    echo -e "$report" > "$output_file"
    axiom_log_info "Report saved to: $output_file"
  else
    echo -e "$report"
  fi
}

# Quick validation (for CI/CD)
axiom_quick_validate() {
  local exit_code=0
  
  axiom_log_info "Running quick validation..."
  
  # Structure check
  if ! axiom_validate_structure >/dev/null 2>&1; then
    axiom_log_error "Structure validation failed"
    exit_code=1
  fi
  
  # Config check (non-strict)
  if ! axiom_validate_config "" "0" >/dev/null 2>&1; then
    axiom_log_warn "Configuration has warnings"
    # Don't fail for warnings in quick mode
  fi
  
  if [ $exit_code -eq 0 ]; then
    axiom_log_info "✅ Quick validation passed"
  else
    axiom_log_error "❌ Quick validation failed"
  fi
  
  return $exit_code
}

# Main function for standalone usage
main() {
  local action="${1:-check}"
  
  case "$action" in
    check|validate)
      axiom_validate_structure
      axiom_validate_config
      ;;
    structure)
      axiom_validate_structure
      ;;
    config)
      axiom_validate_config "${2:-}"
      ;;
    scripts)
      axiom_validate_script_headers
      ;;
    report)
      axiom_validation_report "${2:-}"
      ;;
    quick)
      axiom_quick_validate
      ;;
    help|--help|-h)
      cat <<EOF
AXIOM Validation System

Usage: validate.sh [command] [arguments]

Commands:
  check|validate   Full validation (structure + config)
  structure        Validate directory structure only
  config [file]    Validate configuration file (default: .env)
  scripts          Validate script headers
  report [file]    Generate comprehensive validation report
  quick            Quick validation for CI/CD
  help             Show this help message

Examples:
  ./validate.sh check
  ./validate.sh config /path/to/.env
  ./validate.sh report validation.md
  ./validate.sh quick
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
