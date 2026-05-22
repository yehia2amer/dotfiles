# Adding a New Machine

## Overview

This guide covers adding a new machine to the dotfiles repo. Each machine needs:
1. A Nix system config (nix-darwin or NixOS)
2. Home Manager integration (packages + programs)
3. Chezmoi detection + conditional deployment
4. Secrets populated in the native OS credential store

---

## Step 1: Choose Machine Name

Pick a stable, descriptive name. Examples: `MacBookProM3`, `nixos-laptop`, `nixos-server`, `nixos-wsl`.

**Rules:**
- No employer names
- No hostnames that change (macOS hostnames are unreliable)
- Use in: flake.nix, chezmoi template, apply scripts

---

## Step 2: Chezmoi Detection

Edit `chezmoi/.chezmoi.toml.tmpl` — add a new condition:

```toml
{{- else if eq .chezmoi.hostname "NEW-HOSTNAME" }}
    machine = "NewMachineName"
    work = false
    os = "linux"
```

**For macOS:** Don't use hostname (it changes). Use `os + arch`:
```toml
{{- if and (eq .chezmoi.os "darwin") (eq .chezmoi.arch "arm64") }}
```

**For Linux:** Hostname is stable — use it directly.

---

## Step 3: Nix System Config

### If macOS (nix-darwin):

Create or reuse `nix/darwin/default.nix`. Add a new darwinConfiguration in `flake.nix`:

```nix
darwinConfigurations."NewMachineName" = nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";  # or x86_64-darwin
  modules = [
    ./nix/darwin
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.yamer003 = { pkgs, ... }: {
        imports = [ ./home ];
        home.homeDirectory = "/Users/yamer003";
      };
    }
  ];
};
```

### If NixOS:

Create `nix/nixos/newmachine.nix` with hardware config. Add to `flake.nix`:

```nix
nixosConfigurations."newmachine" = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./nix/nixos/newmachine.nix
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.yamer003 = import ./home;
    }
  ];
};
```

**NixOS config needs at minimum:**
- `networking.hostName`
- `system.stateVersion`
- Hardware config (from `nixos-generate-config`)
- Boot loader config
- User account (`users.users.yamer003`)

---

## Step 4: Home Manager

**Shared automatically** — `home/default.nix` imports all modules. The new machine gets:
- All 150+ packages from `packages.nix`
- All programs (git, starship, atuin, etc.)
- Shell framework (zsh, fish, nushell)

**Platform-specific packages** are handled by:
- `packages-darwin.nix` — only installs on macOS
- `packages-linux.nix` — only installs on Linux

**If the new machine needs different packages:** Add a conditional in the relevant file:
```nix
home.packages = lib.optionals (pkgs.stdenv.isLinux) [ ... ];
```

**If homeDirectory differs** (different username or OS):
- macOS: set `home.homeDirectory = lib.mkForce "/Users/USERNAME";` in the flake
- Linux: the default `/home/yamer003` from `home/default.nix` works

---

## Step 5: Chezmoi Conditionals

### Files that should NOT deploy on this machine:

Edit `chezmoi/.chezmoiignore`:

```
{{ if eq .machine "NewMachineName" }}
dot_config/wezterm
dot_config/alacritty
private_Library
{{ end }}
```

### Templates that behave differently per machine:

Any `.tmpl` file can use:
```
{{ if eq .machine "NewMachineName" }}
  ...machine-specific content...
{{ end }}

{{ if eq .os "linux" }}
  ...linux-specific content...
{{ end }}

{{ if .work }}
  ...work-machine content...
{{ end }}
```

---

## Step 6: Secrets (Native Credential Store)

Chezmoi templates use `{{ keyring "service-name" "yamer003" }}` which is cross-platform.
The `keyring` function auto-detects the OS and calls the native credential API.

