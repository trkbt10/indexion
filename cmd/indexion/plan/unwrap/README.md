# indexion plan unwrap

Detect unnecessary wrapper functions and plan their removal.

## Overview

Scans source files for wrapper functions whose body is a single delegation
call with no added logic. Callers should use the delegate directly.
Supports report, dry-run preview, and auto-fix modes.

## Modes

- (default): Report wrappers found (md/json/text)
- `--dry-run`: Preview all edits (call site replacements + definition deletions)
- `--fix`: Apply edits to files

## Usage

```bash
indexion plan unwrap [options] <directory>
indexion plan unwrap --dry-run --include='*.mbt' src/
indexion plan unwrap --fix --include='*.mbt' --exclude='*_wbtest.mbt' src/
```

## API

- **`parse_args`** (Function) — Parse CLI arguments into an UnwrapConfig starting from the given index.
- **`default`** (Function) — Create a default configuration with report mode and markdown format.
- **`run`** (Function) — Entry point: detect wrappers and report, preview, or apply fixes.
- **`apply_fixes`** (Function) — Apply fixes: replace call sites and delete wrapper definitions.
- **`UnwrapEntry`** (Struct) — A single detected wrapper function to unwrap.
- **`UnwrapPlanJSON`** (Struct) — Complete unwrap candidate plan.
- **`render_dry_run`** (Function) — Render dry-run preview.
- **`render_json`** (Function) — Render as JSON string.
- **`UnwrapPlanConfig`** (Struct) — Configuration summary.
- **`render_text`** (Function) — Render as plain text.

And 42 more symbols.
