# Agent Instructions — ~/.dotfiles

## 🚨 ABSOLUTE RULES

1. **NO SECRETS IN GIT — EVER.** No encrypted files, no age-wrapped secrets, no "just this once." Secrets live ONLY in native OS credential stores.
   - macOS: `security add-generic-password` / `security find-generic-password -w`
   - Linux: `secret-tool store` / `secret-tool lookup`
   - Chezmoi templates use **`{{ keyring "service-name" "yamer003" }}`** — cross-platform, no OS branching (see Secrets section)
   - If a secret cannot be extracted → that file is NOT TRACKED

2. **NO EMPLOYER NAME IN REPO.** Zero trace of any employer. Work URLs, emails, domains all live in macOS Keychain. Use generic labels like "work-genai-base-url", "work-email".

3. **PRE-COMMIT SCANNING IS MANDATORY.** Both TruffleHog AND Gitleaks run on every commit (via prek). Fail on ALL findings (verified + unverified). False positives → allowlist individually, never weaken the scanner.

---

## Ownership Rules — What Goes Where

| Criteria | Owner | Examples |
|----------|-------|---------|
| System packages, macOS defaults, services | **nix-darwin / NixOS** | `nix/darwin/default.nix` |
| Stable user packages (150+ CLI tools) | **Home Manager** (`home/packages.nix`) | ripgrep, fd, kubectl, neovim |
| Stable program config via `programs.*` options | **Home Manager** (`home/programs/`) | git base, starship, atuin, direnv, bat, fzf, zoxide |
| Shell framework (enable + source chezmoi) | **Home Manager** (`home/shell/`) | zsh, fish, nushell |
| Mutable config you actively edit | **Chezmoi** (`chezmoi/`) | nvim, wezterm, nushell config.nu |
| Config that apps mutate (lockfiles, etc) | **Chezmoi** | lazy-lock.json, fish_variables |
| Per-machine templated files | **Chezmoi** (`.tmpl`) | .zshenv, .ssh/config, git local |
| Files with secrets → Keychain reference | **Chezmoi** (`.tmpl`) | .bb9/env, .multica/config.json |
| Files with secrets that CAN'T be extracted | **NOT TRACKED** | ~/.kube/config, ~/.talos/, SSH private keys |
| Cache/runtime/logs/state | **NOT TRACKED** (`.gitignore`) | ~/.cache, ~/.npm, ~/.ollama |

**ONE FILE, ONE OWNER.** Never let both Home Manager and Chezmoi manage the same file.

---

## Architecture

```
~/.dotfiles/
├── flake.nix              # Root flake — nix-darwin + NixOS + Home Manager
├── nix/darwin/            # macOS system config
├── nix/nixos/             # NixOS (laptop, server, wsl) placeholders
├── home/                  # Home Manager modules
│   ├── packages.nix       # 150+ CLI tools (shared all machines)
│   ├── shell/             # zsh.nix, fish.nix, nushell.nix
│   └── programs/          # git, starship, atuin, direnv, bat, fzf, zoxide, gh
├── chezmoi/               # Chezmoi source tree (deployed to ~/)
│   ├── .chezmoi.toml.tmpl # Machine detection (os+arch, not hostname)
│   ├── dot_config/        # ~/.config/* files
│   ├── dot_ssh/           # ~/.ssh/config (templated)
│   └── *.tmpl             # Templated files (secrets from Keychain)
├── scripts/               # apply-darwin.sh, apply-nixos.sh
├── docs/                  # dotfiles-inventory.csv
└── .pre-commit-config.yaml # prek + trufflehog + gitleaks
```

---

## Machines

| Machine | OS | Detection | Hostname |
|---------|----|-----------|---------
| MacBookProM3 | darwin + arm64 | `chezmoi.os == "darwin" && chezmoi.arch == "arm64"` | unreliable (changes with VPN/kubectl) |
| nixos-laptop | linux | `chezmoi.hostname == "nixos-laptop"` | stable |
| nixos-server | linux | `chezmoi.hostname == "nixos-server"` | stable |
| nixos-wsl | linux | `chezmoi.hostname == "nixos-wsl"` | stable |

⚠️ **macOS hostname is UNRELIABLE** — it changes with VPN/kubectl context. Detection uses `os + arch` combo instead.

---

## Secrets — Cross-Platform Keyring

Templates use chezmoi's built-in **`{{ keyring "service-name" "yamer003" }}`** function which abstracts the native credential store:

| Platform | Backend | Store command |
|----------|---------|---------------|
| macOS | Keychain | `security add-generic-password -a "yamer003" -s "<name>" -w "VALUE" -U` |
| Linux | Secret Service (gnome-keyring) | `echo -n "VALUE" \| secret-tool store --label="<name>" service "<name>" username "yamer003"` |
| Windows | Credential Manager | via `cmdkey` or GUI |

**⚠️ IMPORTANT: On Linux, secrets MUST use `username` attribute (not `account`)** — `go-keyring` (used by chezmoi) looks up by `{ service, username }`. Using `account` instead will cause "secret not found" errors.

