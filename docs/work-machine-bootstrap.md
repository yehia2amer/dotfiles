# Work Machine Bootstrap (macOS / nix-darwin)

A simple "run this, run that" guide to bring a freshly-imaged **work-managed Mac**
up to a working environment. No corporate identifiers live in this repo — all
work-specific values are read at runtime from the **macOS login Keychain**.

> Related: `docs/varlock-bitwarden-secrets.md` (AI-agent secrets via Varlock +
> Bitwarden), `docs/adding-a-new-machine.md`.

---

## Prerequisites

- Nix is installed (Determinate/standard multi-user), `nix --version` works.
- This repo is cloned to `~/.dotfiles`.
- You have your **corporate CA** as a PEM file (root + issuing), e.g. exported by IT.
- You are on the corporate network/VPN at least once (to reach internal hosts).

---

## Step 1 — Trust the corporate CA for Nix (TLS over the VPN)

On a work machine the VPN re-signs TLS with a corporate CA. Merge it with the
public roots so Nix works VPN **on and off**:

```bash
sudo WORK_CA_PEM=/path/to/your/corporate-ca.pem \
  bash ~/.dotfiles/scripts/setup-work-ca-bundle.sh
```

This writes `/etc/nix/ca-bundle-work.crt` (referenced by `nix/darwin/default.nix`
and the shell `CA` var) and reloads the nix-daemon. Verify:

```bash
grep -c 'BEGIN CERT' /etc/nix/ca-bundle-work.crt   # public roots + your corp certs
```

> If the first `darwin-rebuild`/`activate` aborts with
> `apfs.util failed to symlink /run`, create the synthetic first, then re-run:
> ```bash
> printf 'run\tprivate/var/run\n' | sudo tee /etc/synthetic.conf
> sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
> ```

---

## Step 2 — Populate work secrets into the Keychain

The dotfiles read all work-specific values from the login Keychain (via chezmoi's
`keyring()` and `security` in scripts). chezmoi's `keyring()` **errors** on a
missing item and aborts the whole apply — so first create every item (empty if
absent; existing ones are never touched):

```bash
bash ~/.dotfiles/scripts/ensure-work-keychain.sh
```

This lets `chezmoi apply` (Step 4) succeed immediately with empty placeholders.
Then fill in the real values — now, or incrementally whenever you have them:

```bash
bash ~/.dotfiles/scripts/setup-work-keychain.sh
```

Values are entered through `security`'s own hidden prompt, never via argv or
shell history. After updating any value, re-run `chezmoi apply` to re-render.
Items:

| Keychain service | Used by | What it is |
|---|---|---|
| `work-email` | git identity (`~/.gitconfig-work`) | your work commit email |
| `work-genai-base-url` | codex / claude / codewiki / scripts | LiteLLM proxy base URL |
| `work-genai-internal-url` | `update-pi-models.py` | internal mgmt API URL |
| `work-genai-web-url` | `update-pi-models.py` | web portal (Chrome SSO tab) |
| `work-vault-url`, `work-vault-namespace` | vault scripts | HashiCorp Vault |
| `work-dns-check-domain` | dns scripts | internal DNS probe host |
| `work-ca-root-cert-path` | scripts | path to corporate root CA |
| `litellm-api-key` | claude / bb9 / scripts | LiteLLM bearer token |
| `bb9-api-key` | `~/.bb9/env` | bb9 OpenAI-compatible key |
| `multica-token` | `~/.multica/config.json` | multica token |
| `gitlab-pat-localhost` | `~/.config/glab-cli` | GitLab PAT (localhost proxy) |
| `veracode-api-key-id` / `-secret` | veracode scripts | Veracode API creds |
| `cloudflare-account-id` / `cloudflare-api-token` | cloudflare scripts | Cloudflare |
| `github-token-nushell` | nushell scripts | GitHub token |
| `claude-code-oauth-token` | claude | OAuth token |
| `opencode-server-password` | opencode | server password |

> Only populate what you actually use — anything skipped just renders empty and
> can be added later by re-running the script.

---

## Step 3 — Activate the system (nix-darwin)

First bootstrap (installs `darwin-rebuild` etc.):

```bash
sudo nix run nix-darwin -- switch --flake ~/.dotfiles#MacBookProM3 \
  --extra-experimental-features "nix-command flakes"
```

Afterwards, day-to-day:

```bash
darwin-rebuild switch --flake ~/.dotfiles#MacBookProM3
```

---

## Step 4 — Apply dotfiles (chezmoi)

```bash
chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply --source ~/.dotfiles/chezmoi
```

`chezmoi apply` renders templates using the Keychain values from Step 2. Items
you left empty render as empty strings (harmless) — update them later with
`setup-work-keychain.sh` and re-run `chezmoi apply` to fill them in.

---

## Step 5 — Personal SSH (Bitwarden SSH Agent)

Personal Git uses the Bitwarden SSH Agent (private key stays in the vault):

1. Bitwarden desktop → **New → SSH key** → generate Ed25519 → save.
2. Add the **public** key to GitHub: <https://github.com/settings/ssh/new>.
3. Store the public key at `~/.ssh/public/github-personal.pub` (chezmoi manages this).
4. Test: `ssh -T git@github.com` → Bitwarden prompts, then `Hi <user>!`.

(Work SSH keys are managed separately — restored from backup / IT, not in this repo.)

---

## Step 6 — Verify

```bash
# Nix + darwin
darwin-rebuild --version
grep ssl-cert-file /etc/nix/nix.conf                    # → /etc/nix/ca-bundle-work.crt

# Keychain wired into a rendered file (example)
grep -q . ~/.gitconfig-work && echo "work git identity set"

# TLS works (VPN on or off)
nix flake metadata github:LnL7/nix-darwin >/dev/null && echo "nix TLS ok"

# SSH via Bitwarden
ssh -T git@github.com
```

Done — environment is set up.
