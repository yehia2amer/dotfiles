#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-nixos-laptop}"
cd "$SCRIPT_DIR"

echo "═══ Applying system config (NixOS: $HOST) ═══"
sudo nixos-rebuild switch --flake ".#$HOST"

echo ""
echo "═══ Applying dotfiles (chezmoi) ═══"
chezmoi apply --source "$SCRIPT_DIR/chezmoi"

echo ""
echo "✅ All applied successfully"
