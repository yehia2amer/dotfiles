#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Build a custom Codex model catalog (`model_catalog_json`) for the enterprise
LiteLLM proxy, so Codex stops falling back to guessed metadata for the
dot-prefixed proxy model names (e.g. `openai.gpt-5.6-sol`).

The catalog Codex loads via `model_catalog_json` REPLACES the bundled catalog,
so we always re-include the current bundled models (under their bare slugs) and
add one entry per routable proxy model.

Sources, in the order they contribute:
  1. `codex debug models --bundled`  -> authoritative per-entry SCHEMA + real
     reasoning efforts + Codex's `base_instructions`/`model_messages`. Used both
     as the entry TEMPLATE (guarantees every required field is present) and as
     the primary reasoning-effort source.
  2. Newest `~/.codex/models_cache.json.*.bak` (legacy) -> fills reasoning
     efforts for families dropped from the current bundle (e.g. gpt-5.3-codex).
  3. `GET {base}/models` (Bearer + browser UA) -> authoritative routable slugs.
     Falls back to the CSV `Model Name` column when unreachable.
  4. `Models_List_EMEA.csv` -> real Max Input / Max Output tokens per model.

Reasoning efforts resolve per base family: bundled > legacy-cache > name
heuristic. The build prints which source supplied each openai model's efforts
and flags heuristic-only models so drift is visible.

Runs strictly under `uv run` (bare python3 is blocked in this environment):
    uv run ~/.agents/scripts/build-codex-catalog.py [--dry-run] [--diff]
        [--out PATH] [--csv PATH]

Fails safe: if it cannot obtain a slug set (no /models and no CSV), it exits
non-zero WITHOUT writing, so a scheduled run never clobbers a good catalog.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# ── Configuration ───────────────────────────────────────────────────────────

HOME = Path.home()
CODEX_HOME = HOME / ".codex"
DEFAULT_OUT = CODEX_HOME / "models_catalog.json"
DEFAULT_CSV = HOME / "Downloads" / "Models_List_EMEA.csv"
API_KEY_ENV = "OPENAI_API_KEY"
API_KEY_KEYCHAIN_ITEM = "litellm-api-key"  # fallback when env is unset (launchd)
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
)

# Codex catalog schema version (from `codex debug models --bundled`).
SCHEMA_VERSION = 4

# CSV `Model Type` values that are usable as an agent chat model.
CHAT_TYPES = {"chat", "responses", "computer_use"}

# Substrings that mark a routable id as non-chat (used when filtering /models
# ids, which carry no type column).
NON_CHAT_PATTERNS = (
    "embed", "embedding", "tts", "whisper", "transcribe", "rerank",
    "imagen", "image", "dall-e", "canvas", "realtime", "audio", "-tts",
)

# Reasoning families detected by name when no first-party effort data exists.
REASONING_NAME_RE = re.compile(
    r"(gpt-5(\.\d+)?)|(^|[.\-])o[134]([.\-]|$)|(o[134]-)|claude|gemini",
    re.IGNORECASE,
)
# gpt-4 / gpt-4o / gpt-4.1 etc. are explicitly NON-reasoning.
NON_REASONING_NAME_RE = re.compile(r"gpt-4(\.|o|-|$)", re.IGNORECASE)

# Vision-capable families (CSV has no vision column; infer from name).
VISION_NAME_RE = re.compile(
    r"(gpt-4o)|(gpt-4\.1)|(gpt-5)|claude|gemini|pixtral|(gpt-image)",
    re.IGNORECASE,
)

# Heuristic reasoning profile used when neither bundled nor legacy cache knows
# the family. Matches what the existing sync scripts assume.
HEURISTIC_LEVELS = [
    {"effort": "low", "description": "Fast responses with lighter reasoning"},
    {"effort": "medium",
     "description": "Balances speed and reasoning depth for everyday tasks"},
    {"effort": "high", "description": "Greater reasoning depth for complex problems"},
    {"effort": "xhigh",
     "description": "Extra high reasoning depth for complex problems"},
]
HEURISTIC_DEFAULT = "medium"

