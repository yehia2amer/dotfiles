# Yehia Amer's Dotfiles

Multi-machine configuration spanning macOS and NixOS, using **Nix Flakes** for system/package management, **Home Manager** for user environment, and **Chezmoi** for mutable dotfiles.

## Machines

| Machine | OS | Flake target | Notes |
|---------|----|--------------| ------|
| `MacBookProM3` | macOS (aarch64) | `darwinConfigurations.MacBookProM3` | Primary workstation |
| `nixos-laptop` | NixOS (x86_64) | `nixosConfigurations.nixos-laptop` | Linux laptop |
| `nixos-server` | NixOS (x86_64) | `nixosConfigurations.nixos-server` | Headless server |
| `nixos-wsl` | NixOS on WSL | `nixosConfigurations.nixos-wsl` | Windows dev via WSL2 |

## Architecture

```
~/.dotfiles/
├── flake.nix              # Root flake — declares all machines + inputs
├── flake.lock             # Pinned dependency versions
├── nix/
│   ├── darwin/            # macOS system config (nix-darwin)
│   └── nixos/             # NixOS configs (laptop, server, wsl)
├── home/                  # Home Manager modules (shared across all machines)
│   ├── default.nix        # Entry point — imports everything below
│   ├── packages.nix       # 150+ CLI tools (cross-platform)
│   ├── packages-darwin.nix
│   ├── packages-linux.nix
│   ├── programs/          # Declarative program configs (git, starship, atuin, etc.)
│   ├── shell/             # Shell framework (zsh, fish, nushell) — enables only
│   └── services/          # User services
├── chezmoi/               # Chezmoi source tree (mutable dotfiles → ~/)
│   ├── .chezmoi.toml.tmpl # Machine detection (os/arch/hostname)
│   ├── .chezmoiignore     # Per-machine file exclusions
│   ├── dot_config/        # ~/.config/* (nvim, wezterm, nushell, etc.)
│   └── *.tmpl             # Templated files (secrets from keyring)
├── scripts/               # apply-darwin.sh, apply-nixos.sh
├── docs/                  # Guides, inventory CSV
└── .pre-commit-config.yaml # TruffleHog + Gitleaks (via prek)
```

## Three Layers: Flakes → Home Manager → Chezmoi

### 1. Nix Flakes (System)

The `flake.nix` declares each machine as a `darwinConfiguration` or `nixosConfiguration`. It pins nixpkgs, nix-darwin, home-manager, nixos-wsl, and vscode-server as inputs.

**Responsibilities:** system packages, services (cntlm, dnsmasq, cloudflared, openssh, vscode-server), networking, user accounts, macOS defaults.

### 2. Home Manager (User Environment)

Integrated as a module inside each flake configuration (not standalone). Uses `useGlobalPkgs = true` to share the flake's nixpkgs.

**Responsibilities:** 150+ CLI tools, declarative program configs (git, starship, atuin, direnv, bat, fzf, zoxide, gh), shell enablement (zsh/fish/nushell).

**Key pattern:** Home Manager only *enables* shells and provides the framework. Actual shell config content lives in Chezmoi (to allow mutable editing without rebuilds).

### 3. Chezmoi (Mutable Dotfiles)

Handles files that are actively edited, app-mutated (lockfiles), machine-templated, or contain keyring secret references.

**Responsibilities:** nvim config, wezterm, nushell config.nu/env.nu, zsh local config, SSH config, git identity conditionals, app configs with secrets.

### One File, One Owner

Never let both Home Manager and Chezmoi manage the same file. The boundary is:
- **Stable, declarative** → Home Manager
- **Mutable, templated, or has secrets** → Chezmoi

## Syncing Workflow

```bash
# Full apply (system + user env + dotfiles)
cd ~/.dotfiles

# macOS:
darwin-rebuild switch --flake .#MacBookProM3 && chezmoi apply

# NixOS (any machine):
sudo nixos-rebuild switch --flake .#nixos-wsl && chezmoi apply

# Or use the convenience scripts:
./scripts/apply-darwin.sh
./scripts/apply-nixos.sh nixos-wsl
```

After editing nix files → `nixos-rebuild switch` or `darwin-rebuild switch`
After editing chezmoi files → `chezmoi apply`
After editing both → run both

## 🚨 NO SECRETS IN GIT — EVER

Secrets live ONLY in native OS credential stores (macOS Keychain / Linux gnome-keyring via secret-tool). Chezmoi templates reference them via `{{ keyring "service-name" "yamer003" }}`. Pre-commit hooks (TruffleHog + Gitleaks) block any secret from being committed.

## Setup on New Machine

```bash
# 1. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh

# 2. Clone
git clone git@github.com:yehia2amer/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 3. Apply system config
# macOS:
darwin-rebuild switch --flake .#MacBookProM3
# NixOS:
sudo nixos-rebuild switch --flake .#<machine-name>

# 4. Populate secrets in native credential store (see docs/adding-a-new-machine.md)

# 5. Apply dotfiles
chezmoi init --source ~/.dotfiles/chezmoi --apply

# 6. Install pre-commit hooks
prek install
```

### WSL NixOS: SSH + Git Proxy Setup

On NixOS-WSL, outbound connections go through cntlm (NTLM authenticating proxy at `127.0.0.1:3128`). GitHub SSH on port 22 is blocked. To make git push/pull work over SSH:

1. **Add SSH config for GitHub** (route through proxy on port 443):
   ```
   # ~/.ssh/config
   Host github.com
     HostName ssh.github.com
     Port 443
     User git
     ProxyCommand nc -X connect -x 127.0.0.1:3128 %h %p
   ```

2. **Add your SSH public key to GitHub** at https://github.com/settings/ssh/new:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```

3. **Verify**:
   ```bash
   ssh -T git@github.com
   # Should print: Hi <username>! You've successfully authenticated...
   ```

4. **Use SSH remote** (not HTTPS):
   ```bash
   git remote set-url origin git@github.com:yehia2amer/dotfiles.git
   ```

5. **Repo-local git identity** (this repo uses personal, not work):
   ```bash
   git config user.email yehamer@gmail.com
   git config user.name "Yehia Amer"
   ```
   This is already stored in `.gitconfig` at the repo root.

## Further Docs

- [Adding a new machine](docs/adding-a-new-machine.md)
- [AGENTS.md](AGENTS.md) — AI agent instructions
- [docs/dotfiles-inventory.csv](docs/dotfiles-inventory.csv) — full file classification