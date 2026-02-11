---
name: ultrathink
description: Run deep plan-first analysis. Use when the user explicitly asks for ultrathink (for example, "plan this first with ultrathink").
---

# Ultrathink

## Overview

Use this skill to generate high-depth planning outputs, always enforce the planning posture: plan first, surface big forks early, compare tradeoffs, then recommend a path.

## Workflow

1. Build a compact context bundle from the current user query.
2. Add optional augmentation from web search results, codebase findings, and other relevant constraints.
3. Run `scripts/run_ultrathink.sh` to submit a background response with priority tier.
4. Poll until completion (up to 1 hour by default), or resume later with the response id.
5. Return the output with explicit forks, tradeoffs, and a recommended execution path.

## Build Context Input

- Start with the user request verbatim.
- Add only high-signal context:
  - codebase: key `rg` findings, relevant files, current errors.
  - web: concise sourced notes when recency matters.
  - constraints: deadlines, non-goals, compatibility or infra limits.
- Prefer short summaries over large dumps.

## Dynamic Query Construction (required)

Do not use a static query string. Construct the request dynamically from the current turn:
1. Extract the user's exact ask for this turn.
2. Add relevant codebase findings (files, errors, diffs, constraints).
3. Add web findings when recency or external facts matter.
4. Add other operational constraints (time, infra, rollout risk, compatibility).
5. Send that assembled payload to Pro.

Recommended structure for the assembled query text:
- `User request`
- `Codebase context`
- `Web context (with sources/dates if used)`
- `Constraints`
- `Task to model: plan first and surface big forks early`

## Run Command

Use the helper script. It reads `OPENAI_API_KEY` from the shell environment.
Dependencies: `curl`, `jq`, `bash`.

```bash
bash /Users/andrewg/.codex/skills/ultrathink/scripts/run_ultrathink.sh \
  --query-file /tmp/ultrathink_query.md \
  --context-text "Constraint: zero downtime." \
  --context-file /tmp/codebase-notes.md
```

Or pipe the dynamically assembled query directly:

```bash
cat /tmp/ultrathink_query.md | bash /Users/andrewg/.codex/skills/ultrathink/scripts/run_ultrathink.sh \
  --query-stdin \
  --context-file /tmp/codebase-notes.md
```

Defaults:
- `model=gpt-5.2-pro`
- `service_tier=priority`
- `background=true`
- plan-first/fork-first instruction prefix
- poll timeout `3600` seconds

## Submit And Resume

Submit only and return response id:

```bash
bash /Users/andrewg/.codex/skills/ultrathink/scripts/run_ultrathink.sh \
  --query-file /tmp/ultrathink_query.md \
  --submit-only
```

Resume polling later:

```bash
bash /Users/andrewg/.codex/skills/ultrathink/scripts/run_ultrathink.sh \
  --resume-response-id resp_123
```

## Output Contract

When presenting results back to the user, keep this shape:
1. Plan summary.
2. Major forks and tradeoffs.
3. Recommended path.
4. Immediate next actions.

If the background response is still running, return the response id and status, then provide the exact resume command.

## Notes

- Background responses are pollable for roughly 10 minutes after completion.
- Priority requests can be downgraded to default tier during rapid traffic ramps; verify `service_tier` in the final response.
