#!/usr/bin/env python3
"""Fetch remotes and print ahead/behind vs upstream/main."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from protected_paths import missing_files, missing_tests


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], check=False, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr.strip() or f"git {' '.join(args)} failed")
    return r.stdout.strip()


def main() -> None:
    root = Path(git("rev-parse", "--show-toplevel"))
    dirty = git("status", "--short")
    tracked_dirty = [ln for ln in dirty.splitlines() if not ln.startswith("??")]
    if tracked_dirty:
        print("DIRTY tracked files — stop and commit or stash before merge:")
        print("\n".join(tracked_dirty))
        raise SystemExit(2)

    remotes = git("remote")
    if "upstream" not in remotes.split():
        raise SystemExit("missing remote 'upstream' (vercel-labs/fx)")

    subprocess.run(["git", "fetch", "upstream"], check=True)
    subprocess.run(["git", "fetch", "origin"], check=False)

    counts = git("rev-list", "--left-right", "--count", "upstream/main...HEAD")
    behind, ahead = (int(x) for x in counts.split())
    print(f"branch={git('branch', '--show-current')}")
    print(f"behind_upstream={behind} ahead_of_upstream={ahead}")
    missing = missing_files(root)
    if missing:
        print("missing exclusive files:")
        print("\n".join(missing))
        raise SystemExit(3)
    absent_tests = missing_tests(root)
    if absent_tests:
        print("missing required tests:")
        print("\n".join(absent_tests))
        raise SystemExit(4)
    print("protected files and tests present")
    if behind == 0:
        print("up to date with upstream/main")
    else:
        print(f"ready to merge {behind} commit(s) from upstream/main")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
