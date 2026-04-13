# v0.9.0

## Highlights

- **Skills Consolidation** — `indexion-doc`, `indexion-plan-docs`, `indexion-plan-readme`, `indexion-plan-reconcile` merged into a single `indexion-documentation` skill covering the full documentation lifecycle
- **SDD Skill v3 Overhaul** — Complete rewrite of `indexion-sdd` skill for cc-sdd v3 skills mode with expanded workflow: per-task drift gates, stall detection/recovery, ISO/IEC standard support, and vocabulary alignment fix

## Skills

### `indexion-documentation` — Unified Documentation Skill

Four documentation-related skills merged into one:

| Previous Skill | Merged Into |
|---------------|-------------|
| `indexion-doc` (doc readme, doc graph) | `indexion-documentation` |
| `indexion-plan-docs` (plan documentation) | `indexion-documentation` |
| `indexion-plan-readme` (plan readme) | `indexion-documentation` |
| `indexion-plan-reconcile` (plan reconcile) | `indexion-documentation` |

### `indexion-sdd` — SDD Workflow v3

Major update for cc-sdd v3 skills mode (`$kiro-spec-*` commands):

- Migrate from `--codex`/`--claude` to `--codex-skills`/`--claude-skills`
- Add ISO/IEC standard support (`.spec.txt` format, PDF text extraction)
- Add Step 1.5: specification fidelity check with traceability chain
- Add Step 2.5: per-task drift gate using `indexion spec align`
- Add Step 2.6: stall detection and recovery for Codex processes
- Add Step 2.7: drift gate proxy when Codex cannot run indexion
- Add Step 3.5: vocabulary alignment fix with agent prompt generation
- Add Step 4: `plan reconcile` for post-implementation documentation drift
- Translate Japanese notes to English for international users
- Remove embedded dogfooding lessons (now maintained in indexion docs)

### Other Skill Updates

- `indexion-explore`: add missing strategies and options
- `indexion-kgf`: add missing subcommands documentation
- `indexion-plan-refactor`: fix CLI option accuracy
- `indexion-segment`: fix argument names and add missing options

## Internal

- Version: 0.8.0 → 0.9.0
- Skills: 4 merged into 1 (`indexion-documentation`), net −3 skill files
- `plugin.json` version synced from 0.1.0 → 0.8.0 → 0.9.0

---

# v0.8.0

## Highlights

- **`indexion wiki` Command Family** — Unified wiki management replaces scattered `doc wiki` and `plan wiki`. Full subcommand tree: `pages add/update/ingest`, `index`, `lint`, `log`, `hook`, `import`, `export`
- **Office Document Inspection (VFS)** — DOCX, XLSX, PPTX archive inspection via virtual filesystem with SoT-enforced path safety
- **ZIP Module** — Native ZIP entry extraction for Office document support
- **BM25 Spec Align** — BM25 scoring for spec alignment, body-aware identifier matching, and KGF numbered criteria support
- **Embedding SoT Unification** — Unified embedding configuration across wiki, digest, and search
- **CI/Release Workflow Split** — Separate CI and release workflows with Windows build path shortening

## New Commands

### `indexion wiki` — Unified Wiki Management

Complete redesign of wiki CLI into a coherent subcommand tree. Replaces `doc wiki` (deleted) and `plan wiki` (deleted) with DRY/SoT architecture.

```bash
# Page management
indexion wiki pages add <title>           # Add a new wiki page
indexion wiki pages update <page-id>      # Update an existing page
indexion wiki pages ingest <path>         # Ingest external content into wiki

# Index and search
indexion wiki index                        # Rebuild wiki search index

# Quality
indexion wiki lint                          # Lint wiki pages for issues
indexion wiki log                           # Show wiki change log

# VCS integration
indexion wiki hook install                 # Install git hooks for wiki
indexion wiki hook uninstall               # Remove git hooks

# Import/Export
indexion wiki import <source>             # Import wiki from external source
indexion wiki export <dest>               # Export wiki as static site
```

### `indexion wiki hook` — VCS Hook Management

Git hook installation for automatic wiki index updates on commit. Hooks trigger `wiki index` to keep search data in sync with content changes.

## New Packages

### `src/vfs/` — Virtual Filesystem for Office Documents

Archive-backed virtual filesystem for inspecting Office Open XML documents (DOCX, XLSX, PPTX). Reads internal XML structure through ZIP entries with SoT-enforced path traversal safety.

### `src/zip/` — ZIP Archive Entry Extraction

