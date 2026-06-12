---
description: Sync pi's model list with the PwC GenAI LiteLLM proxy. Use when told new models are available, when model details may have changed, or when the user says "update models", "sync models", or "refresh model list".
---

# Update Pi Models

Sync pi's model list with the PwC GenAI LiteLLM proxy.

## What it does

Queries the GenAI internal management API (or LiteLLM proxy as fallback) to fetch every available model with full details:
- Context window size
- Max output tokens
- Vision / reasoning support
- Per-token costs (input, output, cache read, cache write)

Filters to chat-capable models only (removes embeddings, image-gen, TTS, reranking, etc.) and writes the result to `~/.pi/agent/models.json`.

## Usage

Run the update script:

```bash
python3 ~/.agents/scripts/update-pi-models.py
```

### How it gets the token (automatic)

On macOS, the script **automatically extracts the JWT from Chrome**:
1. Looks for an open Chrome tab at `genai-sharedservice-emea.pwcinternal.com`
2. Reads `localStorage.tokens` → extracts the `id_token`
3. If no tab is found, opens the GenAI page and waits for SSO to complete

This means you just need to be logged into your Microsoft account in Chrome — no manual token copying needed.

### Options

| Flag | Description |
|------|-------------|
| _(none)_ | Auto-get JWT from Chrome, fetch models, update `~/.pi/agent/models.json` |
| `--dry-run` | Preview changes without writing |
| `--diff` | Show added/removed models and also write |
| `--jwt TOKEN` | Use an explicit JWT instead of Chrome extraction |
| `--no-chrome` | Skip Chrome JWT extraction, use LiteLLM proxy only |

### Requirements

- `OPENAI_API_KEY` env var must be set to the Bearer token for the LiteLLM proxy (fallback)
- Chrome with "Allow JavaScript from Apple Events" enabled (View > Developer menu)
- Active SSO session in Chrome for the GenAI portal

### Strategy priority

1. **Internal management API** (richest data: context window, costs, vision, function calling)
   - Uses Azure AD JWT extracted from Chrome automatically
2. **LiteLLM `/model/info`** (rich metadata, sometimes blocked by Imperva WAF)
3. **LiteLLM `/models`** + GitHub litellm prices DB (IDs only, metadata from public DB)

## When to use

- After being told new models are available on the proxy
- Periodically to pick up newly added models
- When model details (context window, pricing) may have changed
- When the user says "update models", "sync models", "refresh model list"

## What it preserves

- The `github-copilot` provider override (hardcoded in the script)
- To add more preserved providers, edit `OTHER_PROVIDERS` in the script

## Troubleshooting

- **"Allow JavaScript from Apple Events"** must be enabled in Chrome: View > Developer > Allow JavaScript from Apple Events
- **JWT expired**: The id_token lasts ~1 hour. If expired, the script opens the GenAI page in Chrome to trigger a fresh SSO login.
- **No Chrome/not macOS**: Use `--jwt TOKEN` to pass a token manually, or `--no-chrome` to use the LiteLLM proxy fallback.
- **WAF blocks /model/info**: Normal. The script falls back to `/models` + litellm prices DB.

## Script location

`~/.agents/scripts/update-pi-models.py`
