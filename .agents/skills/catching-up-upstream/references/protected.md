# Protected Grok surface

Do not delete these files. On conflict, keep fork behavior.

## Exclusive (ours)

- `src/core/auth/grok_oauth.zig`
- `src/core/auth/grok_session.zig`
- `src/core/auth/login_provider.zig`
- `src/core/gateway/openai_compat.zig`
- `src/gateway/grok_route.zig`
- `src/gateway/grok_stream.zig`
- `src/gateway/grok_billing.zig`
- `src/gateway/openai_sse.zig`
- `src/acp/grok_auth.zig`

## Shared (upstream + our wiring)

- `src/core/shared/types.zig` — `CredentialSource.grok_oauth`
- `src/core/auth/credentials.zig` — grok load/refresh
- `src/core/auth/oauth.zig` — test import of grok_oauth
- `src/core/auth/login_flow.zig` — picker, `runGrokLogin`, logout wipe
- `src/core/auth/auth_runtime.zig` — grok refresh
- `src/core/cli/cli_surface.zig` — `fx login grok|vercel`
- `src/core/agent/runtime/orchestrator.zig` — grok backend URL + openai_compat
- `src/core/agent/stream_provider.zig` — `openai_compat`
- `src/builtins/gateway.zig` — grok stream branch
- `src/builtins/commands.zig` — login/credits help
- `src/acp/types.zig` — `grok_oauth` authMethods
- `src/core/app/app_auth_runtime.zig` — logout clears grok preference

## Tests that must remain (names)

These strings must still appear as `test "..."` in the tree after merge:

- grok device authorization posts client id, grok scopes, and another-harness referrer
- grok refresh posts refresh_token grant to auth.x.ai
- grok token response becomes a session with auth.x.ai issuer
- logout deletes both session files even when one is missing
- login grok and vercel skip the picker; unknown args fail
- last grok login selects grok_oauth and xai/grok-4.6
- xai/grok-4.6 on grok creds hits chat completions without gateway headers
- xai/grok-4.5 uses responses; other grok ids stay on chat completions
- grok-active catalog is the four static ids
- openai sse maps text and tool calls to GatewayCompletion
- openai sse stop finish reason completes instead of interrupting
- openai compat body strips xai prefix and streams chat messages
- openai compat remaps gateway tools to function tools
- billing json becomes a super grok usage snapshot
- credits and xai-usage render snapshot; 401 asks for relogin without leaking the token
- status line shows SG percent, reset, and optional RPM window
- grok web search is server-side web_search
- ACP grok_oauth uses cached session or asks for fx login grok
