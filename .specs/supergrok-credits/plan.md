# Requirements: Wire SuperGrok `/credits` and `/xai-usage`

Approved 2026-08-20. Canonical for implementation. Issue: [GitHub #2](https://github.com/MatheusBBarni/another-harness/issues/2).

## Feature objective

Stop SuperGrok `/credits` and `/xai-usage` from calling Vercel AI Gateway. On an `xai/…` model, fetch Grok billing and render plan / percent / period / reset / prepaid (and RPM when known). Non-`xai/` models keep the existing Gateway credits path.

## Expected behavior

1. **Routing (model wins, not last-login)**  
   Selected model `xai/` + non-empty remainder → `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with `Authorization: Bearer <apiKey()>`, `x-grok-client-mode: cli`, `x-grok-client-version: 1.0.4`.  
   Any other model → existing Gateway `/coding-agent/v1/credits`.  
   Never fall back to Gateway on a missing Grok key or Grok 401/403.

2. **Credential**  
   Refresh the **selected** source before reading the Bearer. TUI `preparePromptCredential` refreshes `grok_oauth` via `loadGrokLoginCredential`, not only `fx_login`. CLI already uses `.refresh_if_needed`. Preferred Grok refresh failure must not fall through to a Vercel/env key. Failed Grok refresh: record `grok_oauth`, print `Run fx login grok.`, open the picker (do not hardcode `fx_login`). Missing key after admission on `xai/`: same copy, **no HTTP**.

3. **One fetch, two renderers**  
   `/credits`, `/balance`, `fx credits` always use `renderCreditsText`.  
   `/xai-usage` uses `renderXaiUsageText` only when `origin = grok`; Gateway origin keeps the credits body.  
   TUI `/credits` uses the interactive body (no `[credits]` prefix — the notice is already labeled Credits). TUI `/xai-usage` uses the Pi notify line. CLI `fx credits` keeps `[credits]` prefixes.

4. **Snapshot**  
   Extend `CreditsSnapshot` with `origin`, `percent: ?u8`, `period`, `reset_at`, `prepaid_cents`, `rpm_remaining`, `rpm_limit`. Gateway leaves them null / `origin = gateway`. `deinit` frees new owned strings. JSON includes the new fields. Do not invent quota from local token counts.

5. **Errors**  
   Grok 401/403 → `Grok billing HTTP {status}. Run fx login grok.` Body and token never copied. Other Grok HTTP/transport/JSON errors: generic Grok billing error, still no Gateway.

6. **Status line**  
   Process cache on `App` (not `session.json`). Billing fields after a successful `/credits` or `/xai-usage` on `xai/`. RPM from Grok stream `x-ratelimit-*-requests` headers. Footer fragment only while the selected model is `xai/`. RPM-only: `{remaining}/{limit} RPM` — never invent `SG 0%`. No fetch on paint or startup.

7. **Tests**  
   Injected GET spies: `xai/` never calls Gateway; non-`xai/` never calls billing; 401 body has no token. Fake-app lookup includes `selected_model`. No new E2E owner.

## Identified edge cases

- Vercel key + `xai/` → Grok 401, relogin copy. Accepted.
- Grok login + non-`xai/` → Gateway with Grok token, Gateway copy. Accepted.
- Refresh failure must not silently send another source’s key.
- `percent = 0` from billing is real (`SG 0%`); missing percent is not.

## Stack

Zig 0.16, existing `std.http.Client` (same stack as `grok_stream`). Reuse `src/gateway/grok_billing.zig`. No new package, directory, or HTTP client. Native CLI/TUI only; WASM stub stays empty.

## UI/UX

No Figma. TUI: domain notice. Footer: `SG {n}% · {reset}` plus optional RPM.

## Constraints / dependencies

- pi-supergrok-usage contract for URL, headers, `toSnapshot`, footer, `/xai-usage` copy.
- `client.fetch` does not expose headers — Grok stream must use an API that does, in `grok_stream.zig`.
- Out of scope: `XAI_API_KEY`, token-window headers, ACP device-code, billing on startup/every paint, persisting usage in `session.json`.

## Grill-me decisions (beyond ADRs)

- `CreditsSnapshot.percent: ?u8` — typed percent for JSON, cache, and footer. Do not parse `used`.
- TUI `/credits` omits `[credits]` prefixes (notice topic is already Credits). CLI `fx credits` keeps them. TUI `/xai-usage` stays the Pi line.
