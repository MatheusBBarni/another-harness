# TechSpec: Additional Statusline Segments (cwd, branch)

## Executive Summary

Extend the existing opt-in footer statusline with two more boolean segments: `cwd` (workspace-root basename) and `branch` (named git branch). Reuse the current toggle, persist, picker, and paint contracts. Do not add `path`, dirty, ahead/behind, hostname, or a custom shell statusline.

App owns cached `cwd_label` and `branch_label` strings and refreshes them off paint when `workspace_root` or `.git/HEAD` mtime/inode changes. `buildHintLine` stays borrow-only. Branch comes from a cheap `.git/HEAD` file read, including `gitdir:` worktrees, and is omitted for non-repos and detached HEAD. The primary trade-off is a slightly stale or omitted branch on unusual git layouts in exchange for never spawning `git` or blocking paint.

There is no `_prd.md` in this repo. GitHub issue 6 is the product source.

## System Architecture

### Component Overview

- `src/core/config/settings_store.zig` and `src/core/config/config_runtime.zig` persist and parse `statusLine.cwd` / `statusLine.branch` as sibling booleans of sandbox, context, and session.
- `src/core/config/settings_catalog.zig` exposes the two new picker and settings-catalog choices.
- `src/core/slash_commands/command_specs.zig` and `src/builtins/commands.zig` extend `/statusline` help and completions.
- `src/core/app/app_commands.zig` toggles and persists the new keys through `handleStatuslineCommand` and the catalog change path.
- `src/core/app/app_lifecycle.zig`, `src/core/app/app_bootstrap_runtime.zig`, and `src/main.zig` load the flags and own the cached label buffers.
- `src/ui/render.zig` appends borrowed `cwd_label` then `branch_label` after session and before sandbox/context, dropping a segment that does not fit.
- Footer paint (`src/ui/footer/input_presentation.zig`) continues to pass `RenderContext.statusline` into `buildHintLine`. UI does not read git or the filesystem.

Data flow: user toggle → App flag + `UserSettingsPatch.statusline_item` → `~/.fx/settings.json` → startup flags → App cache refresh → borrowed `StatuslineItems` → hint line.

## Implementation Design

### Core Interfaces

```zig
pub const StatuslineItems = struct {
    sandbox_label: ?[]const u8 = null,
    context_used: u64 = 0,
    context_total: ?u32 = null,
    session_title: ?[]const u8 = null,
    cwd_label: ?[]const u8 = null,
    branch_label: ?[]const u8 = null,
};

pub const StatuslineItem = enum {
    sandbox,
    context,
    session,
    cwd,
    branch,
};
```

`buildHintLine` appends optional segments in this order: session title, cwd basename, branch name, sandbox, context. Empty or null labels are skipped. `appendStatusSegment` already omits an over-capacity segment without a dangling ` · `.

Branch parse contract:

- `ref: refs/heads/<name>` → `<name>`
- any other HEAD content, including detached SHA and `ref: refs/remotes/...` → omit
- missing `.git`, missing HEAD, or I/O/parse failure → omit, no notice

Cwd contract: last path component of `workspace_root`. Do not expand `~` and do not render the full path.

### Data Models

User settings (`~/.fx/settings.json`):

```json
{
  "statusLine": {
    "sandbox": false,
    "context": false,
    "session": false,
    "cwd": false,
    "branch": false
  }
}
```

Runtime App fields:

- `statusline_cwd: bool`
- `statusline_branch: bool`
- owned `cwd_label` and `branch_label` buffers, empty meaning omit
- cache identity: current `workspace_root` plus resolved HEAD path mtime/inode

Project `.fx.json` continues to ignore `statusLine`.

### API Endpoints

Not applicable. This is an interactive slash command and footer rendering change.

Public command surface:

- `/statusline` opens the compact picker, now including Cwd and Branch
- `/statusline cwd` and `/statusline branch` toggle and persist
- unknown args still error with the updated usage list: `sandbox, context, session, cwd, branch`

## Integration Points

Git is a local filesystem integration only. Read `.git` as a directory or a `gitdir:` file, then read HEAD with the existing small-file budget from `context_contract.Limits.git_metadata_file_bytes`. Do not spawn `git`, do not read the index, and do not inspect remotes.

## Impact Analysis

