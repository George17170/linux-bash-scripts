set -euo pipefail

DRY_RUN=false
AGGRESSIVE=false
AUTO_YES=false

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --aggressive) AGGRESSIVE=true; shift ;;
    --yes)        AUTO_YES=true; shift ;;
    --help)
      echo "Usage: $0 [--dry-run] [--aggressive] [--yes]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if ! command -v docker &>/dev/null; then
  if $DRY_RUN; then
    echo -e "${YELLOW}Warning:${RESET} Docker not found — dry-run continuing anyway."
  else
    echo -e "${RED}Error:${RESET} Docker is not installed or not in PATH."
    exit 1
  fi
elif ! docker info &>/dev/null 2>&1; then
  if $DRY_RUN; then
    echo -e "${YELLOW}Warning:${RESET} Docker daemon not running — dry-run continuing anyway."
  else
    echo -e "${RED}Error:${RESET} Docker daemon is not running."
    exit 1
  fi
fi

disk_before() {
  docker system df 2>/dev/null | tail -1 | awk '{print $NF}' 2>/dev/null || echo "unknown"
}

echo ""
echo -e "${BOLD}Docker Cleanup${RESET}"
$DRY_RUN    && echo -e "  ${YELLOW}Mode: dry run — nothing will be deleted${RESET}"
$AGGRESSIVE && echo -e "  ${YELLOW}Mode: aggressive — all unused images will be removed${RESET}"
echo ""

echo -e "${BOLD}Current disk usage${RESET}"
docker system df 2>/dev/null || echo "  (docker not available)"
echo ""

STOPPED=$(docker ps -aq --filter status=exited --filter status=created 2>/dev/null | awk 'END{print NR}') || STOPPED=0
DANGLING=$(docker images -qf dangling=true 2>/dev/null | awk 'END{print NR}') || DANGLING=0
UNUSED_VOL=$(docker volume ls -qf dangling=true 2>/dev/null | awk 'END{print NR}') || UNUSED_VOL=0

echo -e "${BOLD}What will be removed${RESET}"
echo "$(printf '─%.0s' {1..40})"
echo -e "  Stopped containers:  $STOPPED"
echo -e "  Dangling images:     $DANGLING"
echo -e "  Unused volumes:      $UNUSED_VOL"
$AGGRESSIVE && echo -e "  ${YELLOW}+ all unused images (aggressive mode)${RESET}"
echo -e "  + build cache"
echo ""

if [[ "$STOPPED" -eq 0 && "$DANGLING" -eq 0 && "$UNUSED_VOL" -eq 0 ]]; then
  echo -e "${GREEN}Nothing to clean up. Docker environment is already tidy.${RESET}"
  echo ""
  exit 0
fi

if ! $AUTO_YES && ! $DRY_RUN; then
  read -rp "Proceed with cleanup? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

run_cmd() {
  if $DRY_RUN; then
    echo -e "  ${CYAN}[dry-run]${RESET} $*"
  else
    eval "$@" 2>/dev/null || true
  fi
}

echo -e "${BOLD}Cleaning up${RESET}"
echo "$(printf '─%.0s' {1..40})"

if [[ "$STOPPED" -gt 0 ]]; then
  echo -e "  ${CYAN}→${RESET} Removing stopped containers..."
  run_cmd "docker container prune -f"
fi

if [[ "$DANGLING" -gt 0 ]]; then
  echo -e "  ${CYAN}→${RESET} Removing dangling images..."
  run_cmd "docker image prune -f"
fi

if $AGGRESSIVE; then
  echo -e "  ${YELLOW}→${RESET} Removing all unused images..."
  run_cmd "docker image prune -af"
fi

if [[ "$UNUSED_VOL" -gt 0 ]]; then
  echo -e "  ${CYAN}→${RESET} Removing unused volumes..."
  run_cmd "docker volume prune -f"
fi

echo -e "  ${CYAN}→${RESET} Removing build cache..."
run_cmd "docker builder prune -f"

echo ""
if ! $DRY_RUN; then
  echo -e "${BOLD}Disk usage after cleanup${RESET}"
  docker system df 2>/dev/null || true
  echo ""
  echo -e "${GREEN}Cleanup complete.${RESET}"
else
  echo -e "${YELLOW}Dry run complete — nothing was deleted.${RESET}"
fi
echo ""
