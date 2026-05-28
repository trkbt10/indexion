#!/usr/bin/env python3
"""
Drive `moon build --target native --release` with a workaround for Windows'
CreateProcessW 32k cmdline limit on the `moonc link-core` step.

Strategy:
1. Try `moon build --target native --release`. On macOS/Linux this just works.
2. If the build fails with "filename or extension is too long" (the
   Windows CreateProcessW error surfaced when moonc link-core exceeds the
   32767-char cmdline limit), recover by:
   a) extracting the link-core args from `moon build --dry-run` output,
   b) writing them one-per-line to a response file,
   c) invoking `moonc -rsp-file <rsp>` ourselves to produce the .c output,
   d) re-running `moon build` so its incremental layer picks up the
      produced .c and continues with the C compile + link steps.

Why this approach:
- moon's `--dry-run` prints the full link-core arg list as a single
  shlex-style line. `$MOON_HOME` placeholders are expanded here.
- moonc supports `-rsp-file <path>` as a global option (one arg per line).
- moon itself does not (yet) route link-core through rsp-file (see
  `lower_link_core` in moonbitlang/moon's `moonbuild-rupes-recta` crate),
  so we bridge the gap downstream. Response files have no length limit,
  so adding more packages does not regress the Windows build.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path


CMDLINE_TOO_LONG = "filename or extension is too long"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def run_moon_build() -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "build", "--target", "native", "--release"],
        capture_output=True,
        text=True,
    )


def extract_link_core_args() -> list[str]:
    dr = subprocess.run(
        ["moon", "build", "--target", "native", "--release", "--dry-run"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in dr.stdout.splitlines():
        if line.startswith("moonc link-core"):
            toks = shlex.split(line)
            moon_home = os.environ.get("MOON_HOME") or str(Path.home() / ".moon")
            # Drop "moonc"; expand the $MOON_HOME placeholder that --dry-run
            # always emits regardless of platform.
            return [a.replace("$MOON_HOME", moon_home) for a in toks[1:]]
    raise RuntimeError("no `moonc link-core` line in `moon build --dry-run` output")


def main() -> int:
    os.chdir(repo_root())

    print("[build-native-release] moon build --target native --release", flush=True)
    first = run_moon_build()
    sys.stdout.write(first.stdout)
    sys.stderr.write(first.stderr)
    if first.returncode == 0:
        return 0

    combined = first.stdout + first.stderr
    if CMDLINE_TOO_LONG not in combined:
        return first.returncode

    print(
        "[build-native-release] cmdline length exceeded; recovering via moonc -rsp-file",
        flush=True,
    )

    args = extract_link_core_args()
    rsp_path = Path(tempfile.gettempdir()) / "indexion-moonc-link.rsp"
    rsp_path.write_text("\n".join(args) + "\n", encoding="utf-8")
    print(
        f"[build-native-release] wrote {len(args)} args to {rsp_path}", flush=True
    )

    print("[build-native-release] moonc -rsp-file", str(rsp_path), flush=True)
    rc = subprocess.run(["moonc", "-rsp-file", str(rsp_path)])
    if rc.returncode != 0:
        return rc.returncode

    print(
        "[build-native-release] moon build --target native --release  (resume)",
        flush=True,
    )
    resume = subprocess.run(["moon", "build", "--target", "native", "--release"])
    return resume.returncode


if __name__ == "__main__":
    sys.exit(main())
