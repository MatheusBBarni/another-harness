# TechSpec: Wire SuperGrok `/credits` and `/xai-usage`

Primary input: GitHub issue #2 (no `_prd.md`). Existing parser/renderers in `src/gateway/grok_billing.zig` are private and unused. `/credits` still always GET Vercel Gateway.

## Executive Summary

Keep a single `CreditsProvider.fetch` and a single `CreditsSnapshot`. Branch the HTTP target on the **selected model**: `xai/…` calls `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the SuperGrok Bearer and `x-grok-client-*` headers; every other model keeps `/coding-agent/v1/credits` on AI Gateway. `/credits` and `/xai-usage` share that fetch and split only at render time.

Primary trade-off: credits follow the selected model, not last-login. A Vercel login with an `xai/` model hits Grok billing (and asks for `fx login grok` if the token is wrong). A Grok login with a non-`xai/` model still hits Gateway.

## System Architecture

### Component Overview

- **`CreditsProvider` (`src/core/gateway/gateway_provider.zig`)** — lookup seam. Input gains `model`. Output stays `CreditsSnapshot`.
- **`fetchCredits` (`src/builtins/gateway.zig`)** — composition. If `grok_route.forModel(model) != null`, call Grok billing GET; else existing `fetchCreditsWithFetch` / Gateway GET.
- **`grok_billing.zig`** — parse billing JSON, map 401/403, render credits text, `/xai-usage` text, status-line fragment, RPM window. Export the functions that tests already cover.
- **Command router + `commandShowCredits` + CLI `.credits`** — one fetch; renderer chosen by invoked token (`/xai-usage` vs `/credits`/`/balance`/`fx credits`).
- **`grok_stream.zig`** — after a successful Grok response, parse `x-ratelimit-*-requests` and publish RPM to process cache.
- **App process cache + footer** — last SuperGrok percent/reset from a successful usage command; last RPM from stream headers. Footer appends the fragment only while the selected model is `xai/`.

Data flow:

```
slash/CLI
  → CreditsLookupInput { credential, tenant, model }
  → fetchCredits
       xai/  → grok billing GET → grok_billing.parse → CreditsSnapshot.origin=grok
       else  → Gateway GET     → existing JSON map  → CreditsSnapshot.origin=gateway
  → renderer (credits | xai_usage)
  → TUI notice / CLI stdout
  → on success + xai/: refresh App grok usage cache → footer
```

Grok stream (separate path): response headers → RPM cache → footer.

## Implementation Design

### Core Interfaces

```zig
pub const CreditsLookupInput = struct {
    credential: ?[]const u8,
    tenant: ?[]const u8,
    model: []const u8,
};

pub const CreditsView = enum { credits, xai_usage };

pub const CreditsSnapshot = struct {
    origin: enum { gateway, grok } = .gateway,
    balance: ?[]const u8 = null,
    used: ?[]const u8 = null,
    plan: ?[]const u8 = null,
    period: ?[]const u8 = null,
    reset_at: ?[]const u8 = null,
    prepaid_cents: ?i64 = null,
    rpm_remaining: ?u64 = null,
    rpm_limit: ?u64 = null,
    raw_json: ?[]const u8 = null,
    err_message: ?[]const u8 = null,
    // deinit frees owned strings including period and reset_at
};
```

Grok GET contract (injectable in tests):

```zig
pub const GrokBillingRequest = struct {
    access_token: []const u8,
    url: []const u8 = "https://cli-chat-proxy.grok.com/v1/billing?format=credits",
};

