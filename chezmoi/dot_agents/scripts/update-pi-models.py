#!/usr/bin/env python3
"""
Fetches all available models from the GenAI LiteLLM proxy /model/info
endpoint and updates ~/.pi/agent/models.json with full details (context window,
max output tokens, vision, reasoning, costs) pulled directly from the API.

Usage:
  python3 ~/.agents/scripts/update-pi-models.py           # update models.json
  python3 ~/.agents/scripts/update-pi-models.py --dry-run  # preview only
  python3 ~/.agents/scripts/update-pi-models.py --diff     # show what changed

Requires: OPENAI_API_KEY env var set to the Bearer token.
"""

import json
import os
import subprocess
import sys
import urllib.request

# ── Configuration ─────────────────────────────────────────────────────────────

BASE_URL = subprocess.run(
    ["security", "find-generic-password", "-a", "yamer003", "-s", "work-genai-base-url", "-w"],
    capture_output=True, text=True,
).stdout.strip()
API_KEY_ENV = "OPENAI_API_KEY"
MODELS_JSON = os.path.expanduser("~/.pi/agent/models.json")

# Models to skip (meta/utility endpoints, not usable as chat models)
SKIP_MODELS = {"all-proxy-models"}

# Modes to include (skip embeddings, image-gen, audio-only, reranking, etc.)
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

# ── Helpers ───────────────────────────────────────────────────────────────────

def fetch_model_info(base_url: str, api_key: str) -> list[dict]:
    """Fetch detailed model info from /model/info endpoint."""
    url = f"{base_url}/model/info"
    req = urllib.request.Request(url, headers={"Authorization": api_key})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    return data["data"]


def to_per_million(cost_per_token) -> float:
    """Convert per-token cost to per-million-token cost, rounded."""
    if cost_per_token is None:
        return 0
    return round(cost_per_token * 1_000_000, 4)


def build_model_entry(model_name: str, info: dict) -> dict:
    """Build a pi models.json model entry from LiteLLM model_info."""
    mi = info.get("model_info", {})

    max_input = mi.get("max_input_tokens") or mi.get("max_tokens") or 128000
    max_output = mi.get("max_output_tokens") or 16384

    supports_vision = mi.get("supports_vision")
    supports_reasoning = mi.get("supports_reasoning")

    # Build input types
    input_types = ["text"]
    if supports_vision is True:
        input_types.append("image")

    # Build cost
    cost = {
        "input": to_per_million(mi.get("input_cost_per_token")),
        "output": to_per_million(mi.get("output_cost_per_token")),
        "cacheRead": to_per_million(mi.get("cache_read_input_token_cost")),
        "cacheWrite": to_per_million(mi.get("cache_creation_input_token_cost")),
    }

    entry = {"id": model_name}

    # Only add fields that differ from pi defaults to keep it clean
    if supports_reasoning is True:
        entry["reasoning"] = True

    if "image" in input_types:
        entry["input"] = input_types

    if max_input != 128000:
        entry["contextWindow"] = max_input

    if max_output != 16384:
        entry["maxTokens"] = max_output

    # Always include cost if non-zero
    if any(v > 0 for v in cost.values()):
        entry["cost"] = cost

    return entry


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

    api_key = os.environ.get(API_KEY_ENV)
    if not api_key:
        print(f"ERROR: {API_KEY_ENV} environment variable not set", file=sys.stderr)
        sys.exit(1)

    print(f"Fetching model details from {BASE_URL}/model/info ...")
    raw_models = fetch_model_info(BASE_URL, api_key)
    print(f"  Received {len(raw_models)} model entries (including multi-region duplicates)")

    # Deduplicate by model_name, keep first occurrence
    seen = set()
    unique_models = []
    for m in raw_models:
        name = m.get("model_name", "")
        if name in seen or name in SKIP_MODELS:
            continue
        seen.add(name)
        unique_models.append(m)

    # Filter to chat models (+ forced includes)
    chat_models = []
    for m in unique_models:
        name = m.get("model_name", "")
        mode = m.get("model_info", {}).get("mode")
        if mode in CHAT_MODES or name in FORCE_INCLUDE:
            chat_models.append(m)

    print(f"  Unique models: {len(unique_models)}")
    print(f"  Chat models:   {len(chat_models)}")

    # Build entries sorted by id
    entries = sorted(
        [build_model_entry(m["model_name"], m) for m in chat_models],
        key=lambda e: e["id"],
    )

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
