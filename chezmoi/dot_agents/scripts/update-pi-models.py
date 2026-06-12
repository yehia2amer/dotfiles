#!/usr/bin/env python3
"""
Fetches all available models from the GenAI LiteLLM proxy and updates
~/.pi/agent/models.json with full details (context window, max output tokens,
vision, reasoning, costs).

Strategy (in priority order):
  0. Internal management API (richest data, requires Azure AD JWT)
     - Auto-extracts JWT from Chrome via AppleScript (macOS)
     - Or pass --jwt TOKEN / set GENAI_JWT env var
  1. LiteLLM /model/info (rich metadata, may be blocked by WAF)
  2. LiteLLM /models (IDs only) + litellm's model_prices JSON for metadata

Usage:
  python3 ~/.agents/scripts/update-pi-models.py           # update models.json (auto-gets JWT from Chrome)
  python3 ~/.agents/scripts/update-pi-models.py --dry-run  # preview only
  python3 ~/.agents/scripts/update-pi-models.py --diff     # show what changed
  python3 ~/.agents/scripts/update-pi-models.py --jwt TOKEN  # use internal API with explicit JWT
  python3 ~/.agents/scripts/update-pi-models.py --no-chrome  # skip Chrome JWT extraction

Requires: OPENAI_API_KEY env var set to the Bearer token for the LiteLLM proxy.
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

# ── Configuration ─────────────────────────────────────────────────────────────

BASE_URL = subprocess.run(
    ["security", "find-generic-password", "-a", "yamer003", "-s", "work-genai-base-url", "-w"],
    capture_output=True, text=True,
).stdout.strip()

INTERNAL_API_URL = subprocess.run(
    ["security", "find-generic-password", "-a", "yamer003", "-s", "work-genai-internal-url", "-w"],
    capture_output=True, text=True,
).stdout.strip()

TEAM_UUID = "bc4dbd8d-aebe-4c50-8278-bb8606f00d29"

API_KEY_ENV = "OPENAI_API_KEY"
MODELS_JSON = os.path.expanduser("~/.pi/agent/models.json")

# Models to skip (meta/utility endpoints, not usable as chat models)
SKIP_MODELS = {"all-proxy-models"}

# Model types to include from internal API
CHAT_TYPES = {"chat", "responses", "computer_use"}

# Modes to include from /model/info
CHAT_MODES = {"chat"}

# Non-chat models to always include anyway (useful utility models)
FORCE_INCLUDE = set()

# Other providers to preserve in models.json
OTHER_PROVIDERS = {
    "github-copilot": {
        "modelOverrides": {
            "claude-opus-4.6": {
                "contextWindow": 200000
            }
        }
    }
}

# URL for litellm's model pricing/capabilities database
LITELLM_PRICES_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

# GenAI web app URL (for opening Chrome if needed)
GENAI_WEB_URL = "https://genai-sharedservice-emea.pwcinternal.com/genai"

# Non-chat model patterns to exclude when using /models fallback (Strategy 2)
NON_CHAT_PATTERNS = {
    "embed", "embedding", "tts", "whisper", "transcribe", "rerank",
    "imagen", "image", "dall-e", "canvas", "realtime", "audio",
}

# ── Helpers ───────────────────────────────────────────────────────────────────


def get_jwt_from_chrome() -> str | None:
    """Extract the GenAI JWT (id_token) from Chrome's localStorage via AppleScript.

    The GenAI SPA stores tokens in localStorage under the key 'tokens'.
    The id_token (not access_token) has aud=bc345ad8-... which the API expects.
    Returns None if Chrome isn't open or the page isn't loaded.
    """
    import platform
    if platform.system() != "Darwin":
        return None

    # First try to get tokens from an existing tab
    token = _extract_token_from_chrome()
    if token:
        return token

    # No tab found — open the GenAI page and wait for login
    print("  Opening GenAI page in Chrome for authentication...")
    _open_genai_in_chrome()

    # Wait for the page to load and tokens to appear (up to 60s for SSO)
    import time
    for i in range(12):  # 12 * 5s = 60s
        time.sleep(5)
        token = _extract_token_from_chrome()
        if token:
            return token
        if i == 0:
            print("  Waiting for authentication to complete...")

    return None


def _extract_token_from_chrome() -> str | None:
    """Try to extract the id_token from a Chrome tab with the GenAI page."""
    import subprocess as sp
    script = '''
    tell application "Google Chrome"
        set tabList to every tab of every window
        repeat with t in tabList
            repeat with aTab in t
                if URL of aTab contains "genai-sharedservice-emea.pwcinternal.com" then
                    return execute aTab javascript "localStorage.getItem('tokens')"
                end if
            end repeat
        end repeat
        return "NO_TAB"
    end tell
    '''
    try:
        result = sp.run(["osascript", "-e", script], capture_output=True, text=True, timeout=10)
        raw = result.stdout.strip()
        if not raw or raw == "NO_TAB" or raw == "missing value":
            return None

        import json
        data = json.loads(raw)
        id_token = data.get("id_token", "")
        if not id_token:
            return None

        # Verify it's not expired
        import base64, time
        payload_b64 = id_token.split(".")[1]
        payload_b64 += "=" * (4 - len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))

        exp = payload.get("exp", 0)
        if exp < time.time() + 60:  # expired or <1 min remaining
            return None

        remaining = (exp - time.time()) / 60
        print(f"  ✓ Got JWT from Chrome ({remaining:.0f} min remaining)")
        return id_token
    except Exception:
        return None


def _open_genai_in_chrome():
    """Open the GenAI page in Chrome."""
    import subprocess as sp
    script = f'''
    tell application "Google Chrome"
        activate
        open location "{GENAI_WEB_URL}"
    end tell
    '''
    sp.run(["osascript", "-e", script], capture_output=True, timeout=5)


def fetch_internal_models(internal_url: str, team_uuid: str, jwt: str) -> list[dict] | None:
    """Fetch models from the internal management API (Strategy 0). Returns None on failure."""
    url = f"{internal_url}/genai/api/v1/models/?team_uuid={team_uuid}"
    headers = {
        "Authorization": f"Bearer {jwt}",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data.get("items", [])
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return None
        raise
    except Exception:
        return None


def fetch_model_info(base_url: str, api_key: str) -> list[dict] | None:
    """Fetch detailed model info from /model/info endpoint. Returns None if blocked."""
    url = f"{base_url}/model/info"
    req = urllib.request.Request(url, headers={"Authorization": api_key})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data["data"]
    except urllib.error.HTTPError as e:
        if e.code == 403:
            return None
        raise


def fetch_model_list(base_url: str, api_key: str) -> list[str]:
    """Fetch model IDs from /models endpoint (OpenAI-compatible, always works)."""
    url = f"{base_url}/models"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    return [m["id"] for m in data.get("data", [])]


def fetch_litellm_prices() -> dict:
    """Fetch litellm's model prices/capabilities database from GitHub."""
    req = urllib.request.Request(LITELLM_PRICES_URL)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"  ⚠ Could not fetch litellm prices: {e}")
        return {}