# Fields we override on the cloned template per routable model. Everything else
# (base_instructions, model_messages, tool_mode, verbosity, ...) is inherited
# from the bundled template so all required fields stay present and valid.
_TOKEN_FALLBACK_CTX = 128000


# ── Source loaders ────────────────────────────────────────────────────────────


def keychain(service: str) -> str:
    """Read a generic password from the macOS keychain (empty string on miss)."""
    try:
        return subprocess.run(
            ["security", "find-generic-password", "-a", "yamer003",
             "-s", service, "-w"],
            capture_output=True, text=True, check=False,
        ).stdout.strip()
    except Exception:
        return ""


def resolve_api_key() -> str:
    """LiteLLM proxy key: env first, then the keychain item the shell uses.
    Lets the script work under launchd/chezmoi (bare env, no exported key)."""
    return os.environ.get(API_KEY_ENV, "") or keychain(API_KEY_KEYCHAIN_ITEM)


def codex_bin() -> str:
    """Path to the codex binary (PATH, then the known bun location)."""
    return shutil.which("codex") or str(HOME / ".bun" / "bin" / "codex")


def load_bundled() -> list[dict]:
    """`codex debug models --bundled` -> list of full model entries."""
    proc = subprocess.run(
        [codex_bin(), "debug", "models", "--bundled"],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"`codex debug models --bundled` failed: {proc.stderr[:400]}")
    data = json.loads(proc.stdout)
    return data.get("models", [])


