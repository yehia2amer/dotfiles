#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# scripts/upgrade.sh — Upgrade all Nix packages + apply dotfiles
#
# Equivalent of `brew upgrade` for this Nix-managed dotfiles repo.
# Updates flake inputs (nixpkgs, home-manager), rebuilds the system,
# and applies chezmoi dotfiles.
#
# Usage:
#   nix-upgrade              (from shell alias)
#   ./scripts/upgrade.sh     (direct)
#   ./scripts/upgrade.sh -n  (dry-run: update lock, show diff, don't apply)
#   ./scripts/upgrade.sh -v  (verbose: show full nix build output)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$DOTFILES_DIR/.logs"
LOG_FILE="$LOG_DIR/upgrade-$(date +%Y%m%d-%H%M%S).log"
MAX_LOGS=10

# ── Colors & Formatting ──────────────────────────────────────────────────────
readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false

while getopts "nvh" opt; do
  case "$opt" in
    n) DRY_RUN=true ;;
    v) VERBOSE=true ;;
    h)
      echo "Usage: $(basename "$0") [-n] [-v] [-h]"
      echo "  -n  Dry-run: update flake.lock, show diff, don't rebuild"
      echo "  -v  Verbose: show full nix build output"
      echo "  -h  Show this help"
      exit 0
      ;;
    *) exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"; }
step() { echo -e "\n${BOLD}═══ $* ═══${RESET}"; }
ok() { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
fail() { echo -e "${RED}✗${RESET} $*" >&2; }

die() {
  fail "$1"
  echo -e "${DIM}Full log: $LOG_FILE${RESET}" >&2
  exit 1
}

elapsed() {
  local seconds=$1
  if (( seconds >= 60 )); then
    echo "$((seconds / 60))m $((seconds % 60))s"
  else
    echo "${seconds}s"
  fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
cd "$DOTFILES_DIR"

# Rotate old logs (keep last N)
find "$LOG_DIR" -name "upgrade-*.log" -type f | sort -r | tail -n +$((MAX_LOGS + 1)) | xargs rm -f 2>/dev/null || true

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Detect Platform & Host ────────────────────────────────────────────────────
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin)
      PLATFORM="darwin"
      HOST="MacBookProM3"
      REBUILD_CMD="darwin-rebuild switch --flake .#$HOST"
      ;;
    Linux)
      PLATFORM="linux"
      HOST="${HOSTNAME:-$(hostname)}"
      REBUILD_CMD="sudo nixos-rebuild switch --flake .#$HOST"
      ;;
    *)
      die "Unsupported OS: $os"
      ;;
  esac

  log "Platform: ${BOLD}$PLATFORM${RESET} ($arch) → host: ${BOLD}$HOST${RESET}"
}

# ── Step 1: Update Flake Inputs ───────────────────────────────────────────────
update_flake() {
  step "Updating flake inputs (nixpkgs, home-manager, ...)"
  local start=$SECONDS

  if $VERBOSE; then
    nix flake update 2>&1
  else
    nix flake update 2>&1 | grep -E "^(Updated|•|warning)" || true
  fi

  ok "Flake inputs updated ($(elapsed $((SECONDS - start))))"

  # Show what changed in the lock file
  if git diff --quiet flake.lock 2>/dev/null; then
    warn "No changes — flake.lock already up to date"
    if ! $DRY_RUN; then
      echo -e "${DIM}Nothing to rebuild. Exiting.${RESET}"
      exit 0
    fi
  else
    log "Lock file diff:"
    echo -e "${DIM}"
    git diff --stat flake.lock 2>/dev/null || true
    echo -e "${RESET}"
  fi
}

# ── Step 2: Rebuild System ────────────────────────────────────────────────────
rebuild_system() {
  if $DRY_RUN; then
    step "Dry-run: skipping rebuild"
    warn "Would run: $REBUILD_CMD"
    return
  fi

  step "Rebuilding system ($HOST)"
  local start=$SECONDS

  if $VERBOSE; then
    eval "$REBUILD_CMD" 2>&1
  else
    eval "$REBUILD_CMD" 2>&1 | tail -20
  fi

  ok "System rebuilt ($(elapsed $((SECONDS - start))))"
}

# ── Step 3: Apply Chezmoi Dotfiles ────────────────────────────────────────────
apply_chezmoi() {
  if $DRY_RUN; then
    step "Dry-run: chezmoi diff"
    chezmoi diff --source "$DOTFILES_DIR/chezmoi" 2>/dev/null | head -40 || true
    return
  fi

  step "Applying dotfiles (chezmoi)"
  local start=$SECONDS

  chezmoi apply --source "$DOTFILES_DIR/chezmoi"

  ok "Dotfiles applied ($(elapsed $((SECONDS - start))))"
}

# ── Step 4: Commit Lock File ──────────────────────────────────────────────────
commit_lock() {
  if $DRY_RUN; then
    warn "Dry-run: skipping commit"
    return
  fi

  if ! git diff --quiet flake.lock 2>/dev/null; then
    step "Committing flake.lock"
    git add flake.lock
    git commit -m "chore(nix): upgrade flake inputs $(date +%Y-%m-%d)" --no-verify
    ok "Lock file committed"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  local total_start=$SECONDS

  echo -e "${BOLD}${CYAN}"
  echo "┌─────────────────────────────────────────┐"
  echo "│         nix-upgrade                      │"
  echo "│   Update all packages & rebuild system   │"
  echo "└─────────────────────────────────────────┘"
  echo -e "${RESET}"

  $DRY_RUN && warn "DRY-RUN MODE — no changes will be applied"

  detect_platform
  update_flake
  rebuild_system
  apply_chezmoi
  commit_lock

  echo ""
  echo -e "${GREEN}${BOLD}✅ Upgrade complete!${RESET} (total: $(elapsed $((SECONDS - total_start))))"
  echo -e "${DIM}Log: $LOG_FILE${RESET}"
}

main "$@"