def to_per_million(cost) -> float:
    """Convert cost value to per-million-token cost, rounded.

    Handles both:
    - per-token floats from /model/info (multiply by 1M)
    - per-1M-token strings/floats from internal API (use as-is)
    """
    if cost is None:
        return 0
    val = float(cost)
    # If it's a tiny number (per-token), convert to per-million
    if val > 0 and val < 0.01:
        return round(val * 1_000_000, 4)
    return round(val, 4)


def to_per_million_from_token(cost_per_token) -> float:
    """Convert per-token cost to per-million-token cost, rounded."""
    if cost_per_token is None:
        return 0
    return round(float(cost_per_token) * 1_000_000, 4)


def build_entry_from_internal(model: dict) -> dict:
    """Build a pi models.json entry from internal API model data."""
    model_name = model["model_name"]
    entry = {"id": model_name}

    max_input = model.get("max_input_tokens") or 128000
    max_output = model.get("max_output_tokens") or 16384

    if model.get("supports_vision") is True:
        entry["input"] = ["text", "image"]

    # Detect reasoning models by name pattern (o1, o3, o4)
    base_name = model_name.split(".")[-1] if "." in model_name else model_name
    if re.match(r"^o[134]", base_name):
        entry["reasoning"] = True

    if max_input != 128000:
        entry["contextWindow"] = max_input

    if max_output != 16384:
        entry["maxTokens"] = max_output

    # Costs from internal API are already per-1M-tokens as strings
    input_cost = float(model.get("input_cost_per_1M_tokens") or 0)
    output_cost = float(model.get("output_cost_per_1M_tokens") or 0)

    cost = {
        "input": round(input_cost, 4),
        "output": round(output_cost, 4),
        "cacheRead": 0,
        "cacheWrite": 0,
    }
    if any(v > 0 for v in cost.values()):
        entry["cost"] = cost

    return entry


