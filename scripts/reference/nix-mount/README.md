# nix-mount reference

Reference material for recovering the `/nix` APFS mount on macOS.

## The problem

macOS system updates periodically wipe `/etc/synthetic.conf` (the `nix` line)
and `/etc/fstab`. Without them the "Nix Store" APFS volume mounts at
`/Volumes/Nix Store` instead of `/nix`, so every `/nix`-based symlink breaks:
`brew`, `nix`, and `/etc/static` -> your shell config all dangle. **No data is
lost** — the volume is intact, just mounted in the wrong place.

## The fix

Run the recovery script (self-contained, idempotent, offline):

```sh
sudo ~/.dotfiles/scripts/fix-nix-mount.sh            # emergency remount only
sudo ~/.dotfiles/scripts/fix-nix-mount.sh --rebuild  # remount + darwin-rebuild switch
```

If macOS refuses the live mount ("Operation not permitted"), the script tells
you to `sudo reboot` — after which `synthetic.conf` + `fstab` mount `/nix`
automatically, then re-run with `--rebuild`.

## These snapshots

`known-good-YYYY-MM-DD.md` files are captured copies of the working
`synthetic.conf` / `fstab` plus the Nix Store volume identity (name + UUID).
They are **reference/diff material only** — the script is the source of truth.
They contain no secrets.