def validate_with_codex(path: Path) -> int:
    """Load the catalog through Codex and return the model count it renders.
    0 means Codex rejected it. This is the same check the shell wrapper did,
    now inline so no bash/jq is needed."""
    proc = subprocess.run(
        [codex_bin(), "debug", "models", "-c", f"model_catalog_json={path}"],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        return 0
    try:
        return len(json.loads(proc.stdout).get("models", []))
    except json.JSONDecodeError:
        return 0


def load_legacy_cache() -> list[dict]:
    """Newest ~/.codex/models_cache.json*.bak (or live) -> model entries."""
    candidates = sorted(
        list(CODEX_HOME.glob("models_cache.json")) +
        list(CODEX_HOME.glob("models_cache.json.*.bak")),
        key=lambda p: p.stat().st_mtime if p.exists() else 0,
        reverse=True,
    )
    for path in candidates:
        try:
            data = json.loads(path.read_text())
            models = data.get("models", []) if isinstance(data, dict) else []
            if models:
                return models
        except (json.JSONDecodeError, OSError):
            continue
    return []


def fetch_routable_slugs(base_url: str, api_key: str) -> list[str] | None:
    """GET {base}/models with Bearer + browser UA. None if unreachable."""
    if not base_url or not api_key:
        return None
    req = urllib.request.Request(
        f"{base_url}/models",
        headers={"Authorization": f"Bearer {api_key}", "User-Agent": BROWSER_UA},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return [m["id"] for m in data.get("data", []) if m.get("id")]
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError,
            json.JSONDecodeError):
        return None


def load_csv(path: Path) -> dict:
    """CSV -> indices for token lookup:
      by_name      : {model_name: info}
      by_canonical : {canonical_model: info}
      by_family    : {base_family: info}  (chat rows only; largest ctx wins)
      chat_names   : [model_name, ...]
    Token counts are ints (or None)."""
    by_name: dict[str, dict] = {}
    by_canonical: dict[str, dict] = {}
    by_family: dict[str, dict] = {}
    chat_names: list[str] = []
    if not path.exists():
        return {"by_name": by_name, "by_canonical": by_canonical,
                "by_family": by_family, "chat_names": chat_names}

    with path.open(newline="", encoding="utf-8-sig") as fh:
        for row in csv.DictReader(fh):
            name = (row.get("Model Name") or "").strip()
            if not name:
                continue
            info = {
                "max_input": _to_int(row.get("Max Input Tokens")),
                "max_output": _to_int(row.get("Max Output Tokens")),
                "provider": (row.get("Provider") or "").strip(),
                "type": (row.get("Model Type") or "").strip(),
            }
            by_name[name] = info
            canonical = (row.get("Canonical Model") or "").strip()
            if canonical and canonical not in by_canonical:
                by_canonical[canonical] = info
            if info["type"] in CHAT_TYPES:
                chat_names.append(name)
                fam = base_family(name)
                # Keep the row with the largest known context for the family.
                prev = by_family.get(fam)
                if (prev is None
                        or (info["max_input"] or 0) > (prev["max_input"] or 0)):
                    by_family[fam] = info
    return {"by_name": by_name, "by_canonical": by_canonical,
            "by_family": by_family, "chat_names": chat_names}


def _to_int(value) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


# ── Name helpers ──────────────────────────────────────────────────────────────

_REGION_RE = re.compile(r"^(global|eu)\.")
_DATE_RE = re.compile(r"-\d{4}-\d{2}-\d{2}$")
_PROVIDER_PREFIXES = ("openai.", "azure.", "bedrock.", "vertex_ai.")


def base_family(slug: str) -> str:
    """Strip provider prefix, region, date suffix, -responses -> family key.

    openai.global.gpt-5.6-sol            -> gpt-5.6-sol
    bedrock.anthropic.claude-opus-4-8    -> anthropic.claude-opus-4-8
    azure.gpt-4o-2024-11-20-responses    -> gpt-4o
    """
    s = slug
    for prefix in _PROVIDER_PREFIXES:
        if s.startswith(prefix):
            s = s[len(prefix):]
            break
    s = _REGION_RE.sub("", s)
    if s.endswith("-responses"):
        s = s[: -len("-responses")]
    s = _DATE_RE.sub("", s)
    return s


def canonical_from_slug(slug: str) -> str:
    """Best-effort canonical key: first dot -> slash, region+date stripped.

    openai.global.gpt-5.6-sol -> openai/gpt-5.6-sol
    """
    if "." not in slug:
        return slug
    provider, rest = slug.split(".", 1)
    rest = _REGION_RE.sub("", rest)
    if rest.endswith("-responses"):
        rest = rest[: -len("-responses")]
    return f"{provider}/{rest}"


def is_chat_slug(slug: str) -> bool:
    low = slug.lower()
    if low.startswith("all-proxy"):
        return False
    if low.endswith("-responses"):
        return False  # duplicate of the non-suffixed routable id
    return not any(pat in low for pat in NON_CHAT_PATTERNS)


# ── Reasoning-effort resolution ────────────────────────────────────────────────


def build_effort_lookup(bundled: list[dict], legacy: list[dict]) -> dict:
    """family -> {'levels': [...], 'default': str|None, 'source': str}."""
    lookup: dict[str, dict] = {}
    # Legacy first, so bundled overwrites on conflict.
    for source, models in (("legacy-cache", legacy), ("bundled", bundled)):
        for m in models:
            fam = base_family(m.get("slug", ""))
            if not fam:
                continue
            lookup[fam] = {
                "levels": m.get("supported_reasoning_levels", []) or [],
                "default": m.get("default_reasoning_level"),
                "source": source,
            }
    return lookup


def resolve_efforts(slug: str, lookup: dict) -> tuple[list, str | None, str]:
    """-> (levels, default, source)."""
    fam = base_family(slug)
    if fam in lookup and lookup[fam]["levels"]:
        return lookup[fam]["levels"], lookup[fam]["default"], lookup[fam]["source"]
    # Heuristic.
    low = slug.lower()
    if NON_REASONING_NAME_RE.search(low) and not REASONING_NAME_RE.search(
        low.replace("gpt-4", "")
    ):
        return [], None, "heuristic-none"
    if REASONING_NAME_RE.search(low):
        return list(HEURISTIC_LEVELS), HEURISTIC_DEFAULT, "heuristic-reasoning"
    return [], None, "heuristic-none"


# ── Entry construction ─────────────────────────────────────────────────────────


def pick_template(slug: str, bundled: list[dict]) -> dict:
    """A full bundled entry to clone. Prefer the entry whose slug matches this
    model's base family (full fidelity: tool_mode, verbosity, web_search type);
    otherwise the generic gpt-5.5 entry (tool_mode=null, portable). Guarantees
    every required field is present."""
    by_slug = {m.get("slug"): m for m in bundled}
    fam = base_family(slug)
    if fam in by_slug:
        return by_slug[fam]
    return by_slug.get("gpt-5.5") or (bundled[0] if bundled else {})


def build_entry(slug: str, bundled: list[dict], csv_idx: dict,
                effort_lookup: dict) -> tuple[dict, str]:
    """Clone a template and override identity/token/modality/effort fields.
    Returns (entry, effort_source)."""
    levels, default_level, effort_source = resolve_efforts(slug, effort_lookup)

    entry = json.loads(json.dumps(pick_template(slug, bundled)))  # deep copy

    # Token limits: exact name row -> canonical row -> base-family row (dated
    # CSV variants) -> family-matched bundled template's own real ctx -> fallback.
    info = (csv_idx["by_name"].get(slug)
            or csv_idx["by_canonical"].get(canonical_from_slug(slug))
            or csv_idx["by_family"].get(base_family(slug)))
    # Only trust the template ctx when it is a family match (else it's the
    # generic gpt-5.5 template at 272000, wrong for e.g. gpt-4o).
    by_slug = {m.get("slug") for m in bundled}
    tmpl_ctx = (entry.get("context_window")
                if base_family(slug) in by_slug else None) or _TOKEN_FALLBACK_CTX
    ctx = (info or {}).get("max_input") or tmpl_ctx

    modalities = ["text", "image"] if VISION_NAME_RE.search(slug.lower()) else ["text"]

    entry.update({
        "slug": slug,
        "display_name": slug,
        "context_window": ctx,
        "max_context_window": ctx,
        "input_modalities": modalities,
        "supported_reasoning_levels": levels,
        "default_reasoning_level": default_level,
        "supported_in_api": True,
        "visibility": "list",
    })
    # Effective ctx percent must not exceed 100 if template had a smaller model.
    if "effective_context_window_percent" not in entry:
        entry["effective_context_window_percent"] = 100
    return entry, effort_source


# ── Main ────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description="Build Codex custom model catalog.")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    ap.add_argument("--dry-run", action="store_true",
                    help="Do not write; print the report only.")
    ap.add_argument("--diff", action="store_true",
                    help="Show slug additions/removals vs the existing catalog.")
    ap.add_argument("--no-validate", action="store_true",
                    help="Skip the `codex debug models` validation before install.")
    args = ap.parse_args()

    bundled = load_bundled()
    if not bundled:
        print("ERROR: could not load bundled catalog from codex.", file=sys.stderr)
        return 1
    legacy = load_legacy_cache()
    effort_lookup = build_effort_lookup(bundled, legacy)
    csv_idx = load_csv(args.csv)

    base_url = keychain("work-genai-base-url")
    api_key = resolve_api_key()
    routable = fetch_routable_slugs(base_url, api_key)
    slug_source = "live /models"
    if routable is None:
        routable = list(csv_idx["chat_names"])
        slug_source = "CSV fallback"
    if not routable:
        print("ERROR: no routable slugs from /models or CSV; refusing to write "
              "(fail-safe).", file=sys.stderr)
        return 2

    # Always include the current bundled models (bare slugs) so they survive the
    # catalog replacement, plus every chat routable proxy slug.
    proxy_slugs = sorted({s for s in routable if is_chat_slug(s)})
    bundled_slugs = [m["slug"] for m in bundled]

    entries: list[dict] = []
    seen: set[str] = set()
    effort_stats: dict[str, int] = {}
    heuristic_only: list[str] = []

    # Bundled entries verbatim (keep Codex's own model cards intact).
    for m in bundled:
        if m["slug"] not in seen:
            entries.append(m)
            seen.add(m["slug"])

    for slug in proxy_slugs:
        if slug in seen:
            continue
        entry, src = build_entry(slug, bundled, csv_idx, effort_lookup)
        entries.append(entry)
        seen.add(slug)
        effort_stats[src] = effort_stats.get(src, 0) + 1
        if src.startswith("heuristic"):
            heuristic_only.append(slug)

    entries.sort(key=lambda e: e["slug"])
    catalog = {"schema_version": SCHEMA_VERSION, "models": entries}

    # Report.
    print(f"Slug source          : {slug_source} ({len(proxy_slugs)} chat slugs)")
    print(f"Bundled models kept  : {len(bundled_slugs)} -> {', '.join(bundled_slugs)}")
    print(f"Legacy cache families: {len({base_family(m['slug']) for m in legacy})}")
    print(f"Total catalog entries: {len(entries)}")
    prefixes: dict[str, int] = {}
    for e in entries:
        prefixes[e['slug'].split('.')[0]] = prefixes.get(e['slug'].split('.')[0], 0) + 1
    print("By prefix            : " +
          ", ".join(f"{k}={v}" for k, v in sorted(prefixes.items())))
    print("Effort source        : " +
          ", ".join(f"{k}={v}" for k, v in sorted(effort_stats.items())))
    if heuristic_only:
        print(f"\n  ⚠ {len(heuristic_only)} models have NO first-party effort data "
              f"(name-heuristic only):")
        for s in heuristic_only[:30]:
            print(f"    - {s}")
        if len(heuristic_only) > 30:
            print(f"    … and {len(heuristic_only) - 30} more")

    if args.diff:
        _show_diff(args.out, seen)

    if args.dry_run:
        print(f"\n[DRY RUN] would write {len(entries)} models to {args.out}")
        return 0

    # Write to a temp file next to the target, validate it through Codex, then
    # atomically swap it in. On any failure the existing catalog is untouched —
    # safe to run unattended from launchd / chezmoi.
    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_suffix(args.out.suffix + ".tmp")
    tmp.write_text(json.dumps(catalog, indent=2) + "\n")

    if not args.no_validate:
        count = validate_with_codex(tmp)
        if count < 1:
            tmp.unlink(missing_ok=True)
            print("\nERROR: Codex rejected the generated catalog; keeping the "
                  "existing one.", file=sys.stderr)
            return 3
        print(f"\nValidation OK: Codex loaded {count} models.")

    if args.out.exists():
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = args.out.with_suffix(args.out.suffix + f".{stamp}.bak")
        shutil.copy2(args.out, backup)
        _rotate_backups(args.out, keep=3)
        print(f"Backed up previous catalog -> {backup.name}")

    os.replace(tmp, args.out)  # atomic within the same directory
    print(f"✓ Installed {len(entries)} models -> {args.out}")
    return 0


def _rotate_backups(out_path: Path, keep: int) -> None:
    """Keep only the newest `keep` timestamped .bak files for this catalog."""
    baks = sorted(out_path.parent.glob(out_path.name + ".*.bak"),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    for old in baks[keep:]:
        old.unlink(missing_ok=True)


def _show_diff(out_path: Path, new_slugs: set[str]) -> None:
    try:
        old = json.loads(out_path.read_text())
        old_slugs = {m["slug"] for m in old.get("models", [])}
    except (FileNotFoundError, json.JSONDecodeError):
        old_slugs = set()
    added = sorted(new_slugs - old_slugs)
    removed = sorted(old_slugs - new_slugs)
    if added:
        print(f"\n  ✚ Added ({len(added)}): " + ", ".join(added[:20]) +
              (" …" if len(added) > 20 else ""))
    if removed:
        print(f"  ✖ Removed ({len(removed)}): " + ", ".join(removed[:20]) +
              (" …" if len(removed) > 20 else ""))
    if not added and not removed:
        print("\n  No slug additions or removals vs existing catalog.")


if __name__ == "__main__":
    sys.exit(main())
