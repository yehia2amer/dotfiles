# Secrets & AI-agent tooling — Bitwarden Secrets Manager + Varlock credential proxy.
# See docs/varlock-bitwarden-secrets.md for the full design & migration runbook.
#
# Scope (per decision D1): PERSONAL secrets → Bitwarden; WORK secrets stay on macOS Keychain.
# varlock itself is installed via Homebrew (not in nixpkgs); bws comes from nixpkgs here.
{ pkgs, lib, ... }:
let
  # Sandboxed AI-agent launcher (guide §13 macOS form). Strips the human SSH agent
  # and all Bitwarden session/token env, then runs the agent inside varlock's
  # built-in macOS sandbox so it only ever sees credential *placeholders*.
  #
  # Usage:  ai <agent-command> [args...]
  # NEVER use `varlock run` (injects real values) or un-sandboxed `varlock proxy run`.
  aiLauncher = pkgs.writeShellScriptBin "ai" ''
    set -euo pipefail
    if ! command -v varlock >/dev/null 2>&1; then
      echo "ai: varlock not found on PATH (install via: brew install varlock && brew pin varlock)" >&2
      exit 127
    fi
    if [ "$#" -eq 0 ]; then
      echo "usage: ai <agent-command> [args...]" >&2
      exit 64
    fi
    exec env \
      -u SSH_AUTH_SOCK \
      -u BW_SESSION \
      -u BWS_ACCESS_TOKEN \
      -u BITWARDENCLI_APPDATA_DIR \
      varlock proxy run --sandbox -- "$@"
  '';
in
{
  home.packages = with pkgs; [
    bws          # Bitwarden Secrets Manager CLI (pinned via flake.lock)
    aiLauncher   # `ai` sandboxed agent launcher
  ];
}
