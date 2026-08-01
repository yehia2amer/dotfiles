#!/usr/bin/env bash
#
# fix-nix-1.sh  —  STEP 1 of 2  (run this first)
#
# For when macOS broke Nix: brew/nix/zsh all dead because the "Nix Store"
# volume no longer mounts at /nix.
#
# Just run:   sudo ~/.dotfiles/scripts/fix-nix-1.sh
#
# It restores the boot config, unmounts the misplaced volume, and REBOOTS
# automatically. After the reboot, run step 2:  sudo ~/.dotfiles/scripts/fix-nix-2.sh
#
# No arguments. Safe to re-run. Ctrl-C during the countdown cancels the reboot.
#
set -euo pipefail

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run me with sudo:  sudo $0"

VOL="Nix Store"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo "  ┌────────────────────────────────────────────┐"
echo "  │  Nix recovery — STEP 1 of 2 (restore+reboot)│"
echo "  └────────────────────────────────────────────┘"
echo

# ── Already healthy? Then do nothing. ─────────────────────────────────────────
if /sbin/mount | grep -q " on /nix " && [ -n "$(ls /nix/store 2>/dev/null | head -1)" ]; then
  ok "/nix is already mounted and populated — nothing to fix here."
  echo
  echo "If your tools still look broken, just run step 2:"
  echo "    sudo $SELFDIR/fix-nix-2.sh"
  exit 0
fi

# ── 1. Restore /etc/synthetic.conf (the 'nix' mountpoint line) ────────────────
say "Restoring /etc/synthetic.conf …"
SYN=/etc/synthetic.conf
touch "$SYN"
grep -qE '^nix([[:space:]]|$)' "$SYN" || { printf 'nix\n%s' "$(cat "$SYN")" > "$SYN.tmp" && mv "$SYN.tmp" "$SYN"; }
grep -qE '^run[[:space:]]'      "$SYN" || printf 'run\tprivate/var/run\n' >> "$SYN"
ok "synthetic.conf ready"

# ── 2. Restore /etc/fstab (mount the volume at /nix) ──────────────────────────
say "Restoring /etc/fstab …"
FSTAB=/etc/fstab
touch "$FSTAB"
grep -q '/nix apfs' "$FSTAB" || printf 'LABEL=Nix\\040Store /nix apfs rw,nobrowse\n' >> "$FSTAB"
ok "fstab ready"

# ── 3. Unmount the volume from the wrong place (/Volumes/Nix Store) ───────────
if /sbin/mount | grep -q "on /Volumes/$VOL "; then
  say "Unmounting misplaced volume …"
  DEV="$(/usr/sbin/diskutil info "$VOL" 2>/dev/null | awk -F': *' '/Device Node/ {print $2; exit}')"
  /usr/sbin/diskutil unmount "$DEV" >/dev/null 2>&1 \
    || /usr/sbin/diskutil unmount force "$DEV" >/dev/null 2>&1 \
    || die "Could not unmount the volume. Close other terminals and re-run."
  ok "Unmounted"
fi

# ── 4. Create the synthetic /nix mountpoint (takes effect fully on reboot) ────
say "Preparing /nix mountpoint …"
/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t >/dev/null 2>&1 || true
ok "Prepared"

# ── 5. Reboot automatically ───────────────────────────────────────────────────
echo
echo "  ┌────────────────────────────────────────────────────────────┐"
echo "  │  Rebooting to finish the mount.                             │"
echo "  │                                                            │"
echo "  │  AFTER the reboot, run STEP 2:                             │"
echo "  │      sudo $SELFDIR/fix-nix-2.sh"
echo "  └────────────────────────────────────────────────────────────┘"
echo
for n in 10 9 8 7 6 5 4 3 2 1; do
  printf '\r  Rebooting in %2ds …  (press Ctrl-C to cancel)   ' "$n"
  sleep 1
done
printf '\r  Rebooting now.                                   \n'
/sbin/shutdown -r now