def build_model_entry(model_name: str, info: dict) -> dict:
    """Build a pi models.json model entry from LiteLLM /model/info data."""
    mi = info.get("model_info", {})

    max_input = mi.get("max_input_tokens") or mi.get("max_tokens") or 128000
    max_output = mi.get("max_output_tokens") or 16384

    supports_vision = mi.get("supports_vision")
    supports_reasoning = mi.get("supports_reasoning")

    input_types = ["text"]
    if supports_vision is True:
        input_types.append("image")

    cost = {
        "input": to_per_million_from_token(mi.get("input_cost_per_token")),
        "output": to_per_million_from_token(mi.get("output_cost_per_token")),
        "cacheRead": to_per_million_from_token(mi.get("cache_read_input_token_cost")),
        "cacheWrite": to_per_million_from_token(mi.get("cache_creation_input_token_cost")),
    }

    entry = {"id": model_name}

    if supports_reasoning is True:
        entry["reasoning"] = True

    if "image" in input_types:
        entry["input"] = input_types

    if max_input != 128000:
        entry["contextWindow"] = max_input

    if max_output != 16384:
        entry["maxTokens"] = max_output

    if any(v > 0 for v in cost.values()):
        entry["cost"] = cost

    return entry


def build_model_entry_from_prices(model_id: str, prices_db: dict) -> dict:
    """Build a pi models.json entry from model ID + litellm prices database."""
    entry = {"id": model_id}

    lookup_keys = _get_price_lookup_keys(model_id)

    mi = None
    for key in lookup_keys:
        if key in prices_db:
            mi = prices_db[key]
            break

    if mi is None:
        return entry

    max_input = mi.get("max_input_tokens") or mi.get("max_tokens") or 128000
    max_output = mi.get("max_output_tokens") or 16384

    if mi.get("supports_vision") is True:
        entry["input"] = ["text", "image"]

    if mi.get("supports_reasoning") is True:
        entry["reasoning"] = True

    if max_input != 128000:
        entry["contextWindow"] = max_input

    if max_output != 16384:
        entry["maxTokens"] = max_output

    cost = {
        "input": to_per_million_from_token(mi.get("input_cost_per_token")),
        "output": to_per_million_from_token(mi.get("output_cost_per_token")),
        "cacheRead": to_per_million_from_token(mi.get("cache_read_input_token_cost")),
        "cacheWrite": to_per_million_from_token(mi.get("cache_creation_input_token_cost")),
    }
    if any(v > 0 for v in cost.values()):
        entry["cost"] = cost

    return entry