Native ZIP archive reader: local file header parsing, DEFLATE decompression, and entry enumeration. Used by VFS for Office document inspection.

### `src/vcs/` — VCS Abstraction Layer

VCS operations abstraction (currently git backend). Hook management for wiki integration.

### `src/docgen/wiki/index/` — Wiki Index Builder

Search index construction for wiki content: section-level TF-IDF vectorization and vocabulary extraction.

### `src/docgen/wiki/ingest/` — Wiki Content Ingestion

Content ingestion pipeline: parse external documents, extract structure, and merge into wiki manifest.

### `src/docgen/wiki/lint/` — Wiki Linter

Lint checks for wiki pages: broken links, missing metadata, structural issues.

### `src/docgen/wiki/log/` — Wiki Change Log

Change tracking and log generation for wiki page modifications.

### `src/docgen/wiki/manifest/` — Wiki Manifest Management

Wiki manifest serialization/deserialization: page registry, metadata, and configuration.

### `src/docgen/wiki/search/` — Wiki Search Engine

TF-IDF-based wiki search with section-level granularity and IO layer for index persistence.

### `src/docgen/wiki/types/` — Wiki Type Definitions

Shared types for wiki subsystem: page metadata, section structure, search result types.

## Improvements

### Spec Align: BM25 Scoring & Identifier Matching

- BM25 scoring replaces raw TF-IDF cosine for spec-to-implementation alignment
- Body-aware identifier matching: requirement bodies contribute to alignment scoring
- Spec vocabulary presence in code used as additional signal
- KGF numbered criteria parsing for structured requirement extraction
- Criteria boost for direct identifier matches

### Spec Verify: Gap Detection Fixes

- Kneedle algorithm disabled in favor of strict kind matching for gap term detection
- More reliable identification of spec concepts missing from implementation

### Search: File-Level Scoring

- File-level scoring for search results, improving ranking of whole-file matches

### Digest: Auto Provider Fallback

- `provider = "auto"` falls back to TF-IDF when no API key is configured, fixing CI failures

### KGF Submodule Updates

- MoonBit DocBlock ordering fix (`///` before `///|`)
- Longest span selection for overlapping token matches
- OCaml/Haskell token ordering and grammar fixes
- PEG doc comment ordering fix for 8 languages
- TypeScript/Python doc comment and PEG ordering fixes
- DocBlock blank line handling fix
- Natural language KGF specs now properly override markdown `.md` mapping

### Embedding SoT Unification

- Single embedding configuration shared across wiki incremental update, digest, and search
- vcdb upgraded to 0.3.0

### Wiki CLI Redesign

- `doc wiki` and `plan wiki` merged into unified `wiki` command tree
- DRY/SoT architecture: shared config resolution, consistent `@argparse` usage
- `index_content` exported for reuse across wiki subcommands

## Bug Fixes

- Fix natural language KGF specs overriding markdown `.md` mapping (24 test failures)
- Fix digest `provider = "auto"` failing when no API key configured
- Fix identifier match to use unicode-safe alphanumeric extraction
- Fix doc_comment search in spec alignment
- Fix drift tests for BM25 and DocBlock changes with structural mutation
- Fix spec align criteria boost and identifier direct match
- Fix spec align + verify tuning for SDD compliance gate
- Fix search file-level scoring
- Fix spec draft KGF-based criteria extraction
- Fix all 4 dogfooding issues (graph cache, CLAUDE.md strengthening)
- Fix deploy-process skill to use annotated tags for `--follow-tags`
- Split CI/release workflows to fix Windows build path issues

## Breaking Changes

- `doc wiki` removed — use `indexion wiki export` / `indexion wiki pages` instead
- `plan wiki` removed — wiki planning integrated into `indexion wiki` subcommands

## Skills

- New: `indexion-sdd` skill with 4 RFC validation results
- New: `indexion-wiki` skill
- Updated: `deploy-process` skill (annotated tags)
- Updated: SDD script documentation (env vars, thresholds, multi-language results)

## Internal

- Version: 0.7.0 → 0.8.0
- 0 errors
- +15,670 lines, −1,093 lines (net +14,577)
- New packages: 11 (vfs, zip, vcs, docgen/wiki/index, docgen/wiki/ingest, docgen/wiki/lint, docgen/wiki/log, docgen/wiki/manifest, docgen/wiki/search, docgen/wiki/types, pipeline/archive tests)
- New CLI commands: `wiki` family with 10 subcommands (pages add/update/ingest, index, lint, log, hook install/uninstall, import, export)
- Deleted: `cmd/indexion/doc/wiki/`, `cmd/indexion/plan/wiki/` (merged into `cmd/indexion/wiki/`)
- CI workflow split: `.github/workflows/ci.yml` separated from release workflow