// Headers:
// Authorization: Bearer <access_token>
// x-grok-client-mode: cli
// x-grok-client-version: 1.0.4
```

`command_router.ParsedCommand.credits` becomes `credits: CreditsView`. Matching `/xai-usage` sets `.xai_usage`; `/credits` and `/balance` set `.credits`. `CommandHandlers.show_credits` takes that view. CLI `fx credits` is always `.credits`.

Export from `grok_billing.zig`: `parseBilling`, `renderCreditsText`, `renderXaiUsageText`, `renderBillingHttpError`, `parseRequestWindow`, `renderStatusLineFragment`. Keep `Snapshot` as parser output; copy into `CreditsSnapshot` in `fetchCredits`.

### Data Models

Grok billing JSON (already parsed):

- `subscription_tier` / `subscriptionTier` → `plan` (default `"SuperGrok"`)
- `config.creditUsagePercent` → `percent` 0–100
- `config.currentPeriod.type` ending `WEEKLY`/`MONTHLY` → period
- `config.currentPeriod.end` → normalized `reset_at`
- `config.prepaidBalance.val` → `prepaid_cents`

Map into `CreditsSnapshot`:

- `origin = .grok`
- `plan` = plan string
- `used` = `"{n}% {weekly|monthly|current period}"` so existing Gateway-shaped text still has a used line if a caller ignores origin
- `balance` = formatted prepaid dollars when present
- typed `period`, `reset_at`, `prepaid_cents`
- RPM fields filled later from process cache when rendering `/xai-usage` and the status line, not from billing JSON

Gateway snapshots leave new fields null and `origin = .gateway`. Existing `balance`/`used`/`plan` mapping does not change.

Do not invent quota from local token counts.

### API Endpoints

**Grok billing (selected model `xai/…`)**

- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`
- 200: parse with `parseBilling`
- 401/403: `err_message = renderBillingHttpError` (`Grok billing HTTP {status}. Run fx login grok.`). Body and token never copied into output
- other HTTP / transport / invalid JSON: generic Grok billing error, still no Gateway fallback

**Vercel Gateway (any non-`xai/` model)**

- existing `GET {gateway}/coding-agent/v1/credits[?teamId=…]`
- existing denial formatting via `formatHttpErrorMessage`

When model is `xai/` and credential is missing or not a Grok session, **do not** call Gateway. Return the relogin error.

## Integration Points

- **cli-chat-proxy.grok.com** — SuperGrok Bearer from `app.auth.apiKey()` / startup credential when the user is on an `xai/` model. No retry on 401/403. No second HTTP stack; `std.http.Client` like `grok_stream`.
- **ai-gateway.vercel.sh** — unchanged for non-`xai/` models. WASM `fetchCredits` stub stays empty; this cycle is native CLI/TUI.

## Impact Analysis

| Component | Impact Type | Description and Risk | Required Action |
|-----------|-------------|----------------------|-----------------|
| `gateway_provider.CreditsLookupInput` | modified | Callers that omit `model` would default to Gateway and revive the bug | Add `model`; update CLI, TUI, probes, WASM |
| `output_contracts.CreditsSnapshot` | modified | New fields + `deinit` | Extend renderText/JSON; Gateway tests still pass |
| `builtins/gateway.zig` `fetchCredits` | modified | Dual GET; risk of leaking token in errors | Branch on `grok_route.forModel`; spies |
| `grok_billing.zig` | modified | Export existing fns | No new package |
| `command_router` / `app_commands.commandShowCredits` | modified | Alias view + pass `selected_model` | `/xai-usage` renderer; cache refresh |
| `cli_surface` credits | modified | Pass `startup.selected_model` | Same branch as slash |
| `grok_stream.zig` | modified | Must read response headers; `client.fetch` cannot | Switch to a request that exposes headers |
| `ui/render.zig` `StatuslineItems` | modified | Optional SuperGrok fragment | Append only for `xai/` |
| `wasm_core_main.zig` | modified | Compile against new input | Ignore model; still empty snapshot |
| README / usage docs | modified | SuperGrok `/credits` and `/xai-usage` | User-facing copy only |

## Testing Approach

### Unit Tests

Injected GET spies on `fetchCredits` (ADR-005):

- model `xai/grok-4.6`: billing URL + `Authorization: Bearer …` + `x-grok-client-mode: cli` + `x-grok-client-version: 1.0.4`; Gateway spy call count = 0
- model `zai/glm-5.2`: existing Gateway path; billing spy call count = 0
- Grok 401/403: message contains `fx login grok`; token bytes absent even if the body is the token
- existing Gateway team-query / malformed JSON / owned-field tests unchanged

