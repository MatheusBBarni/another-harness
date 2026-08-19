# Grok OAuth provider

Approved requirements for adding a SuperGrok / X Premium OAuth provider to the `another-harness` fork of fx.

## Feature objective

Add a SuperGrok / X Premium OAuth provider so Grok models run without `XAI_API_KEY`, while the existing Vercel AI Gateway path stays intact.

## Expected behavior

### Login

- `fx login` and TUI `/login` show a picker: **Vercel** or **Grok**.
- `fx login grok` / `fx login vercel` (and `/login grok`, `/login vercel`) skip the picker.
- Grok uses xAI device-code OAuth:
  - `POST https://auth.x.ai/oauth2/device/code`
  - `POST https://auth.x.ai/oauth2/token`
  - client `b1a00492-073a-47ea-816f-4c329264a828`
  - scopes `openid profile email offline_access grok-cli:access api:access`
  - form field `referrer=another-harness` (never `pi`)
- Persist refreshable tokens in a **separate** session file (`~/.fx/grok-auth.json`), same lock/0600/refresh-skew pattern as Vercel auth. Do not stuff Grok tokens into `~/.fx/auth.json`.
- Last login owns the session: Grok login sets credential source to Grok OAuth and default model to `xai/grok-4.6`. Vercel login restores Gateway + its default/last Gateway model.

### Logout

- `fx logout` / `/logout` **wipes both** Vercel and Grok sessions.

### Models

- IDs are always `xai/grok-…`. Strip `xai/` when calling `api.x.ai`.
- Static Grok catalog: `xai/grok-4.6`, `xai/grok-4.5`, `xai/grok-4.3`, `xai/grok-build-0.1`.
- `xai/grok-4.6`, `xai/grok-4.3`, `xai/grok-build-0.1` → `POST https://api.x.ai/v1/chat/completions`
- `xai/grok-4.5` → `POST https://api.x.ai/v1/responses`
- Last login decides backend for those ids (Grok OAuth vs Vercel Gateway). Same string, different transport.

### Inference

- Grok path is OpenAI-compatible streaming into fx’s existing `GatewayCompletion` / tool-call callbacks.
- Vercel path unchanged (LM spec v4 → `ai-gateway.vercel.sh`).
- Do not send `ai-language-model-*` or `x-vercel-ai-gateway-team` to xAI.

### Usage (pi-supergrok-usage)

- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the SuperGrok Bearer.
- Headers: `x-grok-client-mode: cli`, `x-grok-client-version: 1.0.4`.
- `/credits` (`/balance`) shows plan, weekly/monthly %, reset, prepaid.
- `/xai-usage` is a first-class alias with Pi-style notify text (plan, %, period, reset, prepaid, last RPM window).
- While Grok is active, status line shows `SG {n}% · {reset}` and `{remaining}/{limit} RPM` after a request when headers exist.

### Search

- When Grok is active, web search uses xAI server-side `{ "type": "web_search" }`, not Vercel Perplexity/Parallel.

### ACP

- Advertise `grok_oauth`. If a Grok session file exists, authenticate with it. If not, fail: run `fx login grok` first. No device-code inside ACP this cycle.

## Identified edge cases

- Expired access token → refresh via `refresh_token`; failed refresh → clear Grok session and tell the user to log in again.
- Device-code denied / expired / timeout → same class of errors as Vercel login.
- No TTY → picker is unavailable; require `fx login grok|vercel`.
- Logout with only one session present → still succeeds; both stores end empty.
- 401/403 from billing → `/credits` and `/xai-usage` report re-login; do not leak the token.
- `/model` to a non-`xai/` id while Grok is active and Vercel session was wiped → missing Gateway credential error (existing copy, not a silent xAI call).
- Binary size: keep the Grok path table-driven; no extra HTTP stack.

## Stack / technologies

- Zig 0.16+, existing fx OAuth transport + agent stream provider seams.
- Tests: Zig unit tests in the owning files (fx convention). No Node runtime for the binary.

## UI/UX references

- Not provided (no Figma). CLI/TUI picker follows the existing Vercel team picker pattern.

## Constraints or dependencies

- No `XAI_API_KEY` in this cycle.
- Do not scrape grok.com cookies.
- Do not impersonate Pi’s OAuth referrer.
- Do not remove Vercel login.
- Do not declare ready without `./zig-out/bin/fx` on the happy path (repo AGENTS.md).
- Importing `~/.grok/auth.json` / Pi `auth.json` is out of scope.

## Out of scope this cycle

- Enterprise OIDC (`GROK_OIDC_ISSUER`)
- `XAI_API_KEY` fallback
- Device-code inside ACP
- Token-window headers (`x-ratelimit-*-tokens`)
- Renaming the `fx` binary
