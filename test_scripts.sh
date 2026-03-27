#!/usr/bin/env bash
# tests/test_scripts.sh
# Basic smoke tests for all scripts in the scripts/ directory.
# Tests: file existence, execute permissions, --help flag, exit codes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
PASS=0
FAIL=0

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

pass() { echo -e "  ${GREEN}✔${RESET}  $*"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✘${RESET}  $*"; FAIL=$((FAIL+1)); }

echo ""
echo -e "${BOLD}Script Tests${RESET}"
echo ""

SCRIPTS=(
  "pipeline_health_check.sh"
  "log_analyzer.sh"
  "docker_cleanup.sh"
  "env_validator.sh"
  "git_repo_audit.sh"
)

echo -e "${BOLD}File existence and permissions${RESET}"
echo "$(printf '─%.0s' {1..40})"
for script in "${SCRIPTS[@]}"; do
  path="${SCRIPTS_DIR}/${script}"
  if [[ -f "$path" ]]; then
    pass "$script — exists"
  else
    fail "$script — not found at $path"
    continue
  fi
  if [[ -x "$path" ]]; then
    pass "$script — executable"
  else
    fail "$script — not executable (run: chmod +x $path)"
  fi
done

echo ""
echo -e "${BOLD}--help flag (exit 0)${RESET}"
echo "$(printf '─%.0s' {1..40})"
for script in "${SCRIPTS[@]}"; do
  path="${SCRIPTS_DIR}/${script}"
  [[ -f "$path" ]] || continue
  if bash "$path" --help &>/dev/null; then
    pass "$script --help exits cleanly"
  else
    fail "$script --help returned non-zero"
  fi
done

echo ""
echo -e "${BOLD}log_analyzer.sh — missing file error handling${RESET}"
echo "$(printf '─%.0s' {1..40})"
if bash "${SCRIPTS_DIR}/log_analyzer.sh" "/nonexistent/file.log" &>/dev/null; then
  fail "log_analyzer.sh — should return non-zero for missing file"
else
  pass "log_analyzer.sh — correctly returns error for missing file"
fi

echo ""
echo -e "${BOLD}log_analyzer.sh — parses sample log${RESET}"
echo "$(printf '─%.0s' {1..40})"
SAMPLE_LOG=$(mktemp)
cat > "$SAMPLE_LOG" <<'EOF'
2024-01-15 10:00:01 INFO Starting build
2024-01-15 10:00:02 INFO Running tests
2024-01-15 10:00:03 ERROR Test failed: test_auth_flow
2024-01-15 10:00:04 WARNING Deprecated function used
2024-01-15 10:00:05 INFO 3 tests ran, 1 failed
EOF
if bash "${SCRIPTS_DIR}/log_analyzer.sh" "$SAMPLE_LOG" &>/dev/null; then
  fail "log_analyzer.sh — should return non-zero when errors found"
else
  pass "log_analyzer.sh — correctly returns non-zero for log with errors"
fi

JSON_OUT=$(bash "${SCRIPTS_DIR}/log_analyzer.sh" "$SAMPLE_LOG" --json 2>/dev/null || true)
if echo "$JSON_OUT" | grep -q '"errors"'; then
  pass "log_analyzer.sh --json produces JSON with 'errors' key"
else
  fail "log_analyzer.sh --json output missing 'errors' key"
fi
rm -f "$SAMPLE_LOG"

echo ""
echo -e "${BOLD}docker_cleanup.sh — dry-run exits 0${RESET}"
echo "$(printf '─%.0s' {1..40})"
if bash "${SCRIPTS_DIR}/docker_cleanup.sh" --dry-run --yes &>/dev/null; then
  pass "docker_cleanup.sh --dry-run exits cleanly"
else
  fail "docker_cleanup.sh --dry-run returned non-zero"
fi

echo ""
echo -e "${BOLD}git_repo_audit.sh — rejects non-git directory${RESET}"
echo "$(printf '─%.0s' {1..40})"
TMPDIR_TEST=$(mktemp -d)
if bash "${SCRIPTS_DIR}/git_repo_audit.sh" "$TMPDIR_TEST" &>/dev/null; then
  fail "git_repo_audit.sh — should fail on non-git directory"
else
  pass "git_repo_audit.sh — correctly rejects non-git directory"
fi
rm -rf "$TMPDIR_TEST"

echo ""
echo "$(printf '─%.0s' {1..40})"
echo -e "${BOLD}Results${RESET}"
echo -e "  ${GREEN}Passed:${RESET} $PASS"
echo -e "  ${RED}Failed:${RESET} $FAIL"
echo ""

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
