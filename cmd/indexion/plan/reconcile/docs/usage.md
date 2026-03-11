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
- `--scope=package-docs` expands to `README.md` + `docs/**/*.md` with `doc_specs = ["markdown"]` unless explicit filters are supplied.
- `--scope=tree-docs` expands to `**/README.md` + `**/docs/**/*.md` with `doc_specs = ["markdown"]` unless explicit filters are supplied.
- `docs/**/*.md` matches both `docs/api.md` and nested paths like `docs/reference/api.md`.
