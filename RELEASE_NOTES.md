# v0.5.0

## Highlights

- **`indexion grep`** — New KGF-aware code search with token patterns, semantic queries, and vector similarity
- **Pattern Aliases** — Write `pub fn *` instead of `KW_pub KW_fn *` — aliases auto-generated from KGF specs
- **Shared Embedding Infrastructure** — `TfidfEmbeddingProvider` extracted to `src/text/embed/` as shared SoT for digest, wiki, and grep
- **Performance Fix** — `plan documentation` no longer hangs on large codebases (was CPU 100%, now ~8 seconds)
- **Major Deduplication** — 10+ duplicate functions eliminated, circular dependency resolved, -400 lines net

## New Commands

### `indexion grep`

KGF-aware token pattern search, semantic queries, and vector similarity search.

```bash
# Token patterns with natural keyword aliases
indexion grep "pub fn *" src/
indexion grep "for ... for" src/          # find nested loops
indexion grep "pub struct *" src/

# Semantic queries
indexion grep --semantic=proxy src/       # proxy functions
indexion grep --semantic=long:30 src/     # functions > 30 lines
indexion grep --semantic=params-gte:4 src/ # 4+ params
indexion grep --semantic=name:sort src/   # name contains "sort"
indexion grep --undocumented src/         # undocumented pub declarations

# Vector similarity search (TF-IDF embeddings)
indexion grep --semantic="similar:parse JSON configuration" src/
```

**Pattern syntax:**
- Space-separated token matchers: `pub fn Ident:sort`
- Wildcards: `*` (any token), `...` (zero or more), `!pub` (negation)
- Aliases auto-generated from KGF `=== lex` keyword patterns — no hardcoded tables

**Output modes:** `--files`, `--count`, `--context=N`, `--include`, `--exclude`

## Improvements

### `plan documentation`: Performance & Correctness

- **Single-pass tokenization**: each file tokenized once instead of twice (was the primary bottleneck)
- **KGF ignore patterns applied**: `*_test.mbt`, `*_wbtest.mbt`, `*_mbench.mbt` now excluded from analysis
- **O(n²) → O(n log n) sort**: `sort_pub_items` replaced selection sort with `sort_by`
- **`pub(all)` / `pub(readonly)` detection**: visibility modifier arguments now correctly skipped during declaration extraction

### Shared `src/text/embed/` Package

`TfidfEmbeddingProvider` extracted from `src/digest/index/` to `src/text/embed/`:
- `digest`, `docgen/wiki`, and `grep` all use the same SoT
- `cosine_similarity_dense` added for dense vector comparison
- No more digest-specific coupling for embedding infrastructure

### Sentence Boundary Unification

- `Sentence` type moved from `segmentation/sentence/` to `segmentation/types/`, breaking a circular dependency
- Fullwidth period `．` (U+FF0E) added to `is_sentence_terminator` to sync utils and splitter modules
- 3 duplicate boundary functions deleted from `splitter.mbt`, now using `@utils`

### TOML Config Parser

- Shared `parse_shared_toml_sections` extracted from `parse_project_toml_config` and `parse_global_toml_config`
- 6 identical reconcile/digest match arms consolidated

## Refactoring

Cross-package duplicate elimination validated by dogfooding `indexion plan refactor` and `indexion grep`:

| Duplicate | Resolution |
|-----------|-----------|
| `join_lines` (2 files) | Made pub in `docgen/diagram`, removed from `docgen/render` |
| `extract_substring` (2 files) | Made pub in `segmentation/types`, removed from `punctuation` |
| `contains_slash` (2 files) | Made pub in `ignorefile`, removed from `filter` |
| `is_whitespace_only` (2 files) | Removed private copy from `punctuation`, uses `@utils` |
| `substr` / `substring` (5 files) | Consolidated to `@config.substring` / `@config.substring_from` SoT |
| `extract_extension` (2 files) | `kgf/registry` uses `@config.extension`, `docgen/analyze` thin wrapper |
| `escape_mermaid_label` (same pkg) | Deleted, reuses `escape_mermaid` |
| `process_and_cont` / `process_not_cont` | Unified to `process_predicate_cont` with `negate` parameter |
| `tokenize_source` boilerplate (3 functions) | Extracted shared `tokenize_source` helper |

## Bug Fixes

- Fix `plan documentation --style=coverage` hanging at CPU 100% on large codebases
- Fix `pub(all) fn foo` not detected as a public declaration
- Fix duplicate `.gitignore` loading in documentation analysis
- Fix test files (`*_wbtest.mbt`) included in documentation coverage analysis

## Skills

- New: `indexion-grep` skill with full command reference
- All 8 skills rewritten with verified option defaults, dogfooding lessons, and cross-command relationship tables
- Fixed incorrect defaults (explore strategy, option names) across multiple skills

## Internal

- Version: 0.4.0 → 0.5.0
- 0 warnings, 0 errors, 1173 tests
- New package: `src/text/embed/` (shared TF-IDF embedding provider)
- New package: `cmd/indexion/grep/` (5 files: cli, pattern, search, semantic, similar)

---

# v0.4.0

## Highlights

