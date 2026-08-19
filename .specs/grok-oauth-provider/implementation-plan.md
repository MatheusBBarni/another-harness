# TDD Plan — Grok OAuth provider

Canonical implementation plan. Tests live in the owning Zig files, at the seams below only.

## Public interface

| Seam | Public interface |
|---|---|
| CLI login parse | `fx login`, `fx login grok`, `fx login vercel` |
| Grok OAuth protocol | device-code + token form (injected transport, same as `oauth.zig`) |
| Grok session | parse/stringify `~/.fx/grok-auth.json` |
| Credentials | `CredentialSource.grok_oauth`, last-login preference |
| Logout | wipe Vercel **and** Grok |
| Model route | `xai/grok-…` → strip prefix, completions vs responses |
| OpenAI stream | request body + SSE → existing `GatewayCompletion` |
| Catalog | static four Grok ids when Grok is active |
| Billing | parse `cli-chat-proxy` JSON → snapshot |
| Usage commands | `/credits` + `/xai-usage` text |
| Status line | `SG {n}% · {reset}` (+ RPM when present) |
| Grok search | request includes xAI `{ "type": "web_search" }` |
| ACP | method `grok_oauth`; cached session or “run fx login grok” |

## Behaviors to test (in order)

1. **Tracer — Grok device authorization request**  
   POST to `https://auth.x.ai/oauth2/device/code` with client id, scopes, and `referrer=another-harness`.
2. **Grok token response becomes a session**  
   access + refresh + expiry persist; issuer is `https://auth.x.ai`, not Vercel.
3. **Expired Grok access token refreshes**  
   `grant_type=refresh_token` against `https://auth.x.ai/oauth2/token`.
4. **`fx login grok` / `fx login vercel` skip the picker**  
   unknown arg still fails with usage.
5. **`fx logout` deletes both session files**  
   succeeds when only one (or neither) exists.
6. **Last Grok login selects `grok_oauth` and default `xai/grok-4.6`**  
   Vercel login restores Gateway ownership.
7. **`xai/grok-4.6` on Grok creds hits chat completions**  
   model sent as `grok-4.6`; no Gateway LM headers.
8. **OpenAI SSE maps to `GatewayCompletion`**  
   text + tool calls land on existing callbacks.
9. **`xai/grok-4.5` uses `/v1/responses`**  
   other three catalog ids stay on chat completions.
10. **Grok-active catalog is the four static ids**  
    `xai/grok-4.6`, `xai/grok-4.5`, `xai/grok-4.3`, `xai/grok-build-0.1`.
11. **Billing JSON → usage snapshot**  
    weekly %, reset, prepaid, plan (same fields as pi-supergrok-usage).
12. **`/credits` and `/xai-usage` render that snapshot**  
    401/403 say re-login; token never appears in output.
13. **Status line shows `SG {n}% · {reset}`**  
    RPM appended from `x-ratelimit-*-requests` after a Grok response.
14. **Grok web search is server-side `web_search`**  
    not Vercel Perplexity/Parallel.
15. **ACP `grok_oauth` uses the cached session**  
    missing session → run `fx login grok`.

## Out of scope for this cycle

- Enterprise OIDC, `XAI_API_KEY`, importing `~/.grok/auth.json`
- Device-code inside ACP
- Token-window headers
- Live-network e2e (credentialed; PGSO exclusion)
- Interactive picker key-handling (reuse team-picker; cover via arg path + a snapshot of picker labels if cheap)