---

# v0.7.0

## Highlights

- **`indexion spec` Command Family** — New SDD-oriented specification analysis: `spec align` for traceability & drift detection, `spec draft` for auto-generating SDD drafts from READMEs, and `spec verify` for spec-to-implementation conformance checking
- **MinHash + LSH** — Locality-sensitive hashing for sub-quadratic duplicate detection in large corpora
- **BM25 & Jensen-Shannon Divergence** — Advanced TF-IDF scoring with term saturation and information-theoretic distribution comparison
- **Reconcile Refactoring** — Core reconcile analysis extracted from `cmd/` to `src/reconcile/` with new tracking and store packages
- **Git VCS Integration** — Native git timestamp and dirty-flag tracking for file-state awareness
- **KGF Declarations & Tokenize Packages** — Feature string layer and public declaration extraction refactored into dedicated packages
- **N-Provider Digest Support** — Multiple concurrent embedding providers (TF-IDF + remote) in digest index

## New Commands

### `indexion spec align` — Specification Traceability & Drift Detection

Full alignment engine with five subcommands for mapping requirements to implementations:

```bash
# Detect drift between spec and code
indexion spec align diff --spec='docs/spec/*.md' --threshold=0.6 src/

# Generate requirement-to-implementation trace
indexion spec align trace --spec='docs/spec/*.md' src/

# Get reconciliation suggestions with agent-aware tasks
indexion spec align suggest --agent=claude --spec='docs/spec/*.md' src/

# CI-friendly status check
indexion spec align status --fail-on=drifted --spec='docs/spec/*.md' src/

# Real-time monitoring
indexion spec align watch --interval=5 --spec='docs/spec/*.md' src/
```

**`diff`** classifies requirements into: matched, drifted, spec-only, impl-only, conflict. Supports `tfidf`, `ncd`, and `hybrid` similarity algorithms. Incremental mode (`--incremental --git-base <ref>`) restricts analysis to changed files.

**`trace`** builds a requirement-implementation correlation graph with confidence scores. Outputs JSON, YAML, or Mermaid diagrams. Commit-aware history tracking in cache.

**`suggest`** emits spec-wins/impl-wins/both guidance with reasoning. Agent-aware task rendering for claude, copilot, or generic agents.

**`status`** returns a CI-friendly summary with configurable exit codes.

**`watch`** continuously reruns alignment when inputs change.

### `indexion spec draft` — SDD Generation from Documentation

Auto-generates Software Design Document (SDD) draft requirements from README and usage documentation.

```bash
indexion spec draft --specs-dir=kgfs docs/
```

Parses sections and feature bullets via KGF document interpretation, outputting numbered requirement drafts (REQ-1, REQ-2, ...) in markdown or JSON.

### `indexion spec verify` — Spec Conformance Checking

Identifies spec terminology absent from implementation — the reverse direction of reconcile.

```bash
indexion spec verify --spec='docs/spec/*.md' src/
```

Tokenizes both spec and implementation via KGF, builds TF-IDF vectors, and reports gap terms (spec concepts missing from code). Filterable by kind: `ident`, `text`, `vocab`, or `all`. Outputs JSON, markdown, or GitHub issue format.

## New Packages

### `src/text/minhash/` — MinHash & LSH

MinHash signature generation (128 hashes, FNV-1a) for Jaccard similarity estimation with ~8.8% error. LSH (Locality-Sensitive Hashing) for approximate nearest neighbor search with automatic band parameter selection for target threshold.

### `src/text/tfidf/bm25` — Okapi BM25

BM25 scoring (k1=1.2, b=0.75) with term frequency saturation and document length normalization. Batch precomputation with cached norms for cosine similarity.

### `src/text/tfidf/jsd` — Jensen-Shannon Divergence

Symmetric, bounded [0,1] information-theoretic distance for token distributions. Treats frequencies as probability distributions, unlike geometric cosine similarity.

### `src/text/stats/` — Statistical Thresholding

Kneedle algorithm for automatic elbow detection in sorted weight curves. Used by gap term extraction to separate signal from noise.

### `src/document/structure/` — Document Structure Parsing

KGF-based document section parsing: heading hierarchy, document facts, table pair extraction, and interpreted document representation.

### `src/embedding/config/` — Embedding Configuration SoT

