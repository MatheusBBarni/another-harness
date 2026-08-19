#!/usr/bin/env python3
"""Merge is successful only if protected tests exist and zig build test passes."""

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
    missing = missing_files(root)
    if missing:
        print("FAIL missing exclusive files:")
        print("\n".join(missing))
        raise SystemExit(3)
    absent = missing_tests(root)
    if absent:
        print("FAIL required tests missing from tree:")
        print("\n".join(absent))
        raise SystemExit(4)

    print("protected tests present — running zig build test")
    proc = subprocess.run(["zig", "build", "test", "--summary", "new"], cwd=root)
    if proc.returncode != 0:
        print("FAIL zig build test")
        raise SystemExit(proc.returncode)
    print("OK merge verification passed")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
