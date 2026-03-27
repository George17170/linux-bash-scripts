set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"

LOGFILE=""
TAIL_LINES=0
ERRORS_ONLY=false
JSON_OUTPUT=false

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

usage() {
  echo "Usage: $0 <logfile> [--tail <n>] [--errors-only] [--json]"
  echo ""
  echo "Options:"
  echo "  --tail <n>       Only analyze the last n lines"
  echo "  --errors-only    Only show errors and failures"
  echo "  --json           Output summary as JSON"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)        TAIL_LINES="$2"; shift 2 ;;
    --errors-only) ERRORS_ONLY=true; shift ;;
    --json)        JSON_OUTPUT=true; shift ;;
    --help)        usage ;;
    -*)            echo "Unknown option: $1"; usage ;;
    *)             LOGFILE="$1"; shift ;;
  esac
done

if [[ -z "$LOGFILE" ]]; then
  echo -e "${RED}Error:${RESET} No log file specified."
  usage
fi

if [[ ! -f "$LOGFILE" ]]; then
  echo -e "${RED}Error:${RESET} File not found: $LOGFILE"
  exit 1
fi

if [[ "$TAIL_LINES" -gt 0 ]]; then
  CONTENT=$(tail -n "$TAIL_LINES" "$LOGFILE")
else
  CONTENT=$(cat "$LOGFILE")
fi

TOTAL_LINES=$(echo "$CONTENT" | wc -l | tr -d ' ')
FILE_SIZE=$(du -h "$LOGFILE" | cut -f1)

ERROR_COUNT=$(echo "$CONTENT" | grep -ciE "(error|exception|traceback|fatal|critical)" || true)
WARNING_COUNT=$(echo "$CONTENT" | grep -ciE "(warning|warn|deprecated)" || true)
FAILURE_COUNT=$(echo "$CONTENT" | grep -ciE "(failed|failure|FAILED|FAIL)" || true)
SUCCESS_COUNT=$(echo "$CONTENT" | grep -ciE "(passed|success|succeeded|ok\b)" || true)

TESTS_RUN=$(echo "$CONTENT" | grep -oiE "[0-9]+ (test|tests) (ran|run|passed|failed)" | head -1 || true)
PYTEST_SUMMARY=$(echo "$CONTENT" | grep -E "^(PASSED|FAILED|ERROR|=+ .+ =+)" | tail -5 || true)

DOCKER_STEPS=$(echo "$CONTENT" | grep -c "^Step [0-9]" 2>/dev/null || true)
DOCKER_ERRORS=$(echo "$CONTENT" | grep -c "^ERROR" 2>/dev/null || true)

START_TIME=$(echo "$CONTENT" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1 || true)
END_TIME=$(echo "$CONTENT"   | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}" | tail -1 || true)

if $JSON_OUTPUT; then
  cat <<EOF
{
  "file": "$LOGFILE",
  "file_size": "$FILE_SIZE",
  "total_lines": $TOTAL_LINES,
  "errors": $ERROR_COUNT,
  "warnings": $WARNING_COUNT,
  "failures": $FAILURE_COUNT,
  "successes": $SUCCESS_COUNT,
  "start_time": "$START_TIME",
  "end_time": "$END_TIME",
  "docker_build_steps": $DOCKER_STEPS
}
EOF
  exit 0
fi

echo ""
echo -e "${BOLD}Log Analyzer${RESET}"
echo -e "${CYAN}File:${RESET}  $LOGFILE"
echo -e "${CYAN}Size:${RESET}  $FILE_SIZE  |  ${CYAN}Lines:${RESET} $TOTAL_LINES"
[[ -n "$START_TIME" ]] && echo -e "${CYAN}Start:${RESET} $START_TIME"
[[ -n "$END_TIME"   ]] && echo -e "${CYAN}End:${RESET}   $END_TIME"

echo ""
echo -e "${BOLD}Counts${RESET}"
echo "$(printf '─%.0s' {1..40})"

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  echo -e "  ${RED}Errors / exceptions:${RESET}  $ERROR_COUNT"
else
  echo -e "  ${GREEN}Errors / exceptions:${RESET}  $ERROR_COUNT"
fi

if [[ "$FAILURE_COUNT" -gt 0 ]]; then
  echo -e "  ${RED}Failures:${RESET}             $FAILURE_COUNT"
else
  echo -e "  ${GREEN}Failures:${RESET}             $FAILURE_COUNT"
fi

if [[ "$WARNING_COUNT" -gt 0 ]]; then
  echo -e "  ${YELLOW}Warnings:${RESET}             $WARNING_COUNT"
else
  echo -e "  Warnings:             $WARNING_COUNT"
fi

echo -e "  ${GREEN}Successes:${RESET}            $SUCCESS_COUNT"

if [[ "$DOCKER_STEPS" -gt 0 ]]; then
  echo ""
  echo -e "${BOLD}Docker build${RESET}"
  echo "$(printf '─%.0s' {1..40})"
  echo -e "  Build steps detected: $DOCKER_STEPS"
  [[ "$DOCKER_ERRORS" -gt 0 ]] && echo -e "  ${RED}Build errors:${RESET} $DOCKER_ERRORS"
fi

if [[ -n "$PYTEST_SUMMARY" ]]; then
  echo ""
  echo -e "${BOLD}Test results${RESET}"
  echo "$(printf '─%.0s' {1..40})"
  echo "$PYTEST_SUMMARY" | while IFS= read -r line; do
    if echo "$line" | grep -qiE "failed|error"; then
      echo -e "  ${RED}$line${RESET}"
    elif echo "$line" | grep -qiE "passed|ok"; then
      echo -e "  ${GREEN}$line${RESET}"
    else
      echo "  $line"
    fi
  done
fi

if ! $ERRORS_ONLY || [[ "$ERROR_COUNT" -gt 0 || "$FAILURE_COUNT" -gt 0 ]]; then
  if [[ "$ERROR_COUNT" -gt 0 || "$FAILURE_COUNT" -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}Error lines${RESET} (first 10)"
    echo "$(printf '─%.0s' {1..40})"
    echo "$CONTENT" \
      | grep -iE "(error|exception|traceback|fatal|failed)" \
      | grep -viE "(no error|0 errors|error handling)" \
      | head -10 \
      | while IFS= read -r line; do
          echo -e "  ${RED}▸${RESET} $line"
        done
  fi
fi

mkdir -p "$LOG_DIR"
SUMMARY_FILE="${LOG_DIR}/analyzed_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "Log Analysis Summary"
  echo "File: $LOGFILE | Size: $FILE_SIZE | Lines: $TOTAL_LINES"
  echo "Errors: $ERROR_COUNT | Warnings: $WARNING_COUNT | Failures: $FAILURE_COUNT | Successes: $SUCCESS_COUNT"
  echo "Start: $START_TIME | End: $END_TIME"
} > "$SUMMARY_FILE"

echo ""
echo "$(printf '─%.0s' {1..40})"
echo -e "  Summary saved: ${CYAN}$SUMMARY_FILE${RESET}"
echo ""

if [[ "$ERROR_COUNT" -gt 0 || "$FAILURE_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0