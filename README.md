```
 ⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⠀⠀⢰⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⣠⣶⣿⣿⣷⣶⡶⣶⣶⣆⠀⠀⠀⣴⣶⣶⠆
 ⠀⠀⠀⠉⢹⣿⣿⠉⠉⠀⠘⢿⣿⣧⣀⣾⣿⡿⠃⠀             Tiny, open, embeddable, native coding agent.
 ⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⠻⣿⣿⣿⠟⠀⠀⠀
 ⠀⠀⠀⢀⣿⣿⠃⠀⠀⠀⠀⢠⣦⠘⢿⣿⣷⡀⠀⠀             Fork of vercel-labs/fx with subscription logins.
 ⠀⠀⠀⣸⣿⡟⠀⠀⠀⠀⣰⣿⣿⠗⠀⠻⣿⣿⣄⠀
 ⠀⠀⠀⣿⣿⠇⠀⠀⠀⠾⠿⠿⠋⠀⠀⠀⠘⠿⠿⠦             ⚠ Experimental. Use at your own risk.
  ⠀⣸⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
```

**another-harness** is a direct fork of [vercel-labs/fx](https://github.com/vercel-labs/fx): a Zig coding-agent CLI aimed at a Unix-shell feel rather than a heavy TUI.

This fork keeps fx’s harness, tools, and Vercel AI Gateway path, and adds **sign-in with real model subscriptions** so you can run frontier models without a provider API key.

| Login | Status |
| --- | --- |
| **SuperGrok / X Premium** | Works: `fx login grok` → Grok models on `api.x.ai` |
| **ChatGPT / Codex** | In development ([#1](https://github.com/MatheusBBarni/another-harness/issues/1)) |
| **Vercel** | Unchanged: `fx login` / `fx login vercel` or `fx setup` |

> [!IMPORTANT]
> The binary is still named `fx` and uses `~/.fx/`. Installing this build **collides** with official fx. Use `./zig-out/bin/fx` from this checkout until the rename ([#4](https://github.com/MatheusBBarni/another-harness/issues/4)).

> [!NOTE]
> Upstream docs still apply for permissions, skills, MCP, and ACP: [fx.sh/docs](https://fx.sh/docs). This README only covers how the fork differs.

## Features

- Everything in upstream fx: interactive shell, `fx ask`, ACP, WASM embed, skills, MCP, subagents
- SuperGrok OAuth (device code) — no `XAI_API_KEY`
- Last login owns the session and default model (`xai/grok-4.6` after Grok sign-in)
- Vercel AI Gateway still available for other models
- Tracks `vercel-labs/fx` via `upstream`; catch-up workflow in `.agents/skills/catching-up-upstream`

## Build

Requires [Zig 0.16.0+](https://ziglang.org/download/):

```bash
git clone https://github.com/MatheusBBarni/another-harness.git
cd another-harness
zig build -Doptimize=ReleaseSafe
./zig-out/bin/fx
```

Do **not** use `curl … fx.sh/setup.sh` for this fork. That installs official fx.

## Run

```bash
cd your_project
/path/to/another-harness/zig-out/bin/fx
```

Sign in:

```bash
./zig-out/bin/fx login          # picker: Vercel or Grok
./zig-out/bin/fx login grok     # SuperGrok / X Premium
./zig-out/bin/fx login vercel   # Vercel AI Gateway
./zig-out/bin/fx setup          # Gateway API key
```

The current directory is the workspace. Type a prompt or `/help`.

```bash
./zig-out/bin/fx ask "explain the changes in this repository"
./zig-out/bin/fx session resume last
```

Starts in `auto` permission mode. See [Permissions](https://fx.sh/docs/configure-fx/permissions).

## Embed and extend

Same surfaces as upstream fx:

| Surface | Use |
| --- | --- |
| `fx acp` | Agent Client Protocol |
| `createFxAgent()` | JS host + `fx-core.wasm` |
| `createFxTerminal()` | Interactive terminal + `fx-term.wasm` |

Skills, MCP, and subagents: [fx capabilities](https://fx.sh/docs/capabilities/skills). WASM SDK: [sdk/README.md](sdk/README.md).

## Documentation

- Upstream product docs: [fx.sh/docs](https://fx.sh/docs)
- This fork: [issues](https://github.com/MatheusBBarni/another-harness/issues) (Codex OAuth, SuperGrok usage, subagents, rename)

## Credits

Interface sounds by [cuelume](https://github.com/Danilaa1/cuelume).
