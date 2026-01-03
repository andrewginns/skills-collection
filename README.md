# Skill Collection

This repository collects Agent skills that package reusable workflows as small bundles of instructions and optional scripts. Each skill lives in its own folder and includes a `SKILL.md` file with the name, description, and usage guidance.

## What makes up a skill

- **`SKILL.md`**: Required. Defines the skill name and description in YAML front matter, plus any instructions and usage examples.
- **`scripts/`** (optional): Automation or deterministic tooling the skill can run.
- **`references/`** (optional): Supporting docs, schemas, or examples.
- **`assets/`** (optional): Templates or other resources.

## How skills are used

- Skills can be invoked explicitly by name, or implicitly based on their description.
- Keep skills focused on a single workflow and document clear triggers for when they should run.

## Learn more

For the latest guidance on skills, see the official docs:

- https://developers.openai.com/codex/skills
- https://agentskills.io/specification

## Dependency management note

The agent skills specification does not define how dependencies are installed or managed. If your skill includes scripts, portability can be improved by embedding dependency metadata for runtimes that support it. For example:

- **Python**: `uv` inline script metadata in a `# /// script` block.
- **JavaScript/Node.js**: `npx` for ad-hoc execution, or `npm` package executables.
- **Go**: `go run` with module-aware dependency resolution.
- **Rust**: `cargo run` for crates with a `Cargo.toml`.
- **Deno**: inline `deno.json`/`deno.jsonc` configs or `deno run` with import maps.