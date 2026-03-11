# indexion plan reconcile

## Overview

`indexion plan reconcile` detects drift candidates between implementation and documentation.

Its statuses are suggestion classes, not proofs. The goal is to surface likely review work with evidence and reuse review decisions, not to fully prove semantic consistency.

It builds a code graph from the target directory, extracts code symbols and inline docs, and matches them against external document fragments. Document extraction is KGF-based, so Markdown, plaintext, TOML, and other detectable document specs can participate in the same scan.

Direct symbol-name matches come from KGF feature metadata. Specs can declare `reference_token_kinds`, programming specs can declare `document_symbol_kinds`, and both code and document specs can declare `coverage_token_kinds` for module coverage, so `reconcile` does not need per-format token-kind guesses or command-local symbol-kind whitelists for supported languages.

Matching is symbol-first, then module-scoped. If a README or design section clearly covers a whole module, `reconcile` suppresses per-symbol `missing_doc` noise for that module and reports the coverage in the summary instead.

When many symbol candidates concentrate in one module or project group, the report also emits aggregate review groups so the first action can be "review this module/project doc set" instead of triaging each symbol independently.

Code discovery respects KGF ignore patterns, so language-specific test files and generated artifacts can be excluded by the active spec set instead of by command-local suffix rules.

Cross-package behavior is regression-tested with the TypeScript fixture at `fixtures/project/typescript-reconcile`, so package-doc scans are validated against non-MoonBit inputs as well.

The command does not rewrite code or docs. Its job is to produce a mechanically derived report with timestamp evidence, mapping confidence, and a logical review queue for follow-up.

At a high level, the flow is:

1. Discover source files and document files under the target directory.
2. Extract code symbols and document fragments.
3. Match fragments to symbols with symbol-first heuristics and module-scope coverage fallback.
4. Compare git and mtime evidence to classify drift.
5. Persist manifest, report, and DB state to avoid rechecking unchanged candidates.


## Usage

```bash
indexion plan reconcile [options] <directory>
```

Common examples:

```bash
# Scan the current project and print JSON
indexion plan reconcile .

# Render a human-readable report
indexion plan reconcile --format=md cmd/indexion/plan/reconcile

# Audit package docs with the built-in preset
indexion plan reconcile --scope=package-docs cmd/indexion/plan/reconcile

# Audit README/docs across a subtree
indexion plan reconcile --scope=tree-docs cmd/indexion/plan

# Audit package docs only (README + docs/)
indexion plan reconcile \
  --doc='README.md' \
  --doc='docs/**/*.md' \
  --doc-spec=markdown \
  cmd/indexion/plan/reconcile

# Restrict document inputs
indexion plan reconcile \
  --doc='docs/**/*.md' \
  --doc='spec/**/*.toml' \
  --doc-spec=markdown \
  --doc-spec=toml \
  .

# Apply logical review decisions from a JSON file
indexion plan reconcile \
  --review-results=.indexion/reconcile/reviews.json \
  .
```

Main CLI options:

| Option | Purpose | Default |
|--------|---------|---------|
| `--format=json\|md\|github-issue` | Select report renderer | `json` |
| `--output=FILE`, `-o=` | Write report to a file | stdout |
| `--scope=custom\|package-docs\|tree-docs` | Apply common doc-audit presets | `custom` |
| `--specs=DIR` | Override KGF spec directory | auto-detect |
| `--index-dir=DIR` | Override reconcile cache directory | `.indexion/reconcile` |
| `--config=FILE` | Load explicit `.indexion.toml` or `.json` | auto-discover |
| `--doc=GLOB` | Limit document paths, repeatable | all detectable docs |
| `--doc-spec=NAME` | Limit document specs, repeatable | all detected specs |
| `--threshold-seconds=N` | Tolerated time skew before drift | `60` |
| `--max-candidates=N` | Max report candidates | `200` |
| `--no-file-fallback` | Disable basename fallback matching | off |
| `--mtime-only` | Ignore git timestamps and use mtimes only | off |
| `--logical-review=queue\|off` | Enable or disable logical review queueing | `queue` |

Best practice is to start with JSON output, inspect candidate IDs and review keys, and then switch to Markdown or GitHub Issue rendering for human workflows.

Notes:

