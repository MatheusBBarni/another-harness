# TDD Plan — Wire SuperGrok `/credits` and `/xai-usage`

Canonical implementation plan. Requirements: `.specs/supergrok-credits/plan.md`. Tests live in the owning Zig files, at the seams below only. One RED → GREEN slice at a time.

## Public interface

| Seam | Change |
|---|---|
| `CreditsLookupInput` | add `model: []const u8` |
| `CreditsSnapshot` | add `origin`, `percent: ?u8`, `period`, `reset_at`, `prepaid_cents`, `rpm_*`; JSON + `deinit` |
| `fetchCredits` | branch on `xai/` remainder; injectable Grok GET next to existing Gateway GET |
| `grok_billing` | export parse/render/error/window/fragment (tests already cover them) |
| `ParsedCommand.credits` | `CreditsView { credits, xai_usage }`; `show_credits` takes the view |
| `commandShowCredits` / CLI credits | pass `selected_model`; TUI notice = CLI renderer |
| `preparePromptCredential` | refresh selected `grok_oauth`; recover with that source |
| `loadGrokLoginCredential` | surface refresh errors; no precedence fallthrough |
| App cache + `StatuslineItems` | process-local SuperGrok fragment; RPM from `grok_stream` headers |

Deep module: `grok_billing` stays the parser/renderer. `fetchCredits` only chooses URL and copies into `CreditsSnapshot`.

## Behaviors to test (in order)

1. **Tracer — `xai/` credits never touch Gateway**  
   Model `xai/grok-4.6` GETs `cli-chat-proxy.grok.com/v1/billing?format=credits` with Bearer + `x-grok-client-mode: cli` + `x-grok-client-version: 1.0.4`. Gateway GET is not called.

2. **Non-`xai/` credits stay on Gateway**  
   Model `zai/glm-5.2` still hits `/coding-agent/v1/credits`. Billing GET is not called.

3. **Grok 401/403 do not leak the token**  
   Output contains `Run fx login grok.` Token bytes are absent even if the HTTP body is the token.

4. **Grok snapshot renders `/credits` and JSON with percent**  
   Text matches `renderCreditsText` (plan, `% weekly`, prepaid). JSON includes `origin` and `percent`. `deinit` frees `period` and `reset_at`.

5. **`/xai-usage` is Grok-origin-only Pi text**  
   `origin = grok` → Pi notify line (plan, %, period, reset, prepaid, optional RPM). `origin = gateway` → existing credits body.

6. **Slash view + TUI fetch pass the selected model**  
   `/xai-usage` → `.xai_usage`; `/credits` and `/balance` → `.credits`. Fake-app lookup includes `selected_model`. TUI notice text matches the CLI renderer.

7. **Missing or failed Grok credential does no HTTP**  
   `xai/` with no `apiKey()`, or selected `grok_oauth` refresh failure: no billing GET, no Gateway GET, `Run fx login grok.` Recovery records `grok_oauth`, not `fx_login`.

8. **Footer shows cached SuperGrok usage on `xai/`**  
   After a successful usage snapshot: `SG {n}% · {reset}`. After stream headers: `{remaining}/{limit} RPM`. RPM-only never invents `SG 0%`. Non-`xai/` omits the fragment.

## Out of scope for this cycle

- New E2E / PGSO owner (keep existing Gateway 403 in `tui-slash-extra`)
- WASM credits behavior (compile stub only)
- Docs/README copy
- `XAI_API_KEY`, ACP, paint-time/startup billing, `session.json` persistence
- Successful-refresh rewriting the Grok session file (chat already owns that path; slice 7 covers failure)
