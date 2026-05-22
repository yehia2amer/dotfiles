# Yehia Amer's Dotfiles

Multi-machine Nix + Home Manager + Chezmoi configuration.

## Machines

- `MacBookProM3` — macOS Apple Silicon (primary)
- `nixos-laptop` — NixOS Linux laptop
- `nixos-server` — NixOS Linux server
- `nixos-wsl` — NixOS under WSL on Windows

## Architecture

```
flake.nix          → nix-darwin / NixOS (system config)
home/              → Home Manager (stable user environment)
chezmoi/           → Chezmoi (mutable dotfiles)
```

## 🚨 ABSOLUTE RULE: NO SECRETS IN GIT — EVER

No encrypted files, no age-wrapped secrets, no exceptions.
Secrets live ONLY in native OS credential stores (macOS Keychain / Linux secret-tool).
Pre-commit hooks (TruffleHog + Gitleaks via prek) block any secret from being committed.

## Apply

```bash
# macOS
darwin-rebuild switch --flake .#MacBookProM3
chezmoi apply

# NixOS
sudo nixos-rebuild switch --flake .#nixos-laptop
chezmoi apply
```

## Setup on new machine

```bash
git clone <repo> ~/.dotfiles
cd ~/.dotfiles
# Apply system config (darwin-rebuild or nixos-rebuild)
# Then:
chezmoi init --source ~/.dotfiles/chezmoi --apply
prek install
```