`grok_billing` tests stay; they become tests of public fns.

`CreditsSnapshot` render:

- Grok origin `/credits` text matches `renderCreditsText` (plan, `% weekly`, prepaid)
- Grok origin `/xai-usage` text matches Pi notify line including reset and optional RPM
- Gateway JSON still `{kind, balance, used, plan}`; Grok JSON includes new nullable fields
- `deinit` frees `period` and `reset_at`

`commandShowCredits` fake app: lookup input includes `selected_model`. Router: `/xai-usage` → `.xai_usage`, `/credits`/`/balance` → `.credits`.

`parseRequestWindow` / stream: headers `"8299"`/`"8300"` → RPM cache; missing/non-numeric → no RPM.

### Integration Tests

No new E2E file. Keep `tests/e2e/tui-slash-extra.test.ts` Gateway 403 case as the Vercel path. Live Grok billing stays out of PGSO (credentialed network).

## Development Sequencing

### Build Order

1. Export `grok_billing` APIs; extend `CreditsSnapshot` + `deinit` + render/JSON tests — no dependencies
2. Add `CreditsLookupInput.model`; branch `fetchCredits` with injected spies — depends on step 1
3. Thread `CreditsView` through router/TUI/CLI; pass selected model into fetch; `/xai-usage` renderer — depends on step 2
4. Capture Grok RPM headers; process cache; footer fragment when model is `xai/` — depends on steps 1 and 3
5. Docs (`README` usage/credits, slash help if copy is still “gateway only”) — depends on steps 3 and 4

### Technical Dependencies

- Grok billing URL and headers are the pi-supergrok-usage contract; do not invent a second quota source
- `std.http.Client.fetch` does not expose headers; Grok stream must use a request API that does
- No new directories or HTTP client

## Monitoring and Observability

- `debug_trace` scope `credits`: `origin=grok|gateway model=… status=…` with no Authorization header
- Do not log billing JSON that might echo tokens
- No new metrics/alerts this cycle

## Technical Considerations

### Key Decisions

- **One fetch, two renderers** — avoids a second provider and a new CLI command. Cost: router must carry the alias.
- **Model wins** — same prefix as `grok_route.forModel`. Cost: last-login no longer owns credits (issue text overridden).
- **Extend `CreditsSnapshot`** — JSON and status cache share typed fields. Cost: Gateway JSON grows null keys.
- **Process cache, no paint-time fetch** — percent/reset after `/credits` or `/xai-usage`; RPM after a Grok turn. Cost: empty SuperGrok percent until first successful usage command this process.
- **Spies, not e2e** — proves Gateway isolation at the seam that currently always calls Gateway.

### Known Risks

- TUI forgets to pass `selected_model` → silent Gateway 401 on SuperGrok. Mitigate with the fake-app lookup test.
- `xai/` + Vercel API key → Grok 401 `Run fx login grok.` Accepted.
- Grok login + non-`xai/` model → Gateway 401 with Gateway copy. Accepted.
- Header capture may need a `grok_stream` request-shape change. Keep it in that file; do not add a second HTTP stack.
- Token leak in error bodies. `renderBillingHttpError` ignores the body; spies assert absence.

Out of scope: `XAI_API_KEY`, token-window headers, ACP device-code, fetching billing on startup or every footer paint, persisting usage in `session.json`.

## Architecture Decision Records

- [ADR-001: One CreditsProvider fetch, two command renderers](adrs/adr-001.md) — `/xai-usage` stays an alias; renderer is selected by invoked token.
- [ADR-002: Route billing by selected xai/ model](adrs/adr-002.md) — `xai/` uses Grok billing; everything else uses Gateway.
- [ADR-003: Extend CreditsSnapshot with SuperGrok fields](adrs/adr-003.md) — typed period, reset, prepaid, RPM on the existing snapshot.
- [ADR-004: Process-local SuperGrok status-line cache](adrs/adr-004.md) — cache on `App`; no paint-time fetch; RPM from stream headers.
- [ADR-005: Prove Gateway isolation with injected fetch spies](adrs/adr-005.md) — unit spies only; no new E2E owner.
