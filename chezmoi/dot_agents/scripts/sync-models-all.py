#!/usr/bin/env python3
"""
Sync model metadata from the GenAI LiteLLM internal `/model/info` endpoint into:
- Pi      : ~/.pi/agent/models.json
- Codex   : ~/.codex/models_cache.json
- OpenCode: ~/.config/opencode/opencode.jsonc
- Claude  : ~/.claude/settings.json
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE_URL = subprocess.run(
    ["security", "find-generic-password", "-a", "yamer003", "-s", "work-genai-internal-url", "-w"],
    capture_output=True, text=True,
).stdout.strip()
PI_KEY_ENV = "OPENAI_API_KEY"
CLAUDE_KEY_ENV = "ANTHROPIC_AUTH_TOKEN"

PI_MODELS_JSON = Path.home() / ".pi/agent/models.json"
CODEX_MODELS_CACHE = Path.home() / ".codex/models_cache.json"
OPENCODE_JSONC = Path.home() / ".config/opencode/opencode.jsonc"
CLAUDE_SETTINGS_JSON = Path.home() / ".claude/settings.json"

SKIP_MODELS = {"all-proxy-models"}
CHAT_MODES = {"chat"}
FORCE_INCLUDE = set()

OTHER_PI_PROVIDERS = {
    "github-copilot": {
        "modelOverrides": {
            "claude-opus-4.6": {
                "contextWindow": 200000
            }
        }
    }
}


def load_json(path: Path, default=None):
    try:
        with path.open() as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {path}: {exc}") from exc


def backup_file(path: Path):
    if path.exists():
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = path.with_suffix(path.suffix + f".{stamp}.bak")
        shutil.copy2(path, backup)
        return backup
    return None


def resolve_api_key() -> str | None:
    api_key = os.environ.get(PI_KEY_ENV)
    if api_key:
        return api_key

    claude_settings = load_json(CLAUDE_SETTINGS_JSON, default={}) or {}
    env = claude_settings.get("env", {}) if isinstance(claude_settings, dict) else {}
    api_key = env.get(CLAUDE_KEY_ENV)
    if api_key:
        return api_key

    opencode = load_json(OPENCODE_JSONC, default={}) or {}
    provider = opencode.get("provider", {}).get("openai-compatible", {})
    api_key = provider.get("options", {}).get("apiKey")
    if api_key:
        return api_key.removeprefix("Bearer ")

    return None


def auth_header_value(api_key: str) -> str:
    return api_key


def fetch_model_info(base_url: str, api_key: str) -> list[dict]:
    req = urllib.request.Request(
        f"{base_url}/model/info",
        headers={"accept": "application/json", "Authorization": auth_header_value(api_key)},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    if isinstance(data, dict) and "data" in data:
        return data["data"]
    if isinstance(data, list):
        return data
    raise RuntimeError(f"Unexpected response shape from {base_url}/model/info: {type(data).__name__}")


def to_per_million(cost_per_token):
    if cost_per_token is None:
        return 0
    return round(cost_per_token * 1_000_000, 4)


def uniq_chat_models(raw_models: list[dict]) -> list[dict]:
    seen = set()
    unique_models = []
    for model in raw_models:
        name = model.get("model_name", "")
        if name in seen or name in SKIP_MODELS:
            continue
        seen.add(name)
        unique_models.append(model)

    result = []
    for model in unique_models:
        name = model.get("model_name", "")
        mode = model.get("model_info", {}).get("mode")
        if mode in CHAT_MODES or name in FORCE_INCLUDE:
            result.append(model)
    return sorted(result, key=lambda m: m.get("model_name", ""))


def build_pi_model_entry(model_name: str, info: dict) -> dict:
    mi = info.get("model_info", {})
    max_input = mi.get("max_input_tokens") or mi.get("max_tokens") or 128000
    max_output = mi.get("max_output_tokens") or 16384
    supports_vision = mi.get("supports_vision")
    supports_reasoning = mi.get("supports_reasoning")

    input_types = ["text"]
    if supports_vision is True:
        input_types.append("image")

    cost = {
        "input": to_per_million(mi.get("input_cost_per_token")),
        "output": to_per_million(mi.get("output_cost_per_token")),
        "cacheRead": to_per_million(mi.get("cache_read_input_token_cost")),
        "cacheWrite": to_per_million(mi.get("cache_creation_input_token_cost")),
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


def build_pi_payload(chat_models: list[dict]) -> dict:
    entries = [build_pi_model_entry(m["model_name"], m) for m in chat_models]
    return {
        "providers": {
            **OTHER_PI_PROVIDERS,
            "litellm": {
                "baseUrl": BASE_URL,
                "api": "openai-completions",
                "apiKey": PI_KEY_ENV,
                "authHeader": True,
                "models": sorted(entries, key=lambda e: e["id"]),
            },
        }
    }


def to_codex_reasoning_levels(enabled: bool):
    if not enabled:
        return []
    return [
        {"effort": "low", "description": "Fast responses with lighter reasoning"},
        {"effort": "medium", "description": "Balances speed and reasoning depth for everyday tasks"},
        {"effort": "high", "description": "Greater reasoning depth for complex problems"},
        {"effort": "xhigh", "description": "Extra high reasoning depth for complex problems"},
    ]


def sync_codex(chat_models: list[dict], dry_run: bool):
    cache = load_json(CODEX_MODELS_CACHE)
    if not cache or not isinstance(cache.get("models"), list):
        return [f"skip Codex: missing or invalid {CODEX_MODELS_CACHE}"]

    pi_entries = {m["id"]: m for m in build_pi_payload(chat_models)["providers"]["litellm"]["models"]}
    additions = 0
    merged = []
    seen = set()
    for model in cache["models"]:
        slug = model.get("slug")
        if slug in pi_entries:
            entry = pi_entries[slug]
            supports_reasoning = entry.get("reasoning") is True
            model = {
                **model,
                "slug": slug,
                "display_name": slug,
                "description": model.get("description") or "Synced from LiteLLM metadata",
                "default_reasoning_level": "medium" if supports_reasoning else model.get("default_reasoning_level"),
                "supported_reasoning_levels": to_codex_reasoning_levels(supports_reasoning),
                "input_modalities": entry.get("input", ["text"]),
                "context_window": entry.get("contextWindow", model.get("context_window", 128000)),
                "max_output_tokens": entry.get("maxTokens", model.get("max_output_tokens", 16384)),
                "supported_in_api": True,
                "visibility": model.get("visibility", "list"),
            }
            seen.add(slug)
        merged.append(model)

    for slug, entry in sorted(pi_entries.items()):
        if slug in seen:
            continue
        additions += 1
        supports_reasoning = entry.get("reasoning") is True
        merged.append({
            "slug": slug,
            "display_name": slug,
            "description": "Synced from LiteLLM metadata",
            "default_reasoning_level": "medium" if supports_reasoning else None,
            "supported_reasoning_levels": to_codex_reasoning_levels(supports_reasoning),
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": True,
            "priority": 0,
            "additional_speed_tiers": [],
            "availability_nux": None,
            "upgrade": None,
            "input_modalities": entry.get("input", ["text"]),
            "context_window": entry.get("contextWindow", 128000),
            "max_output_tokens": entry.get("maxTokens", 16384),
        })

    cache["models"] = merged
    cache["fetched_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    if dry_run:
        return [f"Codex: would merge {len(pi_entries)} model aliases, add {additions}"]

    backup_file(CODEX_MODELS_CACHE)
    CODEX_MODELS_CACHE.write_text(json.dumps(cache, indent=2) + "\n")
    return [f"Codex: merged {len(pi_entries)} model aliases, added {additions}"]


def sync_pi(chat_models: list[dict], dry_run: bool):
    payload = build_pi_payload(chat_models)
    if dry_run:
        return [f"Pi: would write {len(payload['providers']['litellm']['models'])} chat models"]
    PI_MODELS_JSON.parent.mkdir(parents=True, exist_ok=True)
    backup_file(PI_MODELS_JSON)
    PI_MODELS_JSON.write_text(json.dumps(payload, indent=2) + "\n")
    return [f"Pi: wrote {len(payload['providers']['litellm']['models'])} chat models"]


def opencode_model_entry(info: dict) -> dict:
    mi = info.get("model_info", {})
    context = mi.get("max_input_tokens") or mi.get("max_tokens") or 128000
    output = mi.get("max_output_tokens") or 16384
    model_name = info["model_name"]
    label = model_name.split(".")[-1].replace("-", " ").upper()
    return {
        "name": label,
        "limit": {
            "context": context,
            "input": min(context, 922000 if context > 922000 else context),
            "output": output,
        },
    }


def sync_opencode(chat_models: list[dict], dry_run: bool):
    config = load_json(OPENCODE_JSONC, default={})
    if config is None:
        return [f"skip OpenCode: invalid {OPENCODE_JSONC}"]

    provider = config.setdefault("provider", {}).setdefault("openai-compatible", {
        "name": "GenAI Gateway",
        "api": "openai",
        "options": {
            "baseURL": BASE_URL,
            "apiKey": f"Bearer ${{{PI_KEY_ENV}}}",
        },
        "models": {},
    })
    provider.setdefault("options", {})
    provider["options"].setdefault("baseURL", BASE_URL)
    provider["options"].setdefault("apiKey", f"Bearer ${{{PI_KEY_ENV}}}")
    provider.setdefault("models", {})
    models = provider["models"]

    updated = 0
    for model in chat_models:
        name = model["model_name"]
        models[name] = opencode_model_entry(model)
        updated += 1

    if dry_run:
        return [f"OpenCode: would upsert {updated} openai-compatible models"]

    backup_file(OPENCODE_JSONC)
    OPENCODE_JSONC.write_text(json.dumps(config, indent=2) + "\n")
    return [f"OpenCode: upserted {updated} openai-compatible models"]


def sync_claude(chat_models: list[dict], dry_run: bool):
    settings = load_json(CLAUDE_SETTINGS_JSON, default={})
    if settings is None:
        return [f"skip Claude: invalid {CLAUDE_SETTINGS_JSON}"]

    names = {m["model_name"] for m in chat_models}
    env = settings.setdefault("env", {})
    changes = []
    mapping = {
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "bedrock.anthropic.claude-opus-4-6",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "bedrock.anthropic.claude-sonnet-4-6",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "bedrock.anthropic.claude-haiku-4-5",
    }
    for key, value in mapping.items():
        if value in names and env.get(key) != value:
            env[key] = value
            changes.append(f"{key}={value}")

    if dry_run:
        return ["Claude: would update defaults" + (f" ({', '.join(changes)})" if changes else " (no changes)")]

    if changes:
        backup_file(CLAUDE_SETTINGS_JSON)
        CLAUDE_SETTINGS_JSON.write_text(json.dumps(settings, indent=2) + "\n")
        return [f"Claude: updated {len(changes)} default model env values"]
    return ["Claude: no changes needed"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = resolve_api_key()
    if not api_key:
        print(
            f"ERROR: neither {PI_KEY_ENV} nor Claude/OpenCode fallback credentials are available",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Fetching model info from {BASE_URL}/model/info ...")
    raw = fetch_model_info(BASE_URL, api_key)
    chat_models = uniq_chat_models(raw)
    print(f"Fetched {len(raw)} raw entries, {len(chat_models)} unique chat models")

    steps = []
    steps.extend(sync_pi(chat_models, args.dry_run))
    steps.extend(sync_codex(chat_models, args.dry_run))
    steps.extend(sync_opencode(chat_models, args.dry_run))
    steps.extend(sync_claude(chat_models, args.dry_run))

    print("\nSummary:")
    for line in steps:
        print(f"- {line}")


if __name__ == "__main__":
    main()
