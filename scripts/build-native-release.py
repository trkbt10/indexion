#!/usr/bin/env python3
"""
Drive `moon build --target native --release` with a workaround for Windows'
CreateProcessW 32k cmdline limit on the `moonc link-core` step.

On macOS and Linux this script is a thin pass-through to `moon build`.

On Windows the `moonc link-core` invocation's argv exceeds the 32767-char
limit of a single CreateProcessW call. We cannot resume after the
failure because moon's n2 build database records the failed step and
re-issues the same invocation on the next `moon build`.

So on Windows we:

  1. Run `moon build --target native --release` once. moon's setup
     phase generates `_build/native/release/build/all_pkgs.json` and
     then n2 starts executing the build graph. All upstream steps —
     C-stub compilation, static-library archiving, and the ~227
     `moonc build-package` calls — succeed and persist their outputs
     to disk. n2 then attempts `moonc link-core …`, CreateProcessW
     fails, and `moon build` exits non-zero. The intermediate
     artifacts remain on disk.

  2. Detect the "filename or extension is too long" message (the
     CreateProcessW signature) and recover by running the two
     remaining build steps ourselves, with the `moonc link-core`
     invocation routed through `moonc -rsp-file <rsp>`:

       a. `moonc -rsp-file <rsp>` produces
          `_build/native/release/build/cmd/indexion/indexion.c`.

       b. The final `cc` / `cl` step links `indexion.c` and the
          stub .a archives into `indexion.exe`. (Its argv is
          well under 32k.)

     Both commands are extracted from `moon build --dry-run`'s
     toposorted output, with `$MOON_HOME` placeholders expanded.

The recovery is invariant to package count: more src/ or cmd/
packages do not regress the response file (it has no length limit),
and the final cc step's argv stays in the few-KB range regardless.

References:
  - moonc's `-rsp-file <path>` global option ("Read additional
    arguments from a response file"; one arg per line). See
    `moonc --help`.
  - moon's `lower_link_core` in
    `crates/moonbuild-rupes-recta/src/build_lower/lower_build.rs`
    does not yet route through a response file.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path


CREATE_PROCESS_TOO_LONG = "filename or extension is too long"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def find_dry_run_steps(moon_home: str) -> tuple[list[str], list[str]]:
    """Extract the `moonc link-core` and final `cc … -o …/indexion.exe` argvs
    from `moon build --dry-run`. Both have `$MOON_HOME` expanded."""
    dr = subprocess.run(
        ["moon", "build", "--target", "native", "--release", "--dry-run"],
        capture_output=True,
        text=True,
        check=True,
    )
    link_line = None
    final_cc_line = None
    for line in dr.stdout.splitlines():
        if link_line is None and line.startswith("moonc link-core"):
            link_line = line
        elif (
            final_cc_line is None
            and "indexion.exe" in line
            and " -o " in line
            and not line.startswith("moonc")
        ):
            final_cc_line = line
    if link_line is None or final_cc_line is None:
        raise RuntimeError(
            "could not locate `moonc link-core` and/or final cc step in `moon build --dry-run` output"
        )

    def expand(line: str) -> list[str]:
        return [t.replace("$MOON_HOME", moon_home) for t in shlex.split(line)]

    return expand(link_line), expand(final_cc_line)


def recover_link_and_final_cc() -> int:
    moon_home = os.environ.get("MOON_HOME") or str(Path.home() / ".moon")
    link_argv, final_cc_argv = find_dry_run_steps(moon_home)

    # 1) moonc link-core via -rsp-file.
    # link_argv[0] is "moonc" (normalized by --dry-run); we re-resolve
    # via PATH so subprocess uses the actual .exe on Windows.
    # link_argv[1:] is "link-core" + all .core paths + flags.
    rsp_path = Path(tempfile.gettempdir()) / "indexion-moonc-link.rsp"
    rsp_path.write_text("\n".join(link_argv[1:]) + "\n", encoding="utf-8")
    print(
        f"[build-native-release] moonc -rsp-file {rsp_path}  ({len(link_argv) - 1} args)",
        flush=True,
    )
    rc = subprocess.run([link_argv[0], "-rsp-file", str(rsp_path)])
    if rc.returncode != 0:
        return rc.returncode

    # 2) Final cc step: compile indexion.c + link stubs/runtime → indexion.exe.
    print(
        f"[build-native-release] {final_cc_argv[0]} -o … indexion.exe",
        flush=True,
    )
    return subprocess.run(final_cc_argv).returncode


def main() -> int:
    os.chdir(repo_root())

    print(
        "[build-native-release] moon build --target native --release",
        flush=True,
    )
    r = subprocess.run(
        ["moon", "build", "--target", "native", "--release"],
        capture_output=True,
        text=True,
    )
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode == 0:
        return 0

    if CREATE_PROCESS_TOO_LONG not in (r.stdout + r.stderr):
        return r.returncode

    print(
        "[build-native-release] CreateProcessW cmdline limit hit; recovering link-core + final cc",
        flush=True,
    )
    return recover_link_and_final_cc()


if __name__ == "__main__":
    sys.exit(main())
