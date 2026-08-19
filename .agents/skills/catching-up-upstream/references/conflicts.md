# Conflict playbook

## Exclusive files

If git marks a protected exclusive file conflicted and upstream also touched it (rare):

```bash
git checkout --ours -- <path>
git add <path>
```

Then read the upstream version (`git show upstream/main:<path>` if it exists) only to cherry-pick non-Grok bugfixes by hand.

## Shared files

1. `git checkout --theirs -- <path>` is **wrong** if it drops Grok symbols.
2. Open the conflict. Keep **both**:
   - upstream logic/structure
   - our Grok branches (`grok_oauth`, `grok_backend`, `openai_compat`, `runGrokLogin`, `grok_stream`)
3. Search the file after resolve:

```bash
rg -n "grok_oauth|openai_compat|runGrokLogin|grok_stream|grok_route" <path>
```

If those symbols vanished from a shared file that used to have them, restore from `ORIG_HEAD` / our pre-merge commit.

## Abort

If the merge is a mess and Grok tests cannot be restored:

```bash
git merge --abort
```

Report what conflicted. Do not force-push. Do not reset `--hard` to upstream.

## After resolve

From the repo root:

```bash
python3 .agents/skills/catching-up-upstream/scripts/verify.py
```

Fix compile errors from upstream API renames **without** removing Grok call sites. Typical: function renamed in `orchestrator.zig` or `cli_surface.zig` — update our call to the new name.