### macOS (new Mac):
```bash
# Store all required secrets in Keychain
security add-generic-password -a "yamer003" -s "litellm-api-key" -w "VALUE" -U
security add-generic-password -a "yamer003" -s "github-token-nushell" -w "VALUE" -U
# ... (see AGENTS.md for full list)

# Load SSH keys
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

### Linux (NixOS / NixOS-WSL):
```bash
# ⚠️  IMPORTANT: use 'username' attribute (NOT 'account')
# go-keyring (used by chezmoi's {{ keyring }}) looks up by { service, username }
echo -n "VALUE" | secret-tool store --label="litellm-api-key" service "litellm-api-key" username "yamer003"
echo -n "VALUE" | secret-tool store --label="github-token-nushell" service "github-token-nushell" username "yamer003"

# Verify
secret-tool lookup service "litellm-api-key" username "yamer003"

# SSH keys
ssh-add ~/.ssh/id_ed25519
```

### WSL-specific: gnome-keyring must be unlocked first
```bash
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
echo "" | gnome-keyring-daemon --unlock --components=secrets
# Then store secrets as above
```
The NixOS-WSL config auto-sets these env vars and unlocks on boot.

**Required secrets** (minimum to function — see AGENTS.md for full list):
| Service Name | Needed for |
|---|---|
| `litellm-api-key` | AI tools (claude, codex, openai env var) |
| `github-token-nushell` | Nushell scripts |
| `work-email` | Work git identity |
| `work-genai-base-url` | AI gateway URL |

Not all secrets are needed on every machine. A personal Linux laptop without work tools only needs `github-token-nushell`.

---

## Step 7: Apply Script

Create `scripts/apply-newmachine.sh` or use the existing generic ones:

```bash
# macOS
./scripts/apply-darwin.sh

# NixOS
./scripts/apply-nixos.sh newmachine
```

---

## Step 8: Bootstrap (First-Time Setup on New Machine)

```bash
# 1. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh

# 2. Clone repo
git clone <REPO_URL> ~/.dotfiles
cd ~/.dotfiles

# 3. Apply system config
# macOS:
darwin-rebuild switch --flake .#NewMachineName
# NixOS:
sudo nixos-rebuild switch --flake .#newmachine

# 4. Set up chezmoi
chezmoi init --source ~/.dotfiles/chezmoi
# Fix sourceDir if needed:
echo 'sourceDir = "/home/yamer003/.dotfiles/chezmoi"' > ~/.config/chezmoi/chezmoi.toml
chezmoi init --source ~/.dotfiles/chezmoi  # regenerates [data] from template

# 5. Populate secrets in native store (see Step 6)

# 6. Apply dotfiles
chezmoi apply

# 7. Install pre-commit hooks
prek install

# 8. Verify
prek run --all-files
```

---

## What's Shared vs Machine-Specific

| Layer | Shared | Machine-Specific |
|-------|--------|-----------------|
| **Packages** | `home/packages.nix` (150+ tools) | `packages-darwin.nix`, `packages-linux.nix` |
| **Programs** | All of `home/programs/` | `credential.helper` (osxkeychain vs libsecret) |
| **Shell** | Framework (zsh/fish/nushell enable) | PATH, certs, brew (in `.tmpl` files) |
| **Dotfiles** | Most of `chezmoi/dot_config/` | `.tmpl` files, `.chezmoiignore` exclusions |
| **Secrets** | Same service names in keychain | Values differ per machine |
| **System** | Nothing — each OS is different | `nix/darwin/` or `nix/nixos/*.nix` |

---

## Checklist

- [ ] Machine name chosen (no employer, no unstable hostname)
- [ ] `chezmoi/.chezmoi.toml.tmpl` — detection added
- [ ] `flake.nix` — new configuration added
- [ ] `nix/` — system config created (darwin or nixos)
- [ ] `chezmoi/.chezmoiignore` — exclusions for this machine (if any)
- [ ] Secrets populated in native credential store
- [ ] `chezmoi apply` works
- [ ] `darwin-rebuild` or `nixos-rebuild` succeeds
- [ ] `prek run --all-files` passes
- [ ] `docs/dotfiles-inventory.csv` updated (if new files added)