### How it works

`{{ keyring }}` uses Go's `go-keyring` library (strategy pattern):
- Detects the OS at runtime
- Calls the platform-native credential API
- No OS branching needed in templates

### Storing secrets

```bash
# macOS
security add-generic-password -a "yamer003" -s "<service-name>" -w "VALUE" -U

# Linux (gnome-keyring) — NOTE: use 'username' not 'account'
echo -n "VALUE" | secret-tool store --label="<service-name>" service "<service-name>" username "yamer003"

# Verify on Linux
secret-tool lookup service "<service-name>" username "yamer003"
```

### Template usage

```
{{- /* Single line, works on macOS + Linux + Windows */ -}}
{{ keyring "bb9-api-key" "yamer003" }}
```

**Never do this** (old pattern, removed):
```
{{- if eq .os "darwin" -}}
{{ output "security" ... }}
{{- else -}}
{{ output "secret-tool" ... }}
{{- end -}}
```

### WSL-specific: gnome-keyring setup

On NixOS-WSL, gnome-keyring must be unlocked before `chezmoi apply`:
```bash
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
echo "" | gnome-keyring-daemon --unlock --components=secrets
```
The NixOS config (`nix/nixos/wsl.nix`) sets session env vars and auto-unlock.

### Secret inventory

| Service Name | What |
|---|---|
| `litellm-api-key` | Corp AI proxy API key (used by claude, codex, openai, codewiki) |
| `bb9-api-key` | BB9 OpenAI-compatible key |
| `multica-token` | Multica AI workspace token |
| `gitlab-pat-localhost` | GitLab PAT for local proxy |
| `github-token-nushell` | GitHub PAT for nushell scripts |
| `opencode-server-password` | OpenCode remote server password |
| `veracode-api-key-id` | Veracode scanner key ID |
| `veracode-api-key-secret` | Veracode scanner secret |
| `claude-code-oauth-token` | Claude Code OAuth token |
| `cloudflare-account-id` | Cloudflare account ID |
| `cloudflare-api-token` | Cloudflare API token |
| `work-genai-base-url` | Work AI gateway URL |
| `work-genai-internal-url` | Work AI internal URL |
| `work-vault-url` | Work HashiCorp Vault URL |
| `work-vault-namespace` | Work Vault namespace |
| `work-email` | Work email address |
| `work-dns-check-domain` | Domain for corp network detection |
| `work-ca-cert-path` | Path to corp CA cert |
| `work-ca-root-cert-path` | Path to corp root CA cert |

---

## Key Commands

```bash
# Apply system + dotfiles (macOS)
cd ~/.dotfiles && darwin-rebuild switch --flake .#MacBookProM3 && chezmoi apply

# Apply system + dotfiles (NixOS-WSL)
cd ~/.dotfiles && sudo nixos-rebuild switch --flake .#nixos-wsl && chezmoi apply

# Apply only dotfiles
chezmoi apply

# Preview changes
chezmoi diff

# Edit a managed file (edits source, not live)
chezmoi edit ~/.config/nvim/init.lua

# Add new file to chezmoi
chezmoi add ~/.config/somefile

# Check for secrets before committing
prek run --all-files

# Store a new secret (macOS)
security add-generic-password -a "yamer003" -s "new-secret-name" -w "VALUE" -U

# Store a new secret (Linux) — NOTE: 'username' not 'account'
echo -n "VALUE" | secret-tool store --label="new-secret-name" service "new-secret-name" username "yamer003"
```

---

## Handling False Positives (Secret Scanners)

Never weaken detection. Allowlist specifically:

| Scanner | Method | File |
|---------|--------|------|
| TruffleHog | Path exclusion | `.trufflehog-exclude-paths.txt` |
| Gitleaks | Fingerprint hash | `.gitleaksignore` |
| Gitleaks | Path/regex pattern | `.gitleaks.toml` `[allowlist]` |
| Gitleaks | Inline annotation | `# gitleaks:allow` in source |

Workflow:
```bash
# 1. Commit blocked → review finding
gitleaks detect --source . --no-git --report-format json --report-path /tmp/r.json
cat /tmp/r.json | jq '.[].Fingerprint'
# 2. If safe → add fingerprint
echo "FINGERPRINT" >> .gitleaksignore
# 3. Commit again
```

---

## Gotchas & Discoveries

