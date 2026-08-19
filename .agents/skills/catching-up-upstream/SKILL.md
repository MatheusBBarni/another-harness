---
name: catching-up-upstream
description: Merge vercel-labs/fx into this another-harness fork without dropping Grok OAuth work. Use when the fork is behind upstream, GitHub says commits behind, or the user asks to catch up, sync, or merge main from the original repo.
---

# Catching up upstream

Bring `upstream/main` (`vercel-labs/fx`) into this fork. **Never delete or revert Grok OAuth work.** A merge is successful only if **our tests still pass**.

This skill lives in-repo at `.agents/skills/catching-up-upstream/`. `.claude/skills/catching-up-upstream` is a symlink to that directory.

## When to use

- GitHub: "N commits behind `vercel-labs/fx`"
- User: catch up, sync upstream, merge original main
- After a long stretch of fork-only work

## Remotes

| Remote | Repo |
|---|---|
| `origin` | `MatheusBBarni/another-harness` |
| `upstream` | `https://github.com/vercel-labs/fx.git` |

If `upstream` is missing: `git remote add upstream https://github.com/vercel-labs/fx.git`

## Workflow

Copy and check off:

```
- [ ] 1. Dirty tree: stop if tracked files are dirty (untracked OK if unrelated)
- [ ] 2. python3 .agents/skills/catching-up-upstream/scripts/status.py
- [ ] 3. If behind == 0: report up to date, stop
- [ ] 4. git merge upstream/main --no-edit
- [ ] 5. Resolve conflicts (see references/conflicts.md)
- [ ] 6. python3 .agents/skills/catching-up-upstream/scripts/verify.py
- [ ] 7. If verify fails: fix until it passes. Do not push a red merge.
- [ ] 8. Report: behind/ahead, conflict files, verify output
```

Run scripts from the **repo root**.

## Hard rules

- Do **not** `reset --hard` onto upstream.
- Do **not** drop commits that add Grok OAuth, Codex seams, or our tests.
- On conflict in a **protected** path: keep our side, then replay upstream hunks that do not undo Grok behavior.
- On conflict in a **shared** path (`orchestrator.zig`, `credentials.zig`, `cli_surface.zig`, `gateway.zig`, `types.zig`, `commands.zig`, `auth_runtime.zig`): take upstream structure, **re-apply** our Grok wiring.
- Never resolve by deleting `grok_*`, `openai_compat.zig`, `openai_sse.zig`, or `login_provider.zig`.

## Success

`scripts/verify.py` exits 0:

1. Every protected test name still exists in the tree
2. `zig build test` exits 0

If either fails, the merge is **not** successful.

## Details

- Protected files and test names: [references/protected.md](references/protected.md)
- Conflict playbook: [references/conflicts.md](references/conflicts.md)
