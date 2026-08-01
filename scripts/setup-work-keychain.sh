#!/usr/bin/env bash
# Populate the macOS login Keychain with the WORK secrets/config values that the
# dotfiles read via chezmoi's keyring() and via `security` in scripts.
#
# Values are entered through `security`'s OWN hidden prompt — never passed as a
# command-line argument and never stored in shell history.
#
# The keychain "account" is the current user, to match the templates/scripts.
#
# Usage:  bash scripts/setup-work-keychain.sh
# See docs/work-machine-bootstrap.md.
set -uo pipefail
ACCOUNT="${USER}"

# service|description  (service names must match the dotfiles exactly)
ITEMS=(
  "work-email|Work git identity email"
  "work-genai-base-url|GenAI LiteLLM proxy base URL (e.g. https://host/v1)"
  "work-genai-internal-url|GenAI internal management API URL"
  "work-genai-web-url|GenAI web portal URL (Chrome SSO tab match)"
  "work-vault-url|HashiCorp Vault URL"
  "work-vault-namespace|Vault namespace"
  "work-dns-check-domain|Internal DNS check domain"
  "work-ca-root-cert-path|Path to corporate root CA (used by scripts)"
  "litellm-api-key|LiteLLM proxy bearer token"
  "bb9-api-key|bb9 OpenAI-compatible API key"
  "multica-token|multica token"
  "gitlab-pat-localhost|GitLab PAT (localhost proxy)"
  "veracode-api-key-id|Veracode API key id"
  "veracode-api-key-secret|Veracode API key secret"
  "cloudflare-account-id|Cloudflare account id"
  "cloudflare-api-token|Cloudflare API token"
  "github-token-nushell|GitHub token used by nushell scripts"
  "claude-code-oauth-token|Claude Code OAuth token"
  "opencode-server-password|OpenCode server password"
)

echo "Populating login keychain for account: $ACCOUNT"
echo "For each item: y = enter value (hidden), anything else = skip."
echo

for entry in "${ITEMS[@]}"; do
  svc="${entry%%|*}"; desc="${entry#*|}"
  read -r -p "Set '${svc}' — ${desc}? [y/N] " yn
  case "$yn" in
    [Yy]*)
      # -w with no value → security prompts (hidden) and confirms; -U updates if exists.
      if security add-generic-password -U -a "$ACCOUNT" -s "$svc" -w; then
        echo "  stored ✓"
      else
        echo "  (aborted / unchanged)"
      fi
      ;;
    *) echo "  skipped" ;;
  esac
  echo
done

echo "Done. Verify one with:"
echo "  security find-generic-password -a \"$ACCOUNT\" -s work-email -w"