- Leaving `--doc` unset scans all detectable document specs under the target directory, not just Markdown.
- `--scope=package-docs` expands to `README.md` + `docs/**/*.md` with `doc_specs = ["markdown"]` unless explicit `--doc` or `--doc-spec` values are provided.
- `--scope=tree-docs` expands to `**/README.md` + `**/docs/**/*.md` with `doc_specs = ["markdown"]` unless explicit filters are provided.
- `docs/**/*.md` matches both `docs/api.md` and nested paths like `docs/reference/api.md`.


## Configuration

`reconcile` reads `.indexion.toml` first and falls back to `.indexion.json`.

Example TOML:

```toml
[reconcile]
doc_scope = "package-docs"
doc_paths = ["docs/**/*.md", "spec/**/*.toml", "notes/**/*.txt"]
doc_specs = ["markdown", "toml", "plaintext"]
index_dir = ".indexion/reconcile"
review_results_path = ".indexion/reconcile/reviews.json"
threshold_seconds = 60
max_candidates = 200

[reconcile.mapping]
allow_file_fallback = true

[reconcile.output]
default_format = "json"

[reconcile.time]
git_preferred = true
mtime_fallback = true

[reconcile.logical_review]
mode = "queue"
```

Notes:

- Relative `index_dir` and `review_results_path` values are resolved from the target directory or the config file location.
- `doc_paths` filters files before fragment extraction. If it is left empty, `reconcile` considers every detectable document spec under the target directory.
- For package-level doc audits, a common setting is `doc_paths = ["README.md", "docs/**/*.md"]` with `doc_specs = ["markdown"]`.
- `doc_specs` filters by detected KGF spec after path filtering.
- `git_preferred = true` uses git history when available, with mtime as fallback.
- `--mtime-only` overrides the time strategy from config.

JSON config supports the same fields under the top-level `reconcile` object.


## Output

The primary output is a `ReconcileReport` with `config`, `summary`, `aggregate_suggestions`, `candidates`, `logical_reviews`, `skipped`, `used_specs`, and `cache_state`.

Rendered formats:

- `json`: full machine-readable report with config, summary, aggregate review groups, candidates, logical review queue, cache state, and used specs.
- `md`: compact review document for humans.
- `github-issue`: checklist-style issue body for manual follow-up.

Candidate statuses currently emitted are:

- `missing_doc`: no external document fragment matched a symbol, and no higher-level module documentation covered its source file.
- `stale_doc`: implementation appears newer than the mapped document fragment.
- `review_mapping`: only a weak heuristic match was found.
- `review_both`: a weak or ambiguous match still requires manual judgment. Strong direct matches are not escalated just because the document is newer.

These statuses are suggestion classes. They indicate what to review next, not what is mathematically true about the repository.

Notable summary fields:

- `module_covered_symbols`: symbols that were not matched directly, but were suppressed from `missing_doc` because the surrounding module was covered by higher-level documentation.
- `total_aggregate_suggestions`, `module_suggestions`, `project_suggestions`: grouped review entry points that compress symbol floods into module and project triage units.
- Aggregate suggestions are built from the full mechanical candidate set before `max_candidates` truncation, so tree-wide audits still surface the right hot spots even when the symbol list is capped.
- When a project already has package docs but the mechanical pass cannot map helper-level symbols precisely, `reconcile` prefers aggregate-only `missing_doc` suggestions instead of flooding the report with helper symbols.

Index state is persisted under the reconcile index directory:

- `manifest.json`: source fingerprint, review hash, and indexed record metadata.
- `report.json`: cached last report for cache hits.
- `records.db`: VCDB-backed candidate and logical review index.

`index.json` is treated as stale leftover output and is cleaned up during save.


## Review Workflow

`reconcile` separates mechanical detection from logical confirmation.

Mechanical pass:

1. Build symbol and fragment inventories.
2. Match them heuristically.
3. Compare git and mtime evidence.
4. Emit drift candidates and queue logical review tasks.

Logical pass:

- Each candidate carries `needs_logical_review`, `logical_review_key`, and evidence fields.
- Pending review tasks are stored in `records.db` and mirrored in the report.
- Re-running `reconcile` reuses pending tasks instead of opening duplicate work.

To close or update queued reviews, prepare a JSON file like:

```json
[
  {
    "review_key": "review:mechanical-digest",
    "status": "accepted",
    "verdict": "Update docs to match the current implementation."
  }
]
```

Then apply it:

```bash
indexion plan reconcile --review-results=.indexion/reconcile/reviews.json .
```

Accepted or rejected reviews stay indexed, so the same unchanged candidate is not requeued on every run.
