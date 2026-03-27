#!/usr/bin/env bash
# pipeline_health_check.sh
# Checks CI/CD pipeline prerequisites and environment health before a run.
# Useful for catching config drift, missing secrets, or stale dependencies
# before they cause a pipeline failure mid-run.
#
# Usage:
#   ./pipeline_health_check.sh [--env <environment>] [--report]
#   ./pipeline_health_check.sh --env staging --report
#
# Exit codes:
#   0 - all checks passed
#   1 - one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
REPORT_FILE="${LOG_DIR}/health_$(date +%Y%m%d_%H%M%S).log"
ENV="${ENV:-local}"
GENERATE_REPORT=false
PASS=0
FAIL=0
WARN=0

BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

usage() {
  echo "Usage: $0 [--env <local|staging|prod>] [--report]"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)   ENV="$2"; shift 2 ;;
    --report) GENERATE_REPORT=true; shift ;;
    --help)  usage ;;
    *)       echo "Unknown option: $1"; usage ;;
  esac
done

mkdir -p "$LOG_DIR"

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  case "$level" in
    PASS) echo -e "  ${GREEN}✔${RESET}  $msg"; ((PASS++)) ;;
    FAIL) echo -e "  ${RED}✘${RESET}  $msg"; ((FAIL++)) ;;
    WARN) echo -e "  ${YELLOW}⚠${RESET}  $msg"; ((WARN++)) ;;
    INFO) echo -e "  ${CYAN}→${RESET}  $msg" ;;
  esac
  if $GENERATE_REPORT; then
    echo "[$ts] [$level] $msg" >> "$REPORT_FILE"
  fi
}

section() {
  echo ""
  echo -e "${BOLD}$1${RESET}"
  echo "$(printf '─%.0s' {1..50})"
}

check_command() {
  local cmd="$1"
  local label="${2:-$cmd}"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>&1 | head -1 || echo "unknown")
    log PASS "$label found — $version"
  else
    log FAIL "$label not found — install it before running the pipeline"
  fi
}

check_env_var() {
  local var="$1"
  local label="${2:-$var}"
  if [[ -n "${!var:-}" ]]; then
    log PASS "$label is set"
  else
    log FAIL "$label is not set — pipeline will likely fail"
  fi
}

check_env_var_optional() {
  local var="$1"
  local label="${2:-$var}"
  if [[ -n "${!var:-}" ]]; then
    log PASS "$label is set"
  else
    log WARN "$label is not set — optional but recommended"
  fi
}

check_file() {
  local file="$1"
  local label="${2:-$1}"
  if [[ -f "$file" ]]; then
    log PASS "$label exists"
  else
    log FAIL "$label not found — expected at $file"
  fi
}

check_docker_running() {
  if docker info &>/dev/null 2>&1; then
    local version
    version=$(docker --version 2>&1)
    log PASS "Docker daemon is running — $version"
  else
    log FAIL "Docker daemon is not running — start Docker Desktop or dockerd"
  fi
}

check_disk_space() {
  local threshold=10
  local available
  available=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
  if [[ "$available" -ge "$threshold" ]]; then
    log PASS "Disk space OK — ${available}GB free"
  else
    log WARN "Low disk space — only ${available}GB free (threshold: ${threshold}GB)"
  fi
}

check_git_state() {
  if ! git rev-parse --git-dir &>/dev/null 2>&1; then
    log WARN "Not inside a git repository"
    return
  fi
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  log INFO "Current branch: $branch"

  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    log WARN "Uncommitted changes detected — pipeline will use current working tree"
  else
    log PASS "Working tree is clean"
  fi

  local behind
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
  if [[ "$behind" -gt 0 ]]; then
    log WARN "Branch is $behind commit(s) behind remote"
  fi
}

check_python_deps() {
  if [[ -f "requirements.txt" ]]; then
    log PASS "requirements.txt found"
    if command -v pip &>/dev/null; then
      local outdated
      outdated=$(pip list --outdated 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$outdated" -gt 1 ]]; then
        log WARN "$((outdated - 1)) outdated Python package(s) — run pip install --upgrade"
      else
        log PASS "Python dependencies are up to date"
      fi
    fi
  else
    log WARN "requirements.txt not found — skipping dependency check"
  fi
}

check_dockerfile() {
  if [[ -f "Dockerfile" ]]; then
    log PASS "Dockerfile found"
    if grep -q "HEALTHCHECK" Dockerfile 2>/dev/null; then
      log PASS "Dockerfile includes HEALTHCHECK"
    else
      log WARN "Dockerfile missing HEALTHCHECK — recommended for production images"
    fi
    if grep -q "USER " Dockerfile 2>/dev/null; then
      log PASS "Dockerfile sets a non-root USER"
    else
      log WARN "Dockerfile does not set USER — container will run as root"
    fi
  else
    log WARN "Dockerfile not found in current directory"
  fi
}

check_github_actions() {
  if [[ -d ".github/workflows" ]]; then
    local count
    count=$(find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    log PASS ".github/workflows found — $count workflow file(s)"
  else
    log WARN ".github/workflows not found — no CI pipelines configured"
  fi
}

echo ""
echo -e "${BOLD}Pipeline Health Check${RESET}"
echo -e "${CYAN}Environment: ${ENV}${RESET}"
echo -e "${CYAN}$(date)${RESET}"

section "Required tools"
check_command git "Git"
check_command python3 "Python 3"
check_command pip "pip"
check_command docker "Docker"
check_command terraform "Terraform"

section "Docker"
check_docker_running

section "Environment variables"
check_env_var_optional "DOCKER_USERNAME" "DockerHub username"
check_env_var_optional "DOCKER_TOKEN" "DockerHub token"
check_env_var_optional "AZURE_SUBSCRIPTION_ID" "Azure subscription ID"
check_env_var_optional "AZURE_CLIENT_ID" "Azure client ID"
check_env_var_optional "SLACK_WEBHOOK_URL" "Slack webhook URL"

if [[ "$ENV" == "staging" || "$ENV" == "prod" ]]; then
  section "Environment: $ENV — additional checks"
  check_env_var "AZURE_TENANT_ID" "Azure tenant ID"
  check_env_var "AZURE_CLIENT_SECRET" "Azure client secret"
fi

section "Project structure"
check_git_state
check_python_deps
check_dockerfile
check_github_actions

section "System"
check_disk_space

echo ""
echo "$(printf '─%.0s' {1..50})"
echo -e "${BOLD}Summary${RESET}"
echo -e "  ${GREEN}Passed:${RESET}  $PASS"
echo -e "  ${YELLOW}Warnings:${RESET} $WARN"
echo -e "  ${RED}Failed:${RESET}  $FAIL"

if $GENERATE_REPORT; then
  echo ""
  echo -e "  ${CYAN}Report saved:${RESET} $REPORT_FILE"
fi

echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}Health check failed — fix the issues above before running the pipeline.${RESET}"
  echo ""
  exit 1
else
  echo -e "${GREEN}All required checks passed.${RESET}"
  echo ""
  exit 0
fi
