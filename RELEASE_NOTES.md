# v0.2.0

## Highlights

- **Magic String Detection** — `plan refactor` now detects string literals repeated across multiple files, surfacing potential constants and SoT violations
- **Unified SoT** — All commands share the same registry loading, output handling, and CLI conventions
- **Zero Warnings** — Eliminated all 46 compiler warnings

## New Features

### `plan refactor`: Repeated String Literals

A new "Repeated String Literals" section in refactoring reports identifies hardcoded strings that appear in 2+ files. Uses KGF tokenization for language-agnostic detection.

```bash
indexion plan refactor --threshold=0.9 --include='*.mbt' src/
# → ## Repeated String Literals
#    | Value         | Files    | Occurrences |
#    | `"kgfs"`      | 13 files | 42 occurrences |
```

### `@kgf_features.load_registry_or_empty`

New convenience API that returns an empty registry instead of `None`. Eliminates `match` boilerplate at every call site.

### `@help` Package

CLI option descriptions (`--specs-dir`, `--output`, `--include`, `--exclude`) are now defined once in `cmd/indexion/help/` and shared across all commands.

### `@config.get_kgfs_install_dir()`

Single Source of Truth for the kgfs write/install path. Used by `kgf install`, `update`, and `init --global`.

## Breaking Changes

- `doc graph`: `--specs` renamed to `--specs-dir` (consistent with all other commands)
- `doc graph`: output default changed from `"-"` to `""` (behavior unchanged — both mean stdout)
- `doc readme`, `plan readme`: format default changed from `"markdown"` to `"md"` (consistent with plan commands)
- `similarity`: config field `output_format` renamed to `format`

## Improvements

- `doc graph`: defaults to `.` when no path given (previously errored)
- `doc readme`: template `{{include:path}}` now tries CWD-relative first, with warning on failure (was silent)
- `doc readme`: full symbol listing (removed "And N more symbols." truncation)
- `explore`: added `--specs-dir` option
- All `moon.pkg` files: test-only imports moved to `for "wbtest"` blocks

## Internal

- Removed duplicate utility functions: `substring_from`, `substring_config`, `trim_section_content`, `last_index_of` → replaced with `@common`/`@config` SoTs
- `@config.find_last_char` promoted to `pub`
- `TableAlign::Center`/`Right` unused variants removed
- Migrated `trkbt10/osenv` for platform config
- Version: 0.1.0 → 0.2.0
- 0 warnings, 0 errors, 1156 tests
