set -euo pipefail

STRICT=false
FIX_HINTS=false
PASS=0
FAIL=0
WARN=0

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)     STRICT=true; shift ;;
    --fix-hints)  FIX_HINTS=true; shift ;;
    --help)
      echo "Usage: $0 [--strict] [--fix-hints]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log_pass() { echo -e "  ${GREEN}✔${RESET}  $*"; ((PASS++)); }
log_fail() { echo -e "  ${RED}✘${RESET}  $*"; ((FAIL++)); }
log_warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; ((WARN++)); }
log_hint() { $FIX_HINTS && echo -e "     ${CYAN}→ Fix:${RESET} $*" || true; }

version_gte() {
  local installed="$1"
  local required="$2"
  printf '%s\n%s\n' "$required" "$installed" | sort -V | head -1 | grep -q "^${required}$"
}

extract_version() {
  echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "0.0.0"
}

check_tool() {
  local cmd="$1"
  local label="$2"
  local min_version="$3"
  local fix_cmd="${4:-}"

  if ! command -v "$cmd" &>/dev/null; then
    log_fail "$label — not found"
    log_hint "$fix_cmd"
    return
  fi

  local raw_version
  raw_version=$("$cmd" --version 2>&1 | head -1 || echo "")
  local version
  version=$(extract_version "$raw_version")

  if [[ -z "$version" || "$version" == "0.0.0" ]]; then
    log_warn "$label — found but could not parse version: $raw_version"
    return
  fi

  if version_gte "$version" "$min_version"; then
    log_pass "$label $version (min: $min_version)"
  else
    if $STRICT; then
      log_fail "$label $version — below minimum $min_version"
    else
      log_warn "$label $version — below recommended $min_version"
    fi
    log_hint "$fix_cmd"
  fi
}

check_python_version() {
  if ! command -v python3 &>/dev/null; then
    log_fail "Python 3 — not found"
    log_hint "brew install python3  OR  https://python.org/downloads"
    return
  fi
  local version
  version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>/dev/null || echo "0.0.0")
  if version_gte "$version" "3.9.0"; then
    log_pass "Python $version (min: 3.9.0)"
  else
    log_fail "Python $version — 3.9+ required"
    log_hint "pyenv install 3.11.0 && pyenv global 3.11.0"
  fi
}

check_env_file() {
  local envfile="${1:-.env}"
  local example="${2:-.env.example}"
  if [[ ! -f "$envfile" ]]; then
    if [[ -f "$example" ]]; then
      log_warn ".env file missing — $example exists, copy it: cp $example $envfile"
    else
      log_warn ".env file missing — create one from your team's template"
    fi
    return
  fi

  log_pass ".env file found"

  if [[ -f "$example" ]]; then
    local missing=()
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
      local key="${line%%=*}"
      if ! grep -q "^${key}=" "$envfile" 2>/dev/null; then
        missing+=("$key")
      fi
    done < "$example"

    if [[ "${#missing[@]}" -gt 0 ]]; then
      log_warn "Keys in $example but missing from $envfile: ${missing[*]}"
    else
      log_pass ".env matches all keys in $example"
    fi
  fi
}

check_ports() {
  local ports=("8080:App server" "5432:PostgreSQL" "6379:Redis")
  for entry in "${ports[@]}"; do
    local port="${entry%%:*}"
    local label="${entry##*:}"
    if lsof -i ":$port" &>/dev/null 2>&1; then
      log_warn "Port $port ($label) is already in use — may conflict with docker-compose"
    else
      log_pass "Port $port ($label) is free"
    fi
  done
}

check_azure_cli() {
  if command -v az &>/dev/null; then
    local version
    version=$(az --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    local logged_in
    logged_in=$(az account show &>/dev/null 2>&1 && echo "yes" || echo "no")
    if [[ "$logged_in" == "yes" ]]; then
      log_pass "Azure CLI $version — logged in"
    else
      log_warn "Azure CLI $version — not logged in (run: az login)"
    fi
  else
    log_warn "Azure CLI not found — needed for Azure deployments"
    log_hint "brew install azure-cli  OR  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
  fi
}

echo ""
echo -e "${BOLD}Environment Validator${RESET}"
$STRICT     && echo -e "  ${YELLOW}Mode: strict — version warnings treated as failures${RESET}"
$FIX_HINTS  && echo -e "  ${CYAN}Mode: fix hints enabled${RESET}"
echo ""

echo -e "${BOLD}Core tools${RESET}"
echo "$(printf '─%.0s' {1..45})"
check_python_version
check_tool git        "Git"       "2.30.0"   "brew install git"
check_tool docker     "Docker"    "24.0.0"   "https://docs.docker.com/get-docker"
check_tool terraform  "Terraform" "1.5.0"    "brew install terraform  OR  https://developer.hashicorp.com/terraform/install"
check_tool pip        "pip"       "22.0.0"   "python3 -m pip install --upgrade pip"

echo ""
echo -e "${BOLD}Optional but recommended${RESET}"
echo "$(printf '─%.0s' {1..45})"
check_azure_cli
check_tool jq         "jq"        "1.6"      "brew install jq"
check_tool make       "Make"      "3.81"     "xcode-select --install  (macOS)"
check_tool act        "act (local GitHub Actions)" "0.2.0" "brew install act"

echo ""
echo -e "${BOLD}Project config${RESET}"
echo "$(printf '─%.0s' {1..45})"
check_env_file ".env" ".env.example"

echo ""
echo -e "${BOLD}Port availability${RESET}"
echo "$(printf '─%.0s' {1..45})"
check_ports

echo ""
echo "$(printf '─%.0s' {1..45})"
echo -e "${BOLD}Summary${RESET}"
echo -e "  ${GREEN}Passed:${RESET}   $PASS"
echo -e "  ${YELLOW}Warnings:${RESET} $WARN"
echo -e "  ${RED}Failed:${RESET}   $FAIL"
echo ""

if $STRICT && [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}Validation failed — fix the errors above before continuing.${RESET}"
  echo ""
  exit 1
elif [[ "$FAIL" -gt 0 ]]; then
  echo -e "${YELLOW}Validation complete with failures — see above.${RESET}"
  echo ""
  exit 1
else
  echo -e "${GREEN}Environment looks good.${RESET}"
  echo ""
  exit 0
fi
