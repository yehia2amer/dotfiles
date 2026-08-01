#!/usr/bin/env bash
# Build the merged CA bundle that lets Nix do TLS on a corporate-MITM machine.
# Merges the public CA roots (from Nix's cacert) with your corporate CA
# (root + issuing) so fetches work with the corporate VPN both ON (intercepted)
# and OFF (normal internet).
#
# The output path matches nix/darwin/default.nix (workCaBundle) and the shell
# CA var in chezmoi (dot_config/zsh/local.zsh.tmpl).
#
# Usage (run as root; provide YOUR corporate CA PEM — root+issuing concatenated):
#   sudo WORK_CA_PEM=/path/to/corporate-ca.pem bash scripts/setup-work-ca-bundle.sh
#
# See docs/work-machine-bootstrap.md.
set -euo pipefail

BASE="/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"   # public roots (nss-cacert)
OUT="/etc/nix/ca-bundle-work.crt"

: "${WORK_CA_PEM:?set WORK_CA_PEM=/path/to/your/corporate-ca.pem (root+issuing, PEM format)}"
[ "$(id -u)" = 0 ] || { echo "!! run with sudo (writes $OUT, reloads nix-daemon)"; exit 1; }
[ -r "$BASE" ]      || { echo "!! base bundle not found: $BASE (is Nix installed?)"; exit 1; }
[ -r "$WORK_CA_PEM" ] || { echo "!! corporate CA PEM not readable: $WORK_CA_PEM"; exit 1; }

umask 022
{
  cat "$BASE"
  echo ""
  echo "# --- corporate CA (root + issuing) ---"
  cat "$WORK_CA_PEM"
} > "$OUT"
chmod 0644 "$OUT"
echo "wrote $OUT ($(grep -c 'BEGIN CERT' "$OUT") certs)"

# Reload the daemon so it picks up the new bundle immediately (nix.conf points here).
launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || true
echo "done."
