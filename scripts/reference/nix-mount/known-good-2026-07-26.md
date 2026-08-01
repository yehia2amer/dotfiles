# Nix /nix mount – known-good reference snapshot
# Captured: Sun Jul 26 01:12:47 EEST 2026
# Host: EG-D7DQNFQL43  (flake attr: MacBookProM3)
# Purpose: macOS updates wipe /etc/synthetic.conf + /etc/fstab, unmounting
#          the Nix Store volume from /nix. Restore with scripts/fix-nix-mount.sh
#          (this snapshot is reference/diff material only).

## /etc/synthetic.conf
    nix
    run	private/var/run
## /etc/fstab
    LABEL=Nix\040Store /nix apfs rw,nobrowse

## Nix Store volume identity (diskutil)
       Volume Name: Nix Store
       Mount Point: /nix
       File System Personality: APFS
       Volume UUID: 75816868-F97F-4A86-B71B-941E052FF49C
       APFS Physical Store: disk0s2

## nixos LaunchDaemons present
    /Library/LaunchDaemons/org.nixos.activate-system.plist
    /Library/LaunchDaemons/org.nixos.nix-daemon.plist
