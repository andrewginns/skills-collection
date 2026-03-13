---
name: codex-app-themer
description: Turn an image, a theme URL, or a loose aesthetic description into a valid portable Codex app theme string. Use this when someone wants a `codex-theme-v1:` import for Codex.app and needs the result clearly labeled as a dark or light theme.
---

# Codex App Themer

## Overview

This skill converts theme inspiration into a Codex desktop app import string that the user can paste into the theme importer. It supports three input styles: image, URL, and vague text description.

## Use This Skill When

- The user wants a portable `codex-theme-v1:` string for Codex.app.
- The source is an image, a URL to an existing theme, or a text-only vibe description.
- The user wants a recognizable approximation of an existing theme within Codex app theme constraints.

## Hard Constraints

- Always tell the user explicitly whether the output is a `Dark theme` or `Light theme`.
- Always return the final portable string.
- Only ask a clarifying question about dark vs light when the source is truly ambiguous.
- If the variant is clear from the source or request, do not ask. Use that variant.
- If you must choose without asking, default to `dark`.
- The final string must use a valid `codeThemeId` for the chosen variant from [`references/code_theme_registry.json`](./references/code_theme_registry.json).
- Colors in the payload must be 6-digit hex values.
- Do not claim exact syntax-theme parity if the app cannot support it. State when the overall chrome is matched and the code theme is approximated.

## Workflow

### 1. Identify The Input Type

- `Image`: extract palette, brightness, contrast, mood, and likely accent color.
- `URL`: inspect only the minimum needed theme files or docs. Prefer primary theme files over screenshots or marketing pages.
- `Text`: infer palette and contrast from the user’s adjectives, references, and mood words.

### 2. Choose The Variant

- Use the user’s explicit request first.
- If the source strongly implies a variant, use that.
- Ask one brief clarifying question only when light vs dark is genuinely unclear.
- If ambiguity remains and asking would slow down a straightforward request, choose `dark`.

Strong dark cues:
- neon, synthwave, noir, terminal, night, cyberpunk, high-glow
- dark screenshots or dark theme repos

Strong light cues:
- paper, editorial, soft daylight, notebook, airy, pastel white
- light screenshots or light theme repos

### 3. Build The Theme Spec

Produce a payload with this shape:

```json
{
  "codeThemeId": "codex",
  "variant": "dark",
  "theme": {
    "accent": "#0169cc",
    "contrast": 45,
    "fonts": {
      "code": null,
      "ui": null
    },
    "ink": "#0d0d0d",
    "opaqueWindows": true,
    "semanticColors": {
      "diffAdded": "#00a240",
      "diffRemoved": "#e02e2a",
      "skill": "#751ed9"
    },
    "surface": "#ffffff"
  }
}
```

Guidelines:
- `codeThemeId`: choose the closest supported match from [`references/code_theme_registry.json`](./references/code_theme_registry.json). Use `codex` when the main goal is chrome matching rather than exact syntax matching.
- `accent`: main highlight color.
- `surface`: main window background.
- `ink`: primary foreground color.
- `contrast`: integer `0..100`; higher values mean stronger separation.
- `fonts`: leave `null` unless the user explicitly asks for fonts.
- `opaqueWindows`: use `true` unless the user clearly wants a translucent or glassy feel.
- `semanticColors.diffAdded`: choose a readable green aligned with the palette.
- `semanticColors.diffRemoved`: choose a readable red aligned with the palette.
- `semanticColors.skill`: choose a vivid secondary accent that still reads distinctly from `accent`.

### 4. Validate And Encode

After choosing the theme spec, normalize and encode it with:

```bash
python "$CODEX_HOME/skills/codex-app-themer/scripts/encode_codex_theme.py" <<'JSON'
{
  "codeThemeId": "codex",
  "variant": "dark",
  "theme": {
    "accent": "#f97e72",
    "contrast": 72,
    "fonts": {
      "code": null,
      "ui": null
    },
    "ink": "#ffffff",
    "opaqueWindows": true,
    "semanticColors": {
      "diffAdded": "#72f1b8",
      "diffRemoved": "#fe4450",
      "skill": "#ff7edb"
    },
    "surface": "#262335"
  }
}
JSON
```

On macOS/Linux, calling the Python script directly is fine. On Windows, if `python` resolves to the Microsoft Store shim or is missing, prefer the PowerShell wrapper in `scripts/encode_codex_theme.ps1`; it tries `python`, then `python3`, then `py -3`, and finally `uv run`.

You can also avoid shell-quoting issues by using a file-backed payload:

```bash
python "$CODEX_HOME/skills/codex-app-themer/scripts/encode_codex_theme.py" \
  --json-file payload.json --portable-only
```

PowerShell / Windows example:

```powershell
& "$env:CODEX_HOME\skills\codex-app-themer\scripts\encode_codex_theme.ps1" `
  -JsonPath .\payload.json -PortableOnly
```

The script returns normalized JSON with:
- `themeTypeLabel`
- `codeThemeId`
- `payload`
- `portableString`

Before replying, validate the exact final string you plan to show:

```bash
python "$CODEX_HOME/skills/codex-app-themer/scripts/encode_codex_theme.py" \
  --share-string 'codex-theme-v1:%7B...%7D'
```

PowerShell / Windows validation example:

```powershell
& "$env:CODEX_HOME\skills\codex-app-themer\scripts\encode_codex_theme.ps1" `
  -ShareString 'codex-theme-v1:%7B...%7D'
```

If this round-trip fails, do not present the string. Fix the payload first.

### 5. Response Contract

Your final answer should include, in this order:

1. A first line that is exactly `Dark theme` or `Light theme`.
2. One short sentence explaining the inspiration and any approximation.
3. The final `codex-theme-v1:` string in a fenced `text` block.
4. One short reminder to import it into the matching light or dark section in Codex.
5. One short note that the user should copy only the raw string and not include surrounding backticks or extra text.

## Examples

### Vague Text Input

If the user says:

> Make something that feels like an old CRT terminal with emerald highlights.

You should infer a dark theme, choose a supported dark `codeThemeId`, produce the encoded string, and label it `Dark theme`.

### Ambiguous Input

If the user says:

> Make me a clean minimalist theme inspired by Scandinavian design.

Ask one question:

> Do you want this as a light theme or a dark theme?

Only ask when the source does not strongly suggest either variant.
