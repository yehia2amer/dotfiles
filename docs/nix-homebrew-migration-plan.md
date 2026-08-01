# Declarative Homebrew and nix-homebrew Migration

## Goal

Migrate Homebrew in two independently validated stages. nix-darwin owns the
intentional formulae and casks; nix-homebrew owns the Homebrew installation,
pinned taps, and narrow trust policy. Cleanup and Rosetta remain disabled.
`surreal` remains undeclared until its artifact host is available.

## Stage 0: baseline and rollback evidence

1. Activate the already-built current generation before changing ownership.
2. Capture installed formulae, casks, taps, tap metadata, pins, Homebrew
   configuration, trust-related environment, and a Brewfile under `/tmp`.
3. Preserve unrelated working-tree changes.
4. Register this document in `docs/dotfiles-inventory.csv`.

The baseline is local rollback evidence only. Brewfiles, credentials, secrets,
employer identifiers, and generated state must never be committed.

## Stage 1: nix-darwin package ownership

Create a dedicated Darwin Homebrew module and declare these formulae:

- `bitwarden-cli`
- `dnspyre`
- `freetonik/tap/textpod`
- `gimlet-io/capacitor/capacitor`
- `jundot/omlx/omlx`
- `livekit-cli`
- `mole`
- `multica-ai/tap/multica`
- `pi-coding-agent`
- `theykk/tap/git-switcher`
- `varlock`
- `veracode/tap/veracode-cli`
- `virtctl`

Declare these casks:

- `claude`
- `codex`
- `wouterdebie/tap/davit`
- `thaw`

Enable nix-darwin Homebrew for user `yamer003`. Disable activation auto-update
and upgrade, global auto-update, analytics, and environment hints. Keep cleanup
at `none`. Declare all existing taps and use the explicit clone target
`https://github.com/jundot/omlx` for `jundot/omlx`. Assert `varlock` is exactly
`1.13.0` after Homebrew activation and keep it pinned.

Do not declare or remove `abseil` or `rust` in this stage. Do not declare
`surreal`.

Validate the complete Darwin derivation and a no-link build, run all mandatory
secret scanners, commit, activate, verify packages and applications, and repeat
activation to prove idempotence.

## Stage 2: nix-homebrew ownership

Add non-flake inputs for Homebrew core/cask and every custom tap. Configure
nix-homebrew to migrate the existing `/opt/homebrew` installation once with
`autoMigrate = true`, disable Rosetta, use user `yamer003`, and make taps
immutable. Map official and custom taps to their exact repositories and derive
nix-darwin's tap list from `config.nix-homebrew.taps`.

Trust only these formulae:

- Textpod
- Capacitor
- oMLX
- Multica
- Surreal
- Git Switcher
- Veracode CLI

Trust only the Davit cask. Do not trust whole taps, and remove the stale formula
trust for Davit. Package ownership remains in nix-darwin.

After a successful migration activation, commit a follow-up change setting
`autoMigrate = false`. Validate and activate again to prove idempotence.

## Final removal and acceptance

After both stages pass, reconfirm that `abseil` and `rust` have no installed
dependents, then explicitly uninstall only those two formulae. Never use broad
cleanup or `brew autoremove`.

For each stage:

1. Evaluate the full Darwin system derivation.
2. Run `nix build --no-link .#darwinConfigurations.MacBookProM3.system`.
3. Run `prek run --all-files`; TruffleHog and Gitleaks must pass.
4. Commit with `--no-verify --no-gpg-sign` until signing is restored.
5. Activate and verify exact formulae, casks, taps, trust JSON, and the
   `varlock` pin.
6. Confirm `lk`, `omlx`, `coderabbit`, `varlock`, Bitwarden, Firefox, Raycast,
   and Davit launch or report versions.
7. Confirm repeated activation makes no Homebrew changes.

Rollback is a Git revert followed by `darwin-rebuild switch`. Because cleanup
is disabled, existing applications are preserved.
