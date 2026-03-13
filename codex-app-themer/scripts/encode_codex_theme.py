#!/usr/bin/env python3
"""Normalize and encode Codex desktop app themes."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote


HEX_COLOR_LENGTH = 7
DEFAULT_REGISTRY = Path(__file__).resolve().parent.parent / "references" / "code_theme_registry.json"
POWERSHELL_JSON_HINT = (
    " On PowerShell, prefer piping stdin, using --json @payload.json, "
    "or the encode_codex_theme.ps1 wrapper."
)
DEFAULTS = {
    "dark": {
        "accent": "#5ba2ff",
        "contrast": 60,
        "fonts": {"code": None, "ui": None},
        "ink": "#ffffff",
        "opaqueWindows": True,
        "semanticColors": {
            "diffAdded": "#23c16b",
            "diffRemoved": "#ff5d5d",
            "skill": "#b676ff",
        },
        "surface": "#161616",
    },
    "light": {
        "accent": "#0169cc",
        "contrast": 45,
        "fonts": {"code": None, "ui": None},
        "ink": "#0d0d0d",
        "opaqueWindows": True,
        "semanticColors": {
            "diffAdded": "#00a240",
            "diffRemoved": "#e02e2a",
            "skill": "#751ed9",
        },
        "surface": "#ffffff",
    },
}


class ThemeEncodingError(ValueError):
    """Raised when the theme payload cannot be normalized."""


def load_registry(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def normalize_hex(field_name: str, value: Any) -> str:
    if not isinstance(value, str):
        raise ThemeEncodingError(f"{field_name} must be a string")
    normalized = value.strip().lower()
    if len(normalized) != HEX_COLOR_LENGTH or not normalized.startswith("#"):
        raise ThemeEncodingError(f"{field_name} must be a 6-digit hex color")
    try:
        int(normalized[1:], 16)
    except ValueError as exc:
        raise ThemeEncodingError(f"{field_name} must be a 6-digit hex color") from exc
    return normalized


def normalize_font(field_name: str, value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ThemeEncodingError(f"{field_name} must be a string or null")
    stripped = value.strip()
    return stripped or None


def normalize_contrast(value: Any) -> int:
    if isinstance(value, bool):
        raise ThemeEncodingError("theme.contrast must be a number")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ThemeEncodingError("theme.contrast must be a number") from exc
    clamped = max(0, min(100, round(number)))
    return int(clamped)


def normalize_bool(field_name: str, value: Any) -> bool:
    if not isinstance(value, bool):
        raise ThemeEncodingError(f"{field_name} must be a boolean")
    return value


def resolve_code_theme_id(theme_id: Any, variant: str, registry: dict[str, Any]) -> str:
    valid_ids = registry["variants"][variant]
    if theme_id is None:
        return "codex" if "codex" in valid_ids else valid_ids[0]
    if not isinstance(theme_id, str):
        raise ThemeEncodingError("codeThemeId must be a string")
    normalized = theme_id.strip()
    if normalized not in valid_ids:
        valid = ", ".join(valid_ids)
        raise ThemeEncodingError(
            f"codeThemeId '{normalized}' is not valid for {variant}. Valid values: {valid}"
        )
    return normalized


def merge_dict(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_dict(merged[key], value)
        else:
            merged[key] = value
    return merged


def normalize_payload(payload: dict[str, Any], registry: dict[str, Any]) -> dict[str, Any]:
    variant = payload.get("variant")
    if variant not in ("dark", "light"):
        raise ThemeEncodingError("variant must be 'dark' or 'light'")

    base_theme = DEFAULTS[variant]
    raw_theme = payload.get("theme")
    if raw_theme is None:
        raw_theme = {}
    if not isinstance(raw_theme, dict):
        raise ThemeEncodingError("theme must be an object")

    merged_theme = merge_dict(base_theme, raw_theme)

    fonts = merged_theme.get("fonts")
    if not isinstance(fonts, dict):
        raise ThemeEncodingError("theme.fonts must be an object")

    semantic_colors = merged_theme.get("semanticColors")
    if not isinstance(semantic_colors, dict):
        raise ThemeEncodingError("theme.semanticColors must be an object")

    normalized_theme = {
        "accent": normalize_hex("theme.accent", merged_theme.get("accent")),
        "contrast": normalize_contrast(merged_theme.get("contrast")),
        "fonts": {
            "code": normalize_font("theme.fonts.code", fonts.get("code")),
            "ui": normalize_font("theme.fonts.ui", fonts.get("ui")),
        },
        "ink": normalize_hex("theme.ink", merged_theme.get("ink")),
        "opaqueWindows": normalize_bool("theme.opaqueWindows", merged_theme.get("opaqueWindows")),
        "semanticColors": {
            "diffAdded": normalize_hex(
                "theme.semanticColors.diffAdded", semantic_colors.get("diffAdded")
            ),
            "diffRemoved": normalize_hex(
                "theme.semanticColors.diffRemoved", semantic_colors.get("diffRemoved")
            ),
            "skill": normalize_hex("theme.semanticColors.skill", semantic_colors.get("skill")),
        },
        "surface": normalize_hex("theme.surface", merged_theme.get("surface")),
    }

    return {
        "codeThemeId": resolve_code_theme_id(payload.get("codeThemeId"), variant, registry),
        "theme": normalized_theme,
        "variant": variant,
    }


def encode_payload(payload: dict[str, Any]) -> str:
    encoded_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
    return "codex-theme-v1:" + quote(encoded_json, safe="")


def decode_share_string(share_string: str, registry: dict[str, Any]) -> dict[str, Any]:
    prefix = "codex-theme-v1:"
    trimmed = share_string.strip()
    if not trimmed.startswith(prefix):
        raise ThemeEncodingError("share string must start with codex-theme-v1:")
    try:
        payload = json.loads(unquote(trimmed[len(prefix) :]))
    except json.JSONDecodeError as exc:
        raise ThemeEncodingError("share string does not contain valid JSON") from exc
    if not isinstance(payload, dict):
        raise ThemeEncodingError("share string payload must be an object")
    return build_output(payload, registry)


def build_output(payload: dict[str, Any], registry: dict[str, Any]) -> dict[str, Any]:
    normalized = normalize_payload(payload, registry)
    return {
        "variant": normalized["variant"],
        "themeTypeLabel": f"{normalized['variant'].capitalize()} theme",
        "codeThemeId": normalized["codeThemeId"],
        "portableString": encode_payload(normalized),
        "payload": normalized,
    }


def read_text_from_source(field_name: str, value: str) -> str:
    if not isinstance(value, str):
        raise ThemeEncodingError(f"{field_name} must be a string")

    normalized = value.strip()
    if normalized == "@-":
        return sys.stdin.read()
    if normalized.startswith("@"):
        path = Path(normalized[1:]).expanduser()
        try:
            return path.read_text(encoding="utf-8-sig")
        except OSError as exc:
            raise ThemeEncodingError(f"{field_name} file '{path}' could not be read") from exc
    return value


def parse_json_payload(raw: str, source_name: str) -> dict[str, Any]:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        hint = POWERSHELL_JSON_HINT if source_name == "--json" else ""
        raise ThemeEncodingError(f"Could not parse JSON from {source_name}.{hint}") from exc
    if not isinstance(payload, dict):
        raise ThemeEncodingError(f"{source_name} payload must be an object")
    return payload


def read_text_file(field_name: str, path_str: str) -> str:
    path = Path(path_str).expanduser()
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise ThemeEncodingError(f"{field_name} file '{path}' could not be read") from exc


def validate_args(args: argparse.Namespace) -> None:
    json_sources = sum(bool(source) for source in (args.json, args.json_file))
    share_sources = sum(bool(source) for source in (args.share_string, args.share_string_file))

    if json_sources > 1:
        raise ThemeEncodingError("Use only one of --json or --json-file")
    if share_sources > 1:
        raise ThemeEncodingError("Use only one of --share-string or --share-string-file")
    if json_sources and share_sources:
        raise ThemeEncodingError("Use either JSON input or a share string, not both")


def read_payload(args: argparse.Namespace) -> dict[str, Any]:
    if args.json:
        return parse_json_payload(read_text_from_source("--json", args.json), "--json")
    if args.json_file:
        return parse_json_payload(read_text_file("--json-file", args.json_file), "--json-file")
    raw = sys.stdin.read().strip()
    if not raw:
        raise ThemeEncodingError("Provide a JSON payload via --json, --json-file, or stdin")
    return parse_json_payload(raw, "stdin")


def run_self_test() -> None:
    registry = load_registry(DEFAULT_REGISTRY)
    synthwave_payload = {
        "codeThemeId": "codex",
        "variant": "dark",
        "theme": {
            "accent": "#F97E72",
            "contrast": 72,
            "fonts": {"code": None, "ui": None},
            "ink": "#FFFFFF",
            "opaqueWindows": True,
            "semanticColors": {
                "diffAdded": "#72F1B8",
                "diffRemoved": "#FE4450",
                "skill": "#FF7EDB",
            },
            "surface": "#262335",
        },
    }
    expected = (
        "codex-theme-v1:%7B%22codeThemeId%22%3A%22codex%22%2C%22theme%22%3A%7B%22accent%22"
        "%3A%22%23f97e72%22%2C%22contrast%22%3A72%2C%22fonts%22%3A%7B%22code%22%3Anull%2C"
        "%22ui%22%3Anull%7D%2C%22ink%22%3A%22%23ffffff%22%2C%22opaqueWindows%22%3Atrue%2C"
        "%22semanticColors%22%3A%7B%22diffAdded%22%3A%22%2372f1b8%22%2C%22diffRemoved%22%3A"
        "%22%23fe4450%22%2C%22skill%22%3A%22%23ff7edb%22%7D%2C%22surface%22%3A%22%23262335"
        "%22%7D%2C%22variant%22%3A%22dark%22%7D"
    )
    result = build_output(synthwave_payload, registry)
    assert result["portableString"] == expected


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python encode_codex_theme.py --json-file payload.json --portable-only\n"
            "  type payload.json | uv run --python 3.12 encode_codex_theme.py --portable-only\n"
            "  encode_codex_theme.ps1 -JsonPath payload.json -PortableOnly"
        ),
    )
    parser.add_argument(
        "--json",
        help="Theme payload as JSON, @path/to/file.json, or @- to read stdin.",
    )
    parser.add_argument(
        "--json-file",
        help="Path to a JSON payload file.",
    )
    parser.add_argument(
        "--share-string",
        help="Existing codex-theme-v1 string, @path/to/file.txt, or @- to read stdin.",
    )
    parser.add_argument(
        "--share-string-file",
        help="Path to a file containing a codex-theme-v1 string.",
    )
    parser.add_argument(
        "--registry",
        default=str(DEFAULT_REGISTRY),
        help="Path to code_theme_registry.json",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run a built-in validation check and exit.",
    )
    parser.add_argument(
        "--portable-only",
        action="store_true",
        help="Print only the final codex-theme-v1 string.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    validate_args(args)
    if args.self_test:
        run_self_test()
        return 0

    registry = load_registry(Path(args.registry))
    if args.share_string or args.share_string_file:
        share_string = args.share_string
        if args.share_string_file:
            share_string = read_text_file("--share-string-file", args.share_string_file)
        output = decode_share_string(read_text_from_source("--share-string", share_string), registry)
    else:
        output = build_output(read_payload(args), registry)
    if args.portable_only:
        sys.stdout.write(output["portableString"])
        sys.stdout.write("\n")
    else:
        json.dump(output, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ThemeEncodingError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