| Component | Impact Type | Description and Risk | Required Action |
|-----------|-------------|----------------------|-----------------|
| `settings_store.zig` | modified | New `StatuslineItem` tags and persist keys. Low risk if switch exhaustiveness is updated. | Extend enum, patch apply, legacy cleanup. |
| `config_runtime.zig` | modified | Parse/merge/source tracking for two bools. | Add fields, typed errors, tests. |
| `settings_catalog.zig` | modified | Picker and catalog rows grow. | Add choices and snapshot fields. |
| `command_specs.zig`, `commands.zig` | modified | Help and completions. | Add cwd/branch args. |
| `app_commands.zig` | modified | Toggle, persist, catalog apply. | Extend existing switches. |
| `app_lifecycle.zig`, `app_bootstrap_runtime.zig`, `main.zig` | modified | Flags and owned caches. | Load flags, own buffers, refresh off paint. |
| `session_commands.zig` | modified | Shadow notices for `statusLine.cwd` / `statusLine.branch`. | Extend item switch. |
| `render.zig` | modified | Two borrowed segments and clip tests. | Append after session. |
| `config-persistence.test.ts`, `tui-slash-menu.test.ts` | modified | Persist and picker coverage. | Assert new keys and labels. |

## Testing Approach

### Unit Tests

- `buildHintLine` shows cwd then branch after session and before sandbox.
- Over-narrow width drops branch, then cwd, without a dangling separator, while keeping permission mode and model when they fit.
- Basename of `/Users/me/projects/another-harness` is `another-harness`.
- HEAD `ref: refs/heads/main` yields `main`.
- Detached HEAD, missing `.git`, and unreadable HEAD omit branch.
- Settings parse/merge for `statusLine.cwd` and `statusLine.branch`, including typed invalid values.

### Integration Tests

- Extend `tests/e2e/config-persistence.test.ts` so `/statusline cwd` and `/statusline branch` persist to `statusLine.cwd` / `statusLine.branch`.
- Extend `tests/e2e/tui-slash-menu.test.ts` picker assertions to include Cwd and Branch.
- Do not add a new e2e file or corpus entry.

## Development Sequencing

### Build Order

1. Extend `StatuslineItem`, settings parse/merge/persist, and catalog ids. No dependencies.
2. Extend `/statusline` help, completions, toggle, picker, and shadow notices. Depends on step 1.
3. Add App flags, owned label buffers, and HEAD/basename refresh keyed by workspace root and HEAD mtime. Depends on step 1.
4. Extend `StatuslineItems` and `buildHintLine` append order plus Zig clip/omit tests. Depends on step 3.
5. Wire cached labels into footer `RenderContext.statusline`. Depends on steps 3 and 4.
6. Extend existing E2E persist and picker owners. Depends on steps 2 and 5.

### Technical Dependencies

None outside this checkout. No new packages, no git binary, no network.

## Monitoring and Observability

No new metrics or alerts. Failures omit the segment. Persistence failures reuse the existing statusline warning notice used by sandbox/context/session. Do not log on the paint path.

## Technical Considerations

### Key Decisions

- Decision: cheap `.git/HEAD` read. Rationale: paint budget. Trade-off: omit unusual layouts. Rejected: `git` spawn and full `collectGitInfo`.
- Decision: cwd + branch only. Rationale: YAGNI and acceptance. Rejected: `path` and dirty/ahead/behind.
- Decision: App-owned cached labels. Rationale: UI must not own product state. Rejected: paint-time filesystem reads.
- Decision: sibling `statusLine` booleans. Rationale: existing persist path. Rejected: nested identity object.
- Decision: refresh on workspace root and HEAD mtime. Rationale: catch checkouts without polling. Rejected: TTL and workspace-root-only cache.
- Decision: extend existing E2E owners. Rationale: same persist/picker product path. Rejected: a new e2e file.

### Known Risks

- HEAD mtime may not change on some filesystems after checkout. Mitigation: also key on inode when available; workspace_root changes always refresh.
- `gitdir:` can point outside the workspace. Mitigation: bounded read, omit on failure, never follow into git spawn.
- Footer assembler currently defaults `RenderContext.statusline` to empty. Implementation must copy App labels into that struct on the existing footer context build path, matching session title ownership.

## Architecture Decision Records

- [ADR-001: Cheap HEAD File Read For Branch](adrs/adr-001.md) — Resolve branch from `.git/HEAD` without spawning git.
- [ADR-002: Ship Cwd And Branch Only](adrs/adr-002.md) — Leave path and later markers out of this slice.
- [ADR-003: App-Owned Cached Identity Labels](adrs/adr-003.md) — Keep `buildHintLine` borrow-only.
- [ADR-004: Persist Cwd And Branch As statusLine Sibling Booleans](adrs/adr-004.md) — Reuse the existing toggle and persist path.
- [ADR-005: Refresh Identity Cache On Workspace Root And HEAD Mtime](adrs/adr-005.md) — Update labels off paint without polling.
- [ADR-006: Cover Cwd And Branch Through Existing Test Owners](adrs/adr-006.md) — Zig unit tests plus existing persist/picker E2E files.
