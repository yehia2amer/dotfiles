# Varlock + Bitwarden — Tailored Implementation & Migration Guide

> **This machine:** `EG_D7DQNFQL43` · Apple M3 Pro · macOS 26.5.2 · work-managed (Microsoft Intune MDM)
> **Stack:** Nix flake → nix-darwin → Home Manager → Chezmoi
> **Source guide:** `~/Downloads/Varlock_Bitwarden_Security_Guide_v2.md` (validated against Varlock 1.13.0)
> **This doc:** how to apply that architecture to *our specific* configs, with a phased migration runbook.
> **Status:** IN PROGRESS.

## Progress (live)

| Phase | State |
|---|---|
| 0 — Human checkpoints (account harden, SSH Agent, machine account + encrypted token) | ✅ done |
| 1 — Tooling (`bws`, `varlock 1.13.0` pinned, `ai` launcher, Bitwarden desktop) | ✅ done + committed |
| 2 — Personal SSH via Bitwarden SSH Agent (new key in vault, `ssh -T` OK) | ✅ done |
| 3 — Git identity via `includeIf gitdir` | ✅ done (live & verified: work/personal switch) |
| 4 — Varlock proxy pilot (`pilot-personal`) | ✅ validated (fake key → real chain proven) |
| 5a — De-classify corporate CA path (drop `keyring`) | ✅ done; renamed to `/etc/nix/ca-bundle-work.crt` |
| — De-corporatize repo + bootstrap guide/scripts | ✅ done (zero corp identifiers; Keychain-driven) |
| 5b — Migrate remaining secrets (personal→SM, work→Keychain) | ⏳ pending (full `chezmoi apply` once Keychain populated) |
| 6 — Daily workflow + acceptance | ⏳ pending |

---

## 0. Environment validation (findings, 2026-07-22)

| Component | State | Action implied |
|---|---|---|
| `bw` Password Manager CLI | ✅ 2026.6.0 · logged in `yehia2amer@gmail.com` · **locked** · cloud/personal | Host for **SSH-key items** (personal) |
| `bws` Secrets Manager CLI | ❌ not installed · not in brew · ✅ nixpkgs `2.1.0` | Declare in Home Manager |
| `varlock` | ✅ installed via brew **1.13.0** (matches guide) · pinned · not in nixpkgs | done (`brew pin varlock`) |
| Bitwarden **desktop app** | ❌ not installed · nixpkgs `bitwarden-desktop 2026.5.0` / brew cask `bitwarden` | Required for **SSH Agent** |
| docker / colima / podman | ❌ none | Use macOS built-in `--sandbox` (seatbelt) |
| `/usr/bin/sandbox-exec` | ✅ present | `varlock proxy run --sandbox` works |
| Secure Enclave | ✅ M3 Pro / arm64 | `varlock encrypt` at-rest protection works |
| node / npm | ✅ v24 / 11 | varlock Bitwarden plugin OK |

**Verdict:** the architecture is viable on this Mac using the **macOS built-in sandbox**. Blockers before migration: (a) install Bitwarden desktop for the SSH Agent, (b) resolve the **work-secret governance** question below (D1). Varlock is installed via **Homebrew** (`brew install varlock`, then `brew pin varlock`).

---

## 1. Decisions required before we start (human)

### D1 — Work-secret governance (BLOCKER) 🔴
This is a **work-managed** device and several secrets are **work** secrets:
`litellm-api-key`, `work-genai-base-url`, `work-email`, `gitlab-pat-localhost`, `bb9-api-key`, `multica-token`, and the corporate CA path (`work-ca-cert-path`).

**Do not** upload work secrets to your **personal** Bitwarden (`yehia2amer@gmail.com`). Recommended split:

| Trust boundary | Secret backend | SSH backend |
|---|---|---|
| **Personal** (github-personal, personal API keys) | Personal Bitwarden **Secrets Manager** + SSH Agent | Personal Bitwarden SSH items |
| **Work** (genai/gitlab/azure) | **Keep in macOS Keychain** (current model) *or* an employer-sanctioned vault | Keep current key files *or* an employer-sanctioned store |

The guide's `varlock-personal-<device>` / `varlock-work-<device>` split still applies — but the **work** machine-account only makes sense if the employer provides a sanctioned Secrets Manager org. Until then, **work secrets stay on Keychain** and only **personal** secrets move to Bitwarden SM.

