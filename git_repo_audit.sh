set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
REPO_PATH=""
STALE_DAYS=60
GENERATE_REPORT=false
ISSUES=0

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --report)     GENERATE_REPORT=true; shift ;;
    --help)
      echo "Usage: $0 [<repo_path>] [--stale-days <n>] [--report]"
      exit 0 ;;
    -*)  echo "Unknown option: $1"; exit 1 ;;
    *)   REPO_PATH="$1"; shift ;;
  esac
done

REPO_PATH="${REPO_PATH:-.}"

log_ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
log_issue() { echo -e "  ${RED}✘${RESET}  $*"; ((ISSUES++)); }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_info()  { echo -e "  ${CYAN}→${RESET}  $*"; }

if [[ ! -d "$REPO_PATH/.git" ]]; then
  echo -e "${RED}Error:${RESET} $REPO_PATH is not a git repository."
  exit 1
fi

cd "$REPO_PATH"

echo ""
echo -e "${BOLD}Git Repo Audit${RESET}"
echo -e "${CYAN}Repo:${RESET} $(pwd)"
echo -e "${CYAN}Date:${RESET} $(date)"

echo ""
echo -e "${BOLD}Repository info${RESET}"
echo "$(printf '─%.0s' {1..45})"
log_info "Default branch: $(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo 'unknown')"
log_info "Total commits:  $(git rev-list --count HEAD 2>/dev/null || echo 'unknown')"
log_info "First commit:   $(git log --oneline --reverse | head -1 | cut -c1-60 || echo 'unknown')"
log_info "Latest commit:  $(git log -1 --format='%h %s (%ar)' 2>/dev/null || echo 'unknown')"
log_info "Contributors:   $(git shortlog -s HEAD 2>/dev/null | wc -l | tr -d ' ')"

echo ""
echo -e "${BOLD}Branch health${RESET}"
echo "$(printf '─%.0s' {1..45})"

TOTAL_BRANCHES=$(git branch -r 2>/dev/null | grep -v HEAD | wc -l | tr -d ' ')
log_info "Remote branches: $TOTAL_BRANCHES"

STALE_CUTOFF=$(date -d "-${STALE_DAYS} days" +%Y-%m-%d 2>/dev/null || date -v -"${STALE_DAYS}"d +%Y-%m-%d 2>/dev/null || echo "")
STALE_BRANCHES=()
if [[ -n "$STALE_CUTOFF" ]]; then
  while IFS= read -r branch; do
    branch=$(echo "$branch" | tr -d ' ')
    [[ "$branch" == *HEAD* ]] && continue
    last_commit=$(git log -1 --format="%ai" "$branch" 2>/dev/null | cut -d' ' -f1 || echo "")
    [[ -z "$last_commit" ]] && continue
    if [[ "$last_commit" < "$STALE_CUTOFF" ]]; then
      STALE_BRANCHES+=("$branch (last commit: $last_commit)")
    fi
  done < <(git branch -r 2>/dev/null | grep -v HEAD || true)
fi

if [[ "${#STALE_BRANCHES[@]}" -gt 0 ]]; then
  log_warn "${#STALE_BRANCHES[@]} branch(es) stale (no commits in ${STALE_DAYS} days):"
  for b in "${STALE_BRANCHES[@]}"; do
    echo -e "     ${YELLOW}·${RESET} $b"
  done
else
  log_ok "No stale branches (threshold: ${STALE_DAYS} days)"
fi

UNMERGED=$(git branch -r --no-merged HEAD 2>/dev/null | grep -v HEAD | wc -l | tr -d ' ')
if [[ "$UNMERGED" -gt 0 ]]; then
  log_warn "$UNMERGED unmerged remote branch(es)"
else
  log_ok "All remote branches are merged or up to date"
fi

echo ""
echo -e "${BOLD}.gitignore check${RESET}"
echo "$(printf '─%.0s' {1..45})"

if [[ ! -f ".gitignore" ]]; then
  log_issue ".gitignore is missing"
else
  log_ok ".gitignore exists"
  MISSING_ENTRIES=()
  check_gitignore_entry() {
    grep -qE "$1" .gitignore 2>/dev/null || MISSING_ENTRIES+=("$2")
  }
  check_gitignore_entry "\.env"            ".env files"
  check_gitignore_entry "__pycache__|\.pyc" "Python cache (__pycache__, *.pyc)"
  check_gitignore_entry "\.terraform"      ".terraform directory"
  check_gitignore_entry "\.DS_Store"       ".DS_Store (macOS)"
  check_gitignore_entry "node_modules"     "node_modules"

  if [[ "${#MISSING_ENTRIES[@]}" -gt 0 ]]; then
    for entry in "${MISSING_ENTRIES[@]}"; do
      log_warn ".gitignore may be missing: $entry"
    done
  else
    log_ok "Common entries present in .gitignore"
  fi
fi

echo ""
echo -e "${BOLD}Sensitive file check${RESET}"
echo "$(printf '─%.0s' {1..45})"

SENSITIVE_PATTERNS=("*.pem" "*.key" "*.p12" "*.pfx" ".env" "secrets.yml" "credentials.json")
FOUND_SENSITIVE=false
for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  if git ls-files "$pattern" 2>/dev/null | grep -q .; then
    log_issue "Potentially sensitive file tracked by git: $pattern"
    FOUND_SENSITIVE=true
  fi
done
$FOUND_SENSITIVE || log_ok "No sensitive file patterns detected in tracked files"

echo ""
echo -e "${BOLD}Large file check${RESET} (files > 1MB in history)"
echo "$(printf '─%.0s' {1..45})"

LARGE_FILES=$(git rev-list --objects --all 2>/dev/null \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' 2>/dev/null \
  | awk '/^blob/ && $3 > 1048576 { printf "  %.1f MB  %s\n", $3/1048576, $4 }' \
  | sort -rn | head -5 || true)

if [[ -n "$LARGE_FILES" ]]; then
  log_warn "Large files found in git history (consider git-lfs):"
  echo "$LARGE_FILES" | while IFS= read -r line; do
    echo -e "     ${YELLOW}·${RESET} $line"
  done
else
  log_ok "No files over 1MB found in git history"
fi

echo ""
echo -e "${BOLD}Tags and releases${RESET}"
echo "$(printf '─%.0s' {1..45})"

TAG_COUNT=$(git tag 2>/dev/null | wc -l | tr -d ' ')
if [[ "$TAG_COUNT" -gt 0 ]]; then
  LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
  log_ok "$TAG_COUNT tag(s) found — latest: $LATEST_TAG"
else
  log_warn "No release tags found — consider semantic versioning (v1.0.0)"
fi

echo ""
echo "$(printf '─%.0s' {1..45})"
echo -e "${BOLD}Summary${RESET}"
if [[ "$ISSUES" -gt 0 ]]; then
  echo -e "  ${RED}$ISSUES issue(s) found — review above${RESET}"
else
  echo -e "  ${GREEN}No critical issues found${RESET}"
fi

if $GENERATE_REPORT; then
  mkdir -p "$LOG_DIR"
  REPORT="${LOG_DIR}/git_audit_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "Git Repo Audit — $(pwd)"
    echo "Date: $(date)"
    echo "Issues: $ISSUES"
    echo "Stale branches: ${#STALE_BRANCHES[@]}"
    echo "Tags: $TAG_COUNT"
  } > "$REPORT"
  echo -e "  ${CYAN}Report saved: $REPORT${RESET}"
fi
echo ""

[[ "$ISSUES" -gt 0 ]] && exit 1 || exit 0