Single Source of Truth for embedding provider types: TfIdf, OpenAI, Precomputed. Includes VcdbStrategy (BruteForce, Hnsw, Ivf) and EmbeddingSource (Raw, Impression, RawWithContext) enums.

### `src/kgf/declarations/` — Public Declaration Extraction

Extracted from `src/kgf/features/` into dedicated package. KGF-aware public declaration extraction with preprocessing support.

### `src/kgf/tokenize/` — Feature String Layer

Feature string conversion layer between KGF lexer and TF-IDF: "Kind:value" format for identifiers, "Kind" for syntax tokens, "vocab:word" for natural language. Enables vocabulary-level comparison.

### `src/pipeline/vocabulary/` — Vocabulary Divergence Pipeline

Gap term extraction with project-wide document frequency filtering. Used bidirectionally: spec→code in verify, code→docs in reconcile.

### `src/reconcile/plan/` — Reconcile Analysis (refactored)

Core reconcile analysis moved from `cmd/indexion/plan/reconcile/` to `src/reconcile/plan/` for reusability across spec commands.

### `src/reconcile/tracking/` — File State Tracking

File-state tracking with git+mtime fallback: timestamps, dirty flags, content hashes.

### `src/reconcile/store/` — Reconcile Cache Store

Serialization/deserialization of cache manifests with version tracking.

### `src/vcs/git/` — Native Git Integration

Git repository detection, last commit timestamp extraction, dirty status checking, and repo root resolution. Platform-aware with graceful fallback to mtime when git is unavailable.

## Improvements

### Digest: N-Provider Support

Digest index now supports multiple concurrent embedding providers, each with independent dimension tracking. New `RemoteEmbeddingProvider` loads pre-computed embeddings from JSONL files.

### KGF Submodule Updates

- SDD and RFC profiles added for specification document parsing
- Shell, YAML, and project file language specifications
- Lexer pattern matcher improvements
- Preprocessing and capture group enhancements
- Expanded programming KGF declaration coverage

### Regex Capture Functions

New capture group extraction functions for enhanced document parsing.

## Bug Fixes

- Fix `cmd/kgf-tokenizer/moon.pkg` missing imports for JS target (removed in warning cleanup, undetected by native-only check)
- Fix ModuleDoc consuming declaration doc blocks
- Fix `doc readme --per-package` symbol extraction

## Fixtures

- New: `fixtures/project/spec-align-basic/` — Multi-language auth system (MoonBit, TypeScript)
- New: `fixtures/project/spec-align-rfc2795/` — RFC 2795 conformance (Rust, TypeScript)
- New: `fixtures/project/spec-align-rfc3492/` — RFC 3492 Punycode conformance (Python, TypeScript)
- New: `fixtures/project/spec-verify-jsonrpc/` — JSON-RPC 2.0 + RFC 7396 Merge Patch (MoonBit, Python, TypeScript)

## Internal

- Version: 0.6.0 → 0.7.0
- 0 errors, 1352 tests (was 1205)
- +25,897 lines, −4,065 lines (net +21,832)
- New packages: 15 (spec/align, spec/draft, document/structure, embedding/config, kgf/declarations, kgf/tokenize, pipeline/vocabulary, reconcile/plan, reconcile/store, reconcile/tracking, text/minhash, text/stats, text/tfidf/bm25, text/tfidf/jsd, vcs/git)
- New CLI commands: 3 (spec align, spec draft, spec verify)
- New spec align subcommands: 5 (diff, trace, suggest, status, watch)
- Reconcile core analysis extracted from cmd/ to src/ for cross-command reuse
- KGF features split: declarations and tokenize into dedicated packages
- Embedding configuration consolidated into single SoT package

---

# v0.6.0

## Highlights

- **Vocabulary Divergence Detection** — `plan reconcile` gains a new signal that compares TF-IDF vocabulary distributions between source code and documentation, detecting terms present in code but absent from docs
- **Otsu Adaptive Thresholding** — Gap terms are filtered using Otsu's method to separate package-specific concepts from language noise
- **`vocabulary_token_kinds` KGF Feature** — 31 KGF specs gain a new feature declaration that enables sub-tokenization of doc comments and string literals for vocabulary analysis
- **`.indexion.toml` `[doc]` Section** — `doc readme` auto-discovers `doc.json` config without `--config` flag
- **JSON KGF Spec** — New `.json` file support prevents markdown spec misdetection
- **Documentation Overhaul** — Wiki, READMEs, and CLI docs updated for search, mcp, grep, serve, doc wiki, plan wiki commands

## New Features

### `plan reconcile`: Vocabulary Divergence Signal