> ✅ **DECIDED:** personal secrets/SSH → personal Bitwarden; **work secrets/SSH → stay on macOS Keychain (current model, unchanged)**. No work credential is ever uploaded to personal Bitwarden.

### D2 — Varlock version pin (DECIDED: Homebrew, DONE)
`varlock` isn't in nixpkgs, so it can't ride `flake.lock`. **Decision: installed via Homebrew** — `brew install varlock` (currently **1.13.0**, which matches the guide's validated version), then **`brew pin varlock`** so `brew upgrade` won't silently move it. Review varlock release notes / proxy breaking changes before ever running `brew unpin && brew upgrade varlock`. A chezmoi `run_onchange_` check can assert the pinned version (Phase 1, optional).

### D3 — Bitwarden Secrets Manager access
Secrets Manager is a **separate product** from the Password Manager. Verify in the web vault that your personal plan exposes **Secrets Manager** (free individual tier or paid) and that you can create a **machine account** with a **read-only** access token. If not available, personal API secrets stay on Keychain too, and only **SSH + git-identity** parts of this guide apply for now.

> ✅ **DECIDED (validated 2026-07-22):** Secrets Manager **is available** on the personal account (US region, `vault.bitwarden.com`). Full Varlock personal-secrets flow (Phases 1–6) is unblocked.

---

## 2. How the architecture maps onto our 3 layers

| Guide concept | Our layer | Where |
|---|---|---|
| Install & pin `bws`, `bitwarden-desktop` | **Home Manager** | `home/programs/secrets.nix` (new), `home/packages-darwin.nix` |
| Install & pin `varlock` (non-nix) | **Homebrew** (`brew install varlock` + `brew pin`) | see Phase 1 |
| macOS `--sandbox` launch wrapper (`ai`/`agent`) | **Home Manager** shell function OR chezmoi script | `home/programs/secrets.nix` or `chezmoi/dot_local/bin/` |
| `~/.ssh/config` public-key selectors, `IdentitiesOnly`, `ForwardAgent no` | **Chezmoi** (mutable, templated) | `chezmoi/dot_ssh/config.tmpl` (rewrite) |
| `~/.ssh/public/*.pub` files | **Chezmoi** (non-secret) | `chezmoi/dot_ssh/public/` (new) |
| Git identity via `includeIf gitdir` | **Home Manager** base + **Chezmoi** identity files | `home/programs/git.nix`, `chezmoi/dot_config/gitconfigs/` |
| Per-project `.env.schema` / `.env.local` | **Not** dotfiles — lives in each repo, kept local via `.git/info/exclude` | project working dirs |
| Remove `keyring`→plaintext rendering | **Chezmoi** | delete/retire the `*.tmpl` keyring lines (§3) |

**Guiding rule (unchanged from your README):** one file, one owner. Non-secret config → Home Manager/Chezmoi. Secrets → **never rendered to plaintext on disk** anymore; they resolve at request-time through Varlock (personal) or remain Keychain-gated (work).

---

## 3. Secret inventory → target mapping

Current `keyring` usages (all render **plaintext to disk** today — the gap Varlock closes):

| Secret (keyring service) | Rendered into | Trust | Guide category | Target |
|---|---|---|---|---|
| `bb9-api-key` | `~/.bb9/env` `OPENAI_API_KEY` | work | **A** (HTTPS API) | Keychain (unchanged) *or* an employer SM; proxy `@proxy(domain=…)` |
| `litellm-api-key` | `~/.claude/settings.json` `ANTHROPIC_AUTH_TOKEN` | work | **A** | Keychain (unchanged) *or* an employer SM |
| `work-genai-base-url` | codex/codewiki/claude base_url | work | **B** (public-ish URL, not a credential) | Move to **non-secret** chezmoi/HM config |
| `work-email` | `gitconfigs/Work` email | work | **B** (not a secret) | Move to **non-secret** chezmoi data |
| `gitlab-pat-localhost` | `~/.config/glab-cli/config.yml` | work | **A** | Keychain (unchanged) *or* an employer SM |
| `multica-token` | `~/.multica/config.json` | work | **A** | Keychain (unchanged) *or* an employer SM |
| `work-ca-cert-path` | `~/.zshenv`, `zsh/local.zsh` SSL vars | work | **B** (a *path*, not a secret) | Move to **non-secret** config (see §3.1) |

**Personal** API secrets (e.g. `OPENAI_API_KEY` for personal projects, GitHub bot tokens) — none are in chezmoi today; these are the natural first citizens of **Bitwarden Secrets Manager + Varlock**.

### 3.1 The corporate CA is **not a secret** — de-classify it
`work-ca-cert-path` just points at a CA bundle; the bundle itself is a public corporate CA (already at `/etc/nix/ca-bundle-work.crt`). Replace the keyring lookup with a plain, non-secret path so `chezmoi apply` never needs Keychain for it:

```zsh
# was: CA={{ keyring "work-ca-cert-path" "yamer003" }}
CA="/etc/nix/ca-bundle-work.crt"   # non-secret merged public+corporate bundle
```

This alone removes a Keychain dependency and one `chezmoi apply` failure mode.

---

## 4. SSH: key files → Bitwarden SSH Agent

Current key files and where they're selected (`chezmoi/dot_ssh/config.tmpl`):

| Key file | Used for | Trust | Migrate to |
|---|---|---|---|
| `~/.ssh/id_ed25519` | `github.com` | personal | Bitwarden SSH item `github-personal-m3pro` |
| `~/.ssh/id_ed25519_github_private` | `personal-github-projects` (dotfiles remote) | personal | Bitwarden SSH item (same or second personal key) |
| `~/.ssh/id_rsa_msc` | `msc-ado-projects` (Azure DevOps) | **work** | Keep file / employer-sanctioned store (**not** personal BW) |
| `~/.ssh/id_rsa` | `192.168.0.5` work box | **work** | Keep file / employer-sanctioned store |

Target `~/.ssh/config` pattern (personal hosts) — public-key selector + strict identity:

```sshconfig
Host *
    ForwardAgent no
    AddKeysToAgent no

Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/public/github-personal.pub
    IdentitiesOnly yes
    ForwardAgent no
```

- `~/.ssh/public/github-personal.pub` is **public** → safe in chezmoi.
- Private key lives only in Bitwarden; the desktop app's SSH Agent signs.
- Remotes switch to the alias: `git remote set-url origin git@github-personal:yehia2amer/REPO.git`.
- **Work keys are left as files for now** (D1) — do not move them to personal Bitwarden.

---

## 5. Git identity: machine-based → `gitdir`-based

Today identity is chosen by **machine** (`local.gitconfig.tmpl` keyed on `MacBookProM3`). The guide's model is **location-based**, which is more robust for mixed personal/work work-trees:

```
~/src/personal/   → ~/.gitconfig-personal  (name/email = personal)
~/src/work/       → ~/.gitconfig-work       (name/email = work; email currently from keyring work-email → move to plain file)
```

`home/programs/git.nix` gains:
```nix
programs.git.settings.user.useConfigOnly = true;   # force explicit identity
programs.git.settings.includeIf."gitdir:~/src/personal/".path = "~/.gitconfig-personal";
programs.git.settings.includeIf."gitdir:~/src/work/".path     = "~/.gitconfig-work";
```
The two identity files are chezmoi-managed (work email is **not** secret — inline it, drop the keyring call).

---

## 6. Phased migration runbook

Each phase is independently shippable and reversible. **Do not** proceed to the next phase until the current one's validation passes. Nothing here deletes an old credential until its replacement is verified.

### Phase 0 — Human checkpoints (no agent) 🔴
Outside any AI session, in a trusted terminal:
1. **Bitwarden account hardening** (guide §4.A): unique master password; FIDO2/WebAuthn MFA; recovery code offline; short vault timeout; timeout action = **Lock**; SSH Agent = **Always authorize**.
2. Confirm **Secrets Manager** access (D3) and create machine account **`varlock-personal-m3pro`**, `Can read` only, scoped to a first pilot project. Copy the access token **once**.
3. `varlock encrypt` the token → save the `varlock("local:…")` expression (Secure Enclave-backed). The token itself is never stored plaintext, never pasted into chat.
4. Decide **D1** and **D2**.

**Rollback:** none needed (no machine changes).

### Phase 1 — Tooling, declared in dotfiles
- **Home Manager** — new `home/programs/secrets.nix`:
  ```nix
  { pkgs, lib, ... }: {
    home.packages = with pkgs; [ bws ]          # Secrets Manager CLI (pinned via flake.lock)
      ++ lib.optionals pkgs.stdenv.isDarwin [ ]; # bitwarden-desktop optional via nix or brew cask
  }
  ```
  Import it from `home/default.nix`.
- **Bitwarden desktop** — install (`brew install --cask bitwarden` *or* nix `bitwarden-desktop`), enable **SSH Agent** in settings.
- **varlock** — via Homebrew (decided, D2, **done**): `brew install varlock` (1.13.0) + `brew pin varlock`. Optional `run_onchange_` chezmoi script asserting `varlock --version` matches the pin.
- **Validation:** `bws --version` (2.1.0), `varlock --version` (matches pin), Bitwarden desktop SSH Agent socket present.

**Rollback:** remove `secrets.nix` import + `darwin-rebuild switch`; `brew uninstall`.

### Phase 2 — SSH → Bitwarden SSH Agent (personal only)
1. In Bitwarden desktop, create SSH-key items for personal keys; register **public** keys with GitHub.
2. `mkdir -p ~/.ssh/public && chmod 700 ~/.ssh ~/.ssh/public`; add `*.pub` (chezmoi `dot_ssh/public/`).
3. Rewrite `chezmoi/dot_ssh/config.tmpl`: add `github-personal` alias (public-key `IdentityFile`, `IdentitiesOnly yes`, `ForwardAgent no`); **leave work hosts untouched**.
4. `chezmoi apply`, then test: `ssh -T git@github-personal` → authenticates via agent.
5. Only after success: `git remote set-url` personal repos to the alias.
6. Keep the old `~/.ssh/id_ed25519*` files until a few days of stable use, then remove the **files** (keys remain in Bitwarden).

**Validation (guide §16):** `ssh -T git@github-personal` works; `grep -RIl 'BEGIN .*PRIVATE KEY' ~/.ssh` returns nothing for migrated personal keys.
**Rollback:** restore key files from backup (`/Volumes/SMB/MacBackup/19Jul2026/.ssh`), revert `config.tmpl`.

### Phase 3 — Git identity → `gitdir`
1. Create `~/src/personal/` and `~/src/work/`; move (or clone) repos accordingly.
2. Add `useConfigOnly` + two `includeIf` blocks to `home/programs/git.nix`; add `~/.gitconfig-personal` / `~/.gitconfig-work` via chezmoi (inline the work email, drop `keyring "work-email"`).
3. `darwin-rebuild switch && chezmoi apply`.
4. **Validation:** in a `~/src/personal` repo `git config user.email` = personal; in `~/src/work` = work; a bare repo outside both **errors** (thanks to `useConfigOnly`).

**Rollback:** revert `git.nix` + remove identity files.

### Phase 4 — Pilot one project on Varlock (personal)
In a **dedicated clone** (guide §7):
```bash
mkdir -p ~/agent-workspaces
git clone --no-hardlinks ~/src/personal/<repo> ~/agent-workspaces/<repo>
cd ~/agent-workspaces/<repo>
git config remote.origin.pushurl DISABLED
printf '.env\n.env.*\n!.env.example\n.env.schema\n.varlock-proxy/\n' >> .git/info/exclude
```
Author `.env.schema` (categories A/B/C from §10–11 of the source guide), `.env.local` with the `varlock("local:…")` token. Validate **without revealing**:
```bash
varlock proxy rules      # exact domains, strict egress, token internal+omitted
```
Launch the agent (macOS):
```bash
env -u SSH_AUTH_SOCK -u BW_SESSION -u BWS_ACCESS_TOKEN -u BITWARDENCLI_APPDATA_DIR \
  varlock proxy run --sandbox -- <agent-command>
```
**Validation (guide §16):** inside sandbox `SSH_AUTH_SOCK` empty; `printf '%s' "$OPENAI_API_KEY"` prints a **placeholder**; `curl https://example.com` blocked; `varlock proxy audit` shows decisions, no secret values.
**Rollback:** `varlock proxy stop --all`; delete the workspace.

### Phase 5 — Retire `keyring`→plaintext rendering
Per-secret, only after a replacement path exists:
- **Non-secrets** (`work-genai-base-url`, `work-email`, `work-ca-cert-path`): inline as plain config in chezmoi (removes Keychain dependency + `chezmoi apply` failures). *(Do this first — low risk, immediately fixes the current apply errors.)*
- **Personal API secrets:** move to Bitwarden SM, consume via Varlock in the relevant project (not rendered to `~`).
- **Work API secrets** (`bb9-api-key`, `litellm-api-key`, `gitlab-pat-localhost`, `multica-token`): per **D1**, keep on Keychain (unchanged) **or** move to an employer-sanctioned SM. Do **not** put in personal Bitwarden.
- Remove each retired `{{ keyring … }}` line; update `.chezmoiignore` if a whole file is dropped.

**Validation:** `chezmoi apply` runs clean with **no** keyring errors; `find ~ -name '.env' -o -name 'env' | xargs grep -l 'sk-\|token'` (adapted) finds no plaintext personal secrets.
**Rollback:** `git revert` the chezmoi change; the Keychain entries were never deleted.

### Phase 6 — Daily workflow + acceptance
- Add a shell wrapper (Home Manager) so the routine command is memorable:
  ```bash
  ai <agent-command>   # = env -u SSH_AUTH_SOCK … varlock proxy run --sandbox -- <agent-command>
  ```
- Walk the guide **§18 acceptance checklist**; check off each item for the personal boundary.

---

## 7. Concrete file-by-file change list (for later PRs)

| File | Change |
|---|---|
| `home/programs/secrets.nix` (new) | add `bws`; optional `bitwarden-desktop`; `ai`/`agent` wrapper function |
| `home/default.nix` | import `./programs/secrets.nix` |
| `home/packages-darwin.nix` | (optional) `bitwarden-desktop` if not via brew |
| `home/programs/git.nix` | `useConfigOnly = true` + two `includeIf gitdir` blocks |
| `chezmoi/dot_ssh/config.tmpl` | add personal `Host *-personal` aliases (public-key selectors); keep work hosts |
| `chezmoi/dot_ssh/public/*.pub` (new) | public keys only |
| `chezmoi/dot_config/gitconfigs/{Personal,Work}` | inline work email (drop `keyring`), align with `gitdir` model |
| `chezmoi/dot_zshenv.tmpl`, `dot_config/zsh/local.zsh.tmpl` | replace `keyring "work-ca-cert-path"` with plain path |
| `chezmoi/dot_codex/*`, `dot_codewiki/*`, `dot_claude/*`, `dot_bb9/*`, `dot_multica/*`, `dot_config/glab-cli/*` | per D1: keep Keychain, or move to SM/Varlock; drop plaintext where possible |
| `chezmoi/run_onchange_assert-varlock-version.sh.tmpl` (new) | fail if `varlock --version` ≠ pin |

---

## 8. Guardrails carried over from the source guide

- **Never** launch an agent with `varlock run …` (injects real values) or un-sandboxed `varlock proxy run …`.
- **Never** give an agent `BW_SESSION`, `BWS_ACCESS_TOKEN`, master password, `SSH_AUTH_SOCK`, or private keys.
- **Never** `@proxy=passthrough` a production credential.
- Exact `@proxy(domain=…)`, narrow `path`/`method`, `egress="strict"`.
- Version-pin varlock; review proxy breaking changes before bumping.
- Incident response: `varlock proxy stop --all` → revoke token/creds → investigate (guide §17).

---

## 9. Open decisions (fill in, then we execute)

- [ ] **D1** work-secret backend: **DECIDED → personal → Bitwarden, work → Keychain (unchanged)**
- [ ] **D2** varlock pin: **DONE → Homebrew `1.13.0` + `brew pin varlock`**
- [ ] **D3** Secrets Manager available on personal account? **DECIDED → yes (US region)**
- [ ] Approve Phase 0 human checkpoints
- [ ] Approve Phase 1 tooling declarations

Once D1–D3 are answered, the low-risk quick win is **Phase 5's non-secret de-classification** (fixes today's `chezmoi apply` keyring errors immediately), then Phases 1→2→3→4 in order.
