#!/usr/bin/env bash
# Ensure every work Keychain item EXISTS so chezmoi's keyring() and the scripts
# resolve to "" instead of erroring. Missing items are created EMPTY; existing
# items are NEVER modified. Run this once on a fresh machine BEFORE `chezmoi
# apply` — it lets the full apply succeed with empty placeholders, and you fill
# in the real values later with scripts/setup-work-keychain.sh (or
# `security add-generic-password -U -a "$USER" -s <service> -w`).
#
# Usage:  bash scripts/ensure-work-keychain.sh
# See docs/work-machine-bootstrap.md.
set -uo pipefail
ACCOUNT="${USER}"

# All work services the dotfiles read (chezmoi keyring() + `security` in scripts).
SERVICES=(
  work-email
  work-genai-base-url
  work-genai-internal-url
  work-genai-web-url
  work-vault-url
  work-vault-namespace
  work-dns-check-domain
  work-ca-root-cert-path
  litellm-api-key
  bb9-api-key
  multica-token
  gitlab-pat-localhost
  veracode-api-key-id
  veracode-api-key-secret
  cloudflare-account-id
  cloudflare-api-token
  github-token-nushell
  claude-code-oauth-token
  opencode-server-password
)

created=0; kept=0
for svc in "${SERVICES[@]}"; do
  if security find-generic-password -a "$ACCOUNT" -s "$svc" >/dev/null 2>&1; then
    kept=$((kept + 1))
  elif security add-generic-password -a "$ACCOUNT" -s "$svc" -w "" 2>/dev/null; then
    echo "  created empty: $svc"
    created=$((created + 1))
  else
    echo "  !! failed to create: $svc" >&2
  fi
done

echo "done: ${created} created empty, ${kept} already present."
echo "Fill real values later:  bash scripts/setup-work-keychain.sh"
