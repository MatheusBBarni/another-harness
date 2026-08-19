"""Grok-owned paths and test names. Used by status.py and verify.py."""

from pathlib import Path

EXCLUSIVE = [
    "src/core/auth/grok_oauth.zig",
    "src/core/auth/grok_session.zig",
    "src/core/auth/login_provider.zig",
    "src/core/gateway/openai_compat.zig",
    "src/gateway/grok_route.zig",
    "src/gateway/grok_stream.zig",
    "src/gateway/grok_billing.zig",
    "src/gateway/openai_sse.zig",
    "src/acp/grok_auth.zig",
]

SHARED = [
    "src/core/shared/types.zig",
    "src/core/auth/credentials.zig",
    "src/core/auth/oauth.zig",
    "src/core/auth/login_flow.zig",
    "src/core/auth/auth_runtime.zig",
    "src/core/cli/cli_surface.zig",
    "src/core/agent/runtime/orchestrator.zig",
    "src/core/agent/stream_provider.zig",
    "src/builtins/gateway.zig",
    "src/builtins/commands.zig",
    "src/acp/types.zig",
    "src/core/app/app_auth_runtime.zig",
]

REQUIRED_TESTS = [
    "grok device authorization posts client id, grok scopes, and another-harness referrer",
    "grok refresh posts refresh_token grant to auth.x.ai",
    "grok token response becomes a session with auth.x.ai issuer",
    "logout deletes both session files even when one is missing",
    "login grok and vercel skip the picker; unknown args fail",
    "last grok login selects grok_oauth and xai/grok-4.6",
    "xai/grok-4.6 on grok creds hits chat completions without gateway headers",
    "xai/grok-4.5 uses responses; other grok ids stay on chat completions",
    "grok-active catalog is the four static ids",
    "openai sse maps text and tool calls to GatewayCompletion",
    "openai sse stop finish reason completes instead of interrupting",
    "openai compat body strips xai prefix and streams chat messages",
    "openai compat remaps gateway tools to function tools",
    "billing json becomes a super grok usage snapshot",
    "credits and xai-usage render snapshot; 401 asks for relogin without leaking the token",
    "status line shows SG percent, reset, and optional RPM window",
    "grok web search is server-side web_search",
    "ACP grok_oauth uses cached session or asks for fx login grok",
]


def missing_files(root: Path) -> list[str]:
    return [p for p in EXCLUSIVE if not (root / p).is_file()]


def missing_tests(root: Path) -> list[str]:
    blob = []
    for rel in EXCLUSIVE + SHARED:
        path = root / rel
        if path.is_file():
            blob.append(path.read_text(encoding="utf-8", errors="replace"))
    text = "\n".join(blob)
    return [name for name in REQUIRED_TESTS if f'test "{name}"' not in text]