A new multi-signal architecture for detecting documentation gaps. In addition to the existing symbol-level matching and timestamp drift, reconcile now compares the TF-IDF vocabulary of source files against co-located documentation.

```bash
indexion plan reconcile --scope=tree-docs --vocab-threshold=0.3 cmd/indexion/
```

**How it works:**
1. Groups files by directory, separating source from documentation
2. Tokenizes both using KGF (language-aware tokens + sub-tokenization via `vocabulary_token_kinds`)
3. Builds project-wide IDF from per-file token arrays
4. Computes module-local cosine distance for divergence detection
5. Extracts gap terms using module-local IDF, filtered by project-wide DF to remove ubiquitous terms
6. Applies Otsu's method to adaptively separate meaningful gap terms from noise

**Output includes:**

```markdown
## Vocabulary Divergence

| Module | Document | Distance | Gap Terms |
|--------|----------|----------|----------|
| `serve` | `README.md` | 74% | `config`, `json`, `conn`, `cors` |
| `grep`  | `README.md` | 67% | `tokens`, `pattern`, `config` |
```

**New CLI option:** `--vocab-threshold=FLOAT` (default: 0.3, configurable via `[reconcile.vocabulary] threshold` in `.indexion.toml`)

### `.indexion.toml` `[doc]` Section

`doc readme` now auto-discovers `doc.json` from `.indexion.toml`:

```toml
[doc]
config_path = "doc.json"
```

Running `indexion doc readme` without `--config` automatically loads the configured `doc.json`.

### `vocabulary_token_kinds` KGF Feature

New KGF feature declaration that tells vocabulary analysis which token kinds contain semantic text worth sub-tokenizing:

```
=== features
vocabulary_token_kinds: DocComment, String
```

Added to all 25 programming language specs, 7 DSL specs, and the new JSON spec. Doc comments and string literals are now sub-tokenized into individual words for vocabulary comparison.

### JSON KGF Spec

New `kgfs/dsl/json.kgf` for `.json` files. Prevents markdown or wiki specs from misdetecting JSON files, reducing noise in vocabulary analysis and other KGF-based features.

## Documentation

### Wiki Updates

- `CLI-Commands.md`: Added `search`, `mcp`, `doc wiki` sections; updated `grep` with `--semantic`/`--undocumented`/`--count`/`--files` flags; expanded `serve` with full REST API and export subcommand
- `Home.md` (Overview): Added `doc wiki`, `search`, `serve`, `mcp` to command table and architecture diagram
- `Architecture.md`: Added MCP Server and Semantic Search to layer diagram, library table, and CLI module table
- `Getting-Started.md`: Added search, grep, mcp examples
- New pages: `src-mcp.md` (MCP Server module), `src-search.md` (Semantic Search module)
- `wiki.json`: Added `src-mcp` and `src-search` page definitions

### README Updates

READMEs rewritten with full Usage/Options/Examples for commands that had only API listings:
- `cmd/indexion/doc/readme/README.md` — Added `--config`, `--template`, doc.json config, template syntax
- `cmd/indexion/grep/README.md` — Full pattern syntax, options, semantic queries, examples
- `cmd/indexion/serve/README.md` — REST API endpoints, export subcommand, configuration
- `cmd/indexion/search/README.md` — Filter syntax, output modes, examples
- `cmd/indexion/mcp/README.md` — Transport modes, configuration
- `cmd/indexion/digest/README.md` — Subcommands (build/query/stats), configuration

### Project README

- `doc.json` expanded with 10 additional command entries
- `docs/intro.md` updated with new features (semantic search, grep, MCP, wiki)
- README regenerated via `indexion doc readme` (auto-discovered from `.indexion.toml`)

## Fixtures

- New: `fixtures/programming/clojure/core.clj`
- New: `fixtures/programming/zig/main.zig`

## Internal

- Version: 0.5.0 -> 0.6.0
- 0 errors, 1205 tests
- New file: `cmd/indexion/plan/reconcile/vocabulary.mbt` (vocabulary divergence computation)
- New file: `kgfs/dsl/json.kgf` (JSON file support)
- New types: `VocabularyDivergence`, `TokenizedModuleGroup`
- New functions: `compute_vocabulary_divergences`, `otsu_threshold_index`, `build_vocabulary_token_set`, `extract_gap_terms_filtered`
- New config: `DocFileConfig` in `src/config/doc_config.mbt`, `[reconcile.vocabulary]` section
- KGF specs modified: 31 files (vocabulary_token_kinds added)

---

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
