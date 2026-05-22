#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "═══ Applying system config (nix-darwin) ═══"
darwin-rebuild switch --flake .#MacBookProM3

echo ""
echo "═══ Applying dotfiles (chezmoi) ═══"
chezmoi apply --source "$SCRIPT_DIR/chezmoi"

echo ""
echo "✅ All applied successfully"
