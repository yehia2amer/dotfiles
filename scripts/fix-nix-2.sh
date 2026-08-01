#!/usr/bin/env bash
#
# fix-nix-2.sh  —  STEP 2 of 2  (run this AFTER the reboot from step 1)
#
# Just run:   sudo ~/.dotfiles/scripts/fix-nix-2.sh
#
# It confirms /nix is mounted, then re-applies your nix-darwin flake to bring
# brew/nix/zsh fully back. It automatically clears any stale ".bak" files that
# would otherwise stop Home Manager. No arguments. Safe to re-run.
#
set -euo pipefail

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run me with sudo:  sudo $0"

VOL="Nix Store"
FLAKE_ATTR="MacBookProM3"
# The dotfiles repo = parent of this script's directory.
DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo "  ┌────────────────────────────────────────────┐"
echo "  │  Nix recovery — STEP 2 of 2 (finish)       │"
echo "  └────────────────────────────────────────────┘"
echo

# ── 1. Make sure /nix is mounted ──────────────────────────────────────────────
if ! /sbin/mount | grep -q " on /nix "; then
  say "/nix not mounted yet — mounting …"
  DEV="$(/usr/sbin/diskutil info "$VOL" 2>/dev/null | awk -F': *' '/Device Node/ {print $2; exit}')"
  [ -n "${DEV:-}" ] || die "Can't find the '$VOL' volume. Run step 1 first: sudo $SELFDIR/fix-nix-1.sh"
  [ -d /nix ] || /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t >/dev/null 2>&1 || true
  /sbin/mount -o nobrowse -t apfs "$DEV" /nix 2>/dev/null \
    || die "Mount failed. Run step 1 and let it reboot first: sudo $SELFDIR/fix-nix-1.sh"
fi
[ -n "$(ls /nix/store 2>/dev/null | head -1)" ] || die "/nix/store is empty — unexpected."
ok "/nix is mounted and populated"

# ── 2. Find darwin-rebuild and the flake ──────────────────────────────────────
DR=/nix/var/nix/profiles/system/sw/bin/darwin-rebuild
[ -x "$DR" ] || DR="$(command -v darwin-rebuild || true)"
[ -n "$DR" ] && [ -x "$DR" ] || die "darwin-rebuild not found. Reboot and re-run."
[ -e "$DOTFILES/flake.nix" ] || die "No flake.nix in $DOTFILES"
ok "Using flake: $DOTFILES#$FLAKE_ATTR"

# ── 3. Apply the flake, auto-clearing any stale .bak collisions ──────────────
LOG="$(mktemp -t fixnix2)"
cd "$DOTFILES"
say "Applying your system config (this can take a few minutes) …"
for attempt in $(seq 1 25); do
  set +e
  "$DR" switch --flake ".#$FLAKE_ATTR" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
  set -e
  [ "$rc" -eq 0 ] && break

  # Home Manager refuses when both  X  and  X.bak  already exist.
  # Move the offending .bak aside and retry automatically. (Bash 3.2 safe.)
  CLOBBER=()
  while IFS= read -r cf; do
    [ -n "$cf" ] && CLOBBER+=("$cf")
  done < <(grep -o "Existing file '[^']*' would be clobbered by backing up" "$LOG" \
            | sed -E "s/Existing file '([^']*)'.*/\1/")
  if [ "${#CLOBBER[@]}" -eq 0 ]; then
    die "darwin-rebuild failed for a reason unrelated to backups (see output above)."
  fi
  for f in "${CLOBBER[@]}"; do
    if [ -e "$f" ]; then
      mv -f "$f" "$f.stale-$(date +%Y%m%d-%H%M%S)"
      warn "Moved stale backup aside: $f"
    fi
  done
  say "Retrying …"
done
rm -f "$LOG"
[ "$rc" -eq 0 ] || die "Gave up after clearing backups. Run again or check the output above."

# ── 4. Verify ─────────────────────────────────────────────────────────────────
echo
say "Verifying …"
PATHX="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
BREW_V="$(PATH="$PATHX" brew --version 2>/dev/null | head -1 || echo 'not found')"
NIX_V="$(PATH="$PATHX" nix --version 2>/dev/null || echo 'not found')"
test -e /etc/static/zshrc && ZSH_OK="OK" || ZSH_OK="MISSING"
ok "brew: $BREW_V"
ok "nix:  $NIX_V"
ok "zsh config (/etc/static/zshrc): $ZSH_OK"

echo
echo "  ┌────────────────────────────────────────────────────────────┐"
echo "  │  DONE. Nix is fully restored.                               │"
echo "  │  Open a fresh terminal — everything is back to normal.      │"
echo "  └────────────────────────────────────────────────────────────┘"
echo