- **KGF Syntax Highlighting** — Wiki code blocks are now highlighted using KGF tokenizer compiled to JS via MoonBit
- **Mermaid Diagram Overhaul** — Diagrams fit container width with vertical centering, zoom/pan, and full-screen support
- **Wiki Navigation UX** — Sidebar auto-expands 2 levels deep with consistent leaf-item alignment
- **Project Root Resolution** — `.indexion/` output is now always placed under the project root

## New Features

### KGF Tokenizer Library

MoonBit-compiled KGF tokenizer (`cmd/kgf-tokenizer`) exported as ESM for browser use. The wiki's `KgfCodeBlock` component uses it to tokenize and color code blocks based on language KGF specs fetched from the server.

### Mermaid Diagram Rendering

Complete rewrite of `MermaidDiagram` component:

- SVG viewBox parsed for intrinsic dimensions; `setTransform` scales to container width
- Vertical centering via computed Y offset
- `invisible` → `visible` toggle prevents layout flash during initial fit
- `ResizeObserver` with width-only tracking avoids resize loops
- Extracted into `useMermaidSvg`, `useFitToWidth` hooks and `FullScreenViewer` sub-component
- Distinct toolbar icons: `Maximize2` (fit width) vs `Fullscreen` (full screen)

## Improvements

### Wiki

- `renderPre` override strips Tailwind prose `<pre>` padding/background to prevent container-in-container styling
- Mermaid blocks unwrapped from `<pre>` — diagram component manages its own container
- Mobile bottom tab navigation replaces hamburger menu
- Sidebar navigation items aligned with spacer for leaf nodes

### CLI

- `.indexion/` output directory resolved to nearest project root (`.git` / `.indexion` marker) instead of target directory
- `digest`: existing index preserved when provider config differs (prevents accidental rebuild)

### CI

- `moon build --target js` added to pages and release workflows for KGF tokenizer
- Test fixtures create `.git` marker for project root detection in temp dirs

## Bug Fixes

- Fix mermaid diagram sizing: container-in-container from prose `<pre>` styling
- Fix mermaid fit stability: double-rAF ensures `setTransform` runs after React commit
- Fix `.indexion` output scattered across subdirectories
- Fix digest index destroyed on provider mismatch
- Fix test abort in CI due to missing `.git` marker in temp reconcile dirs
- Fix lint errors (prettier formatting, empty JSDoc blocks)

## Internal

- Version: 0.3.0 → 0.4.0
- 0 warnings, 0 errors, 1173 tests

---

# v0.3.0

## Highlights

- **`indexion serve`** — New HTTP server command for codebase exploration, search, and wiki hosting
- **`indexion plan wiki`** — Generate wiki writing plans with stale page detection
- **Regex Engine Overhaul** — Backtracking quantifiers, lookahead, Unicode escapes
- **Async Concurrency** — Planning and Git workflows migrated to MoonBit async runtime

## New Commands

### `indexion serve`

HTTP server for codebase exploration and search. Starts on port 3741 by default.

```bash
indexion serve .
indexion serve --port=8080 --cors .
```

- REST API: digest queries, code graph, wiki pages, KGF data
- `POST /api/digest/rebuild` for live index rebuilds
- SPA static file serving with bundled web UI (explorer, 3D graph, wiki, search)
- `--cors` flag for cross-origin requests

#### `indexion serve export`

Export self-contained static site for GitHub Pages deployment.

### `indexion plan wiki`

Analyze project structure and generate wiki writing plans.

```bash
indexion plan wiki .
indexion plan wiki --format=github-issue .
```

- Proposes concept-based page structure and writing tasks
- Detects stale wiki pages when `.indexion/wiki/` exists
- Output formats: markdown, JSON, GitHub issue

## Improvements

### `digest`: `.indexion.toml` Configuration

`digest` now reads embedding settings from `.indexion.toml` / `.indexion.json`. CLI args take precedence over file config.

```toml
[digest]
provider = "openai"
dimension = 1536
```

### `plan reconcile`: Smart Caching

- Source fingerprint and config hash based caching — skips re-analysis on cache hit
- Logical review tracking for better drift detection

### Regex & PEG Engine

- Backtracking quantifiers (`*?`, `+?`, `??`)
- Positive/negative lookahead (`(?=...)`, `(?!...)`)
- Unicode escapes (`\uXXXX` including ranges)
- Expanded `\S`, `\D`, `\W` character classes
- Group end position enumeration
- Fixed PEG iterative evaluator bracket handling and semantics comment parsing

### KGF Resolver

- Exact resolution step for more precise module matching
- Improved error handling and generated resolver package types

### Async Concurrency

- Git operations and planning workflows run concurrently via MoonBit async runtime
- Removed blocking C stubs and legacy parallel module

### Ignore File Handling

- Refactored into domain-neutral gitignore-syntax parser (`src/ignorefile/`)
- Proper separation: `.gitignore` in `git/gitignore.mbt`, `.indexionignore` in `config/ignore.mbt`
- Project root detection via markers (`.git`, `.indexion`, `.indexion.toml`)

## Bug Fixes

- `discover_files` no longer excludes `.` path due to hidden-dir glob pattern
- Tests no longer pollute project `.indexion/` directory

## Internal

- Web UI packages: `packages/wiki`, `packages/api-client`, `packages/vscode-plugin`
- Test fixtures moved to `fixtures/` directory
- CI: frontend typecheck, lint, and test added to release workflow
- Version: 0.2.2 → 0.3.0
- 0 warnings, 0 errors, 1173 tests

---

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