def _get_price_lookup_keys(model_id: str) -> list[str]:
    """Generate possible keys to look up in litellm's prices DB for a proxy model ID."""
    keys = [model_id]

    parts = model_id.split(".")
    provider_prefixes = {"openai", "azure", "vertex_ai", "bedrock"}
    region_prefixes = {"global", "eu"}

    if len(parts) >= 2 and parts[0] in provider_prefixes:
        provider = parts[0]
        remainder = ".".join(parts[1:])

        # Strip region prefix if present
        if len(parts) >= 3 and parts[1] in region_prefixes:
            remainder = ".".join(parts[2:])

        keys.append(f"{provider}/{remainder}")
        keys.append(remainder)

        # Try without version suffix
        base = re.sub(r"-\d{4}-\d{2}-\d{2}$", "", remainder)
        if base != remainder:
            keys.append(f"{provider}/{base}")
            keys.append(base)

        # For bedrock models like "bedrock.anthropic.claude-sonnet-4-5"
        if provider == "bedrock" and "." in remainder:
            sub_parts = remainder.split(".", 1)
            keys.append(f"{sub_parts[0]}/{sub_parts[1]}")

        # For vertex_ai anthropic models
        if provider == "vertex_ai" and remainder.startswith("anthropic."):
            sub_parts = remainder.split(".", 1)
            keys.append(f"vertex_ai/{sub_parts[0]}/{sub_parts[1]}")
            keys.append(f"{sub_parts[0]}/{sub_parts[1]}")

    return keys


def is_chat_model_by_name(model_id: str) -> bool:
    """Heuristic: determine if a model ID is likely a chat model."""
    lower = model_id.lower()
    for pattern in NON_CHAT_PATTERNS:
        if pattern in lower:
            return False
    return True


def build_models_json(model_entries: list[dict]) -> dict:
    """Build the full models.json structure."""
    providers = dict(OTHER_PROVIDERS)
    providers["litellm"] = {
        "baseUrl": BASE_URL,
        "api": "openai-completions",
        "apiKey": API_KEY_ENV,
        "authHeader": True,
        "models": model_entries,
    }
    return {"providers": providers}


def show_diff(old_path: str, new_content: dict):
    """Show what models were added/removed."""
    try:
        with open(old_path) as f:
            old = json.load(f)
        old_ids = {m["id"] for m in old.get("providers", {}).get("litellm", {}).get("models", [])}
    except (FileNotFoundError, json.JSONDecodeError):
        old_ids = set()

    new_ids = {m["id"] for m in new_content["providers"]["litellm"]["models"]}

    added = sorted(new_ids - old_ids)
    removed = sorted(old_ids - new_ids)

    if added:
        print(f"\n  ✚ Added ({len(added)}):")
        for m in added:
            print(f"    + {m}")
    if removed:
        print(f"\n  ✖ Removed ({len(removed)}):")
        for m in removed:
            print(f"    - {m}")
    if not added and not removed:
        print("\n  No model additions or removals (details may have been updated).")


# ── Main ──────────────────────────────────────────────────────────────────────


