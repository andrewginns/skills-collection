---
name: tailscale-serve
description: Expose a local dev server (localhost port) as a tailnet-only HTTPS URL using `tailscale serve`, and show the resulting ts.net URL.
metadata:
  short-description: Localhost → ts.net HTTPS via Tailscale Serve.
---

Turn a locally running web app into a repeatable **Tailscale HTTPS** endpoint.

## Inputs to gather

- `port`: the local port the app listens on (e.g. `3000`).
- `path`: `/` (root) or a subpath like `/myapp`.
- Scope: **tailnet-only** (default). Only suggest public access if the user explicitly asks.

If any are missing, ask concise clarifying questions.

## Procedure

1. Confirm Tailscale is running and logged in:
   - `tailscale status`

2. Confirm the app is reachable locally:
   - `curl -fsS http://127.0.0.1:<port>/` (adjust path if needed)

3. Configure Tailscale Serve (tailnet-only HTTPS):
   - Root mount:
     - `sudo tailscale serve https / http://127.0.0.1:<port>`
   - Subpath mount:
     - `sudo tailscale serve https /<path> http://127.0.0.1:<port>`

4. Show what’s exposed:
   - `tailscale serve status`

5. Provide the URL to share using MagicDNS:
   - `https://<machine-name>.<tailnet>.ts.net/` (root)
   - `https://<machine-name>.<tailnet>.ts.net/<path>` (subpath)

6. Cleanup (when asked):
   - `sudo tailscale serve reset`

## Guardrails / gotchas

- `tailscale serve` changes often require `sudo`.
- If mounting at a subpath, frameworks may need a base path setting.
- Do not enable public exposure (`tailscale funnel`) unless explicitly requested; if requested, ask what auth/protection they want first.