- **macOS hostname changes** with VPN/kubectl context. Never use `chezmoi.hostname` for Mac detection.
- **Home Manager `home.homeDirectory`** needs `lib.mkForce` when using `useGlobalPkgs` with nix-darwin (nixos/common.nix sets it to null).
- **`darwin-rebuild build`** takes 5-15 min first time (downloading 150+ packages). Subsequent builds are instant.
- **`programs.git` options renamed** in recent HM: use `programs.git.settings.user.*` and `programs.delta`.
- **nix-darwin requires `system.primaryUser`** for `system.defaults.*` to work.
- **`credential.helper = store`** writes PLAINTEXT to `~/.git-credentials`. Always use `osxkeychain` on macOS.
- **SSH keys persist in Keychain** via `ssh-add --apple-use-keychain`. Survives reboots.
- **chezmoi `sourceDir`** must be set at root level in `~/.config/chezmoi/chezmoi.toml` (not under `[chezmoi]`).
- **`chezmoi init`** resets `sourceDir` — always re-set it after running init.
- **Nushell env vars from Keychain** use `(security find-generic-password ... | str trim)` syntax. These are NOT yet migrated to `keyring` (nushell env.nu is a plain file, not a chezmoi template — needs manual OS detection).
- **chezmoi `{{ keyring }}` requires `username` attribute on Linux** — `go-keyring` uses `{ service, username }` for Secret Service lookups. Storing with `account` instead of `username` will silently fail.
- **gnome-keyring in WSL** needs `XDG_RUNTIME_DIR=/run/user/1000` and `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`. The NixOS config sets these as session variables.
- **WSL distros share network namespace** — NixOS-WSL uses Ubuntu's cntlm proxy on `127.0.0.1:3128` and dnsmasq on `127.0.0.1:53` directly (no port forwarding needed).
- **pi on NixOS-WSL must run via bun** — Node.js + undici's `EnvHttpProxyAgent` doesn't work behind corp proxy. The NixOS activation script patches pi's shebang from `node` to `bun`. Re-run `sudo nixos-rebuild switch` after `bun update -g @mariozechner/pi-coding-agent`.
- **Corp network detection** in nushell caches DNS result for 5 min at `/tmp/.nu_corp_network_cache`.
- **`allowUnfreePredicate`** is preferred over `allowUnfree = true` — be explicit about which unfree packages.
- **Git identity**: default is personal (`yehamer@gmail.com`). Work identity via `includeIf` or manual gitconfig switch. Both configs in `chezmoi/dot_config/gitconfigs/`.

---

## Inventory

Full dotfiles/folders classification with reasoning: see `docs/dotfiles-inventory.csv`

Agents MUST update this CSV when adding/removing tracked files.

---

## Adding a New Dotfile

1. Decide owner (see Ownership Rules above)
2. If **Chezmoi**: `chezmoi add <file>`, convert to `.tmpl` if it has secrets/machine-specific paths
3. If **Home Manager**: add to appropriate `home/programs/*.nix` module
4. If has secrets: store value in Keychain, template references it
5. Run `prek run --all-files` — must pass
6. Update `docs/dotfiles-inventory.csv`
7. Commit

---

## Resuming This Session

The original session that created this repo is saved at:
```
docs/pi-session-2026-05-22T09-31-34-750Z_019e4f06-9fdd-709b-8867-02bd5aa2438c.html
```

To resume with full context in pi:
```bash
cd ~/.dotfiles
pi -r  # shows recent sessions, pick the one from 2026-05-22
# OR resume by ID:
pi --resume 019e4f06-9fdd-709b-8867-02bd5aa2438c
```

The HTML file is gitignored (not committed) but lives in `docs/` for local reference.

---

## WSL NixOS: SSH + Git Proxy (for agents)

> **Scope:** This section applies ONLY to NixOS-WSL (`nixos-wsl`). Other machines do not use cntlm.

On NixOS-WSL, all outbound traffic routes through cntlm (NTLM proxy at `127.0.0.1:3128`). SSH port 22 is blocked by the corporate firewall.

### Git push/pull over SSH

The SSH config at `~/.ssh/config` must include:

```
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  ProxyCommand nc -X connect -x 127.0.0.1:3128 %h %p
```

This routes SSH through the cntlm proxy to GitHub's port-443 SSH endpoint.

### Git identity for this repo

This repo uses **personal** git identity (not work). The `.gitconfig` file at the repo root sets:
```ini
[user]
    name = Yehia Amer
    email = yehamer@gmail.com
```

Agents MUST NOT commit with the work email to this repo. If `git config user.email` returns a work address, set the repo-local override:
```bash
git config user.email yehamer@gmail.com
git config user.name "Yehia Amer"
```

### Remote URL

Always use SSH (not HTTPS) for this repo on WSL:
```
git@github.com:yehia2amer/dotfiles.git
```

HTTPS will fail because the Windows credential manager provides work credentials that don't have access to the personal GitHub account.

### Troubleshooting

- **`ssh: connect to host github.com port 22: Connection timed out`** → SSH config missing or cntlm not running. Check `systemctl status cntlm`.
- **`Permission denied (publickey)`** → SSH key not added to GitHub. Run `cat ~/.ssh/id_ed25519.pub` and add at https://github.com/settings/ssh/new.
- **`Connection closed by ... port 443`** → Key exists but is not registered with the correct GitHub account.
- **HTTPS `403 denied to ...`** → Using HTTPS instead of SSH. Switch: `git remote set-url origin git@github.com:yehia2amer/dotfiles.git`