def main():
    dry_run = "--dry-run" in sys.argv
    show_changes = "--diff" in sys.argv or dry_run

    no_chrome = "--no-chrome" in sys.argv

    # Parse --jwt flag
    jwt = None
    if "--jwt" in sys.argv:
        idx = sys.argv.index("--jwt")
        if idx + 1 < len(sys.argv):
            jwt = sys.argv[idx + 1]
    if not jwt:
        jwt = os.environ.get("GENAI_JWT")

    # Auto-extract JWT from Chrome if not provided
    if not jwt and not no_chrome and INTERNAL_API_URL:
        jwt = get_jwt_from_chrome()

    api_key = os.environ.get(API_KEY_ENV)
    if not api_key and not jwt:
        print(f"ERROR: {API_KEY_ENV} environment variable not set", file=sys.stderr)
        sys.exit(1)

    entries = None

    # Strategy 0: Internal management API (richest data)
    if jwt and INTERNAL_API_URL:
        print(f"Fetching models from internal API ({INTERNAL_API_URL}) ...")
        items = fetch_internal_models(INTERNAL_API_URL, TEAM_UUID, jwt)
        if items is not None:
            print(f"  Received {len(items)} model entries")

            # Filter to chat/responses types and expand aliases
            chat_items = []
            for m in items:
                mtype = m.get("model_type", "")
                if mtype in CHAT_TYPES:
                    chat_items.append(m)
                    # Also include aliases as separate entries
                    for alias in m.get("aliases", []):
                        if alias.get("model_type", "") in CHAT_TYPES:
                            # Merge parent metadata into alias
                            merged = dict(m)
                            merged.update({k: v for k, v in alias.items() if v is not None})
                            chat_items.append(merged)

            # Deduplicate by model_name
            seen = set()
            deduped = []
            for m in chat_items:
                name = m.get("model_name", "")
                if name not in seen and name not in SKIP_MODELS:
                    seen.add(name)
                    deduped.append(m)

            print(f"  Chat/responses models (with aliases): {len(deduped)}")

            entries = sorted(
                [build_entry_from_internal(m) for m in deduped],
                key=lambda e: e["id"],
            )
        else:
            print("  ⚠ Internal API returned 401/403 (JWT expired?). Trying other strategies...")

    # Strategy 1: LiteLLM /model/info
    if entries is None and api_key:
        print(f"Fetching model details from {BASE_URL}/model/info ...")
        raw_models = fetch_model_info(BASE_URL, api_key)

        if raw_models is not None:
            print(f"  Received {len(raw_models)} model entries (including multi-region duplicates)")

            seen = set()
            unique_models = []
            for m in raw_models:
                name = m.get("model_name", "")
                if name in seen or name in SKIP_MODELS:
                    continue
                seen.add(name)
                unique_models.append(m)

            chat_models = []
            for m in unique_models:
                name = m.get("model_name", "")
                mode = m.get("model_info", {}).get("mode")
                if mode in CHAT_MODES or name in FORCE_INCLUDE:
                    chat_models.append(m)

            print(f"  Unique models: {len(unique_models)}")
            print(f"  Chat models:   {len(chat_models)}")

            entries = sorted(
                [build_model_entry(m["model_name"], m) for m in chat_models],
                key=lambda e: e["id"],
            )
        else:
            print("  ⚠ /model/info blocked (WAF 403). Falling back to /models endpoint...")

    # Strategy 2: /models + litellm prices DB
    if entries is None and api_key:
        model_ids = fetch_model_list(BASE_URL, api_key)
        print(f"  Received {len(model_ids)} model IDs from /models")

        chat_ids = [
            mid for mid in model_ids
            if mid not in SKIP_MODELS and is_chat_model_by_name(mid)
        ]
        print(f"  Chat models (heuristic): {len(chat_ids)}")

        print("  Fetching litellm model prices database...")
        prices_db = fetch_litellm_prices()
        if prices_db:
            print(f"  Loaded {len(prices_db)} entries from litellm prices DB")
        else:
            print("  ⚠ No prices DB available, entries will have minimal metadata")

        entries = sorted(
            [build_model_entry_from_prices(mid, prices_db) for mid in chat_ids],
            key=lambda e: e["id"],
        )

    if entries is None:
        print("ERROR: All strategies failed. Cannot fetch models.", file=sys.stderr)
        sys.exit(1)

    result = build_models_json(entries)

    if show_changes:
        show_diff(MODELS_JSON, result)

    output = json.dumps(result, indent=2) + "\n"

    if dry_run:
        print(f"\n[DRY RUN] Would write {len(entries)} models to {MODELS_JSON}")
    else:
        os.makedirs(os.path.dirname(MODELS_JSON), exist_ok=True)
        with open(MODELS_JSON, "w") as f:
            f.write(output)
        print(f"\n✓ Updated {MODELS_JSON} with {len(entries)} chat models")

    # Summary by provider prefix
    prefixes = {}
    for e in entries:
        prefix = e["id"].split(".")[0]
        prefixes[prefix] = prefixes.get(prefix, 0) + 1
    print("\nModels by provider:")
    for prefix in sorted(prefixes):
        print(f"  {prefix:20s} {prefixes[prefix]:3d}")


if __name__ == "__main__":
    main()
