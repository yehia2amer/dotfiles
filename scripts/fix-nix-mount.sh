#!/usr/bin/env bash
#
# fix-nix-mount.sh
#
# Recovers a nix-darwin install after macOS dropped the /nix mount.
# Symptom: the "Nix Store" APFS volume mounts at /Volumes/Nix Store instead
# of /nix, so brew/nix and /etc/static (zsh config) all dangle.
#
# Root cause pieces this restores:
#   1. /etc/synthetic.conf  -> the `nix` synthetic mountpoint line
#   2. /etc/fstab           -> LABEL=Nix\040Store /nix apfs rw,nobrowse
#   3. mounts the volume at /nix now (no reboot needed)
#
# Idempotent and safe to re-run. Run with: sudo ~/.dotfiles/scripts/fix-nix-mount.sh
#
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  x\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Must run as root:  sudo $0"

# ── Options ───────────────────────────────────────────────────────────────────
# --rebuild : after a successful mount, also run `darwin-rebuild switch` to
#             re-assert the flake and regenerate the org.nixos.darwin-store
#             daemon / synthetic.conf / fstab (needs network + the flake).
DO_REBUILD=0
FLAKE_DIR="${SUDO_USER:+/Users/$SUDO_USER}/.dotfiles"
FLAKE_ATTR="MacBookProM3"
for arg in "$@"; do
  case "$arg" in
    --rebuild) DO_REBUILD=1 ;;
    --flake=*) FLAKE_DIR="${arg#--flake=}" ;;
    -h|--help) printf 'Usage: sudo %s [--rebuild] [--flake=DIR]\n' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

VOL_NAME="Nix Store"

# ── 1. Locate the Nix Store APFS volume device ────────────────────────────────
log "Locating the '$VOL_NAME' APFS volume…"
DEV="$(/usr/sbin/diskutil info "$VOL_NAME" 2>/dev/null \
        | awk -F': *' '/Device Node/ {print $2; exit}')"
[ -n "${DEV:-}" ] || die "Could not find an APFS volume named '$VOL_NAME'."
ok "Found volume at $DEV"

# ── 2. Restore /etc/synthetic.conf (keep any existing non-nix entries) ────────
log "Ensuring /etc/synthetic.conf has the 'nix' mountpoint line…"
SYN=/etc/synthetic.conf
touch "$SYN"
if ! grep -qE '^nix([[:space:]]|$)' "$SYN"; then
  # prepend nix, preserving existing lines (e.g. the nix-darwin 'run' line)
  printf 'nix\n%s' "$(cat "$SYN")" > "$SYN.tmp" && mv "$SYN.tmp" "$SYN"
  ok "Added 'nix' to $SYN"
else
  ok "'nix' already present in $SYN"
fi
grep -qE '^run[[:space:]]' "$SYN" || { printf 'run\tprivate/var/run\n' >> "$SYN"; ok "Re-added 'run' line"; }

# ── 3. Restore /etc/fstab ─────────────────────────────────────────────────────
log "Ensuring /etc/fstab mounts the volume at /nix…"
FSTAB=/etc/fstab
FSTAB_LINE='LABEL=Nix\040Store /nix apfs rw,nobrowse'
touch "$FSTAB"
if ! grep -q '/nix apfs' "$FSTAB"; then
  printf '%s\n' "$FSTAB_LINE" >> "$FSTAB"
  ok "Wrote fstab entry"
else
  ok "fstab entry already present"
fi

# ── 4. Unmount the volume from the wrong location if needed ───────────────────
if /sbin/mount | grep -q "on /Volumes/$VOL_NAME "; then
  log "Unmounting misplaced volume from '/Volumes/$VOL_NAME'…"
  if /usr/sbin/diskutil unmount "$DEV" >/dev/null 2>&1; then
    ok "Unmounted"
  else
    warn "Busy (a shell has its cwd inside it) — forcing…"
    /usr/sbin/diskutil unmount force "$DEV" >/dev/null 2>&1 \
      && ok "Force-unmounted" \
      || die "Could not unmount $DEV even with force. Close other terminals sitting in /Volumes/$VOL_NAME and re-run."
  fi
fi

# ── 5. Create the synthetic /nix mountpoint (no reboot) ───────────────────────
if [ ! -d /nix ]; then
  log "Creating synthetic /nix mountpoint…"
  /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t >/dev/null 2>&1 || true
fi
[ -d /nix ] || die "/nix mountpoint still missing. A reboot will create it from synthetic.conf; reboot then re-run."
ok "/nix mountpoint exists"

# ── 6. Mount the volume at /nix ───────────────────────────────────────────────
if /sbin/mount | grep -q " on /nix "; then
  ok "Something already mounted at /nix"
else
  log "Mounting $DEV at /nix…"
  if /sbin/mount -o nobrowse -t apfs "$DEV" /nix 2>/tmp/nixmount.err; then
    ok "Mounted"
  else
    warn "Live mount failed: $(cat /tmp/nixmount.err)"
    cat <<'EOF'

  This is normal right after force-creating the /nix mountpoint (SIP won't
  let a freshly-synthesised /nix be mounted into until the next boot).
  Your /etc/synthetic.conf and /etc/fstab are now correct, so just:

      sudo reboot

  After reboot /nix mounts automatically. Then re-run with --rebuild:
      sudo ~/.dotfiles/scripts/fix-nix-mount.sh --rebuild
EOF
    exit 0
  fi
fi

# ── 7. Verify ─────────────────────────────────────────────────────────────────
log "Verifying…"
[ -d /nix/store ] || die "/nix/store not visible after mount — unexpected."
COUNT="$(ls /nix/store | wc -l | tr -d ' ')"
ok "/nix/store is populated ($COUNT entries)"
if [ -x /nix/var/nix/profiles/default/bin/nix-store ]; then
  ok "nix-store: $(/nix/var/nix/profiles/default/bin/nix-store --version)"
fi

cat <<'EOF'

────────────────────────────────────────────────────────────────────────
✅ /nix is remounted. brew, nix, and your shell config are back.
EOF

# ── 8. Optionally re-assert the flake (regenerates the darwin-store daemon) ────
if [ "$DO_REBUILD" -eq 1 ]; then
  DR=/nix/var/nix/profiles/system/sw/bin/darwin-rebuild
  [ -x "$DR" ] || die "darwin-rebuild not found at $DR"
  [ -e "$FLAKE_DIR/flake.nix" ] || die "No flake.nix in $FLAKE_DIR (pass --flake=DIR)"
  log "Running darwin-rebuild switch --flake $FLAKE_DIR#$FLAKE_ATTR …"
  "$DR" switch --flake "$FLAKE_DIR#$FLAKE_ATTR"
  ok "System re-asserted; org.nixos.darwin-store daemon restored"
  echo
  echo "Open a fresh terminal — you're fully healed."
else
  cat <<'EOF'

Make it permanent (regenerates the missing org.nixos.darwin-store
LaunchDaemon so a future macOS update won't break this again) by
re-running with --rebuild, or manually:

    sudo ~/.dotfiles/scripts/fix-nix-mount.sh --rebuild
    # or:
    cd ~/.dotfiles && sudo /nix/var/nix/profiles/system/sw/bin/darwin-rebuild switch --flake .#MacBookProM3

Then open a fresh terminal.
EOF
fi
echo "────────────────────────────────────────────────────────────────────────"
