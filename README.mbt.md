<p align="center">
  <img src="docs/logo.svg" alt="indexion" height="64">
</p>

# indexion

> "The map is not the territory" - Alfred Korzybski

**indexion** is a source code exploration and documentation tool that helps you build dynamic maps of your codebase.

## Features

- **Similarity Analysis**: Find duplicated or similar code patterns
- **Refactoring Planning**: Generate actionable refactoring checklists
- **Documentation Generation**: KGF-based intelligent doc extraction
- **Multi-language Support**: Extensible via KGF specifications

## Commands

### `indexion explore`

Analyze similarity across files in a directory.

#### Overview

Explores a directory and calculates pairwise similarity between all files.
Useful for understanding code patterns and finding potential duplications.

#### Usage

```bash
indexion explore [options] <directory>
```


[Full documentation](cmd/indexion/explore/README.md)

### `indexion plan refactor`

Generate refactoring plan based on file similarity analysis.

#### Overview

Analyzes files in a directory, identifies similar code patterns using
TF-IDF or NCD algorithms, and generates a Markdown checklist for
refactoring candidates. Detects duplicate code blocks with function-name
annotation via KGF tokenization (language-agnostic).

#### Usage

```bash
indexion plan refactor [options] <directory>
```


[Full documentation](cmd/indexion/plan/refactor/README.md)

### `indexion plan unwrap`

Detect unnecessary wrapper functions and plan their removal.

#### Overview

Scans source files for wrapper functions whose body is a single delegation
call with no added logic. Callers should use the delegate directly.
Supports report, dry-run preview, and auto-fix modes.

#### Usage

```bash
indexion plan unwrap [options] <directory>
indexion plan unwrap --dry-run --include='*.mbt' src/
indexion plan unwrap --fix --include='*.mbt' --exclude='*_wbtest.mbt' src/
```


[Full documentation](cmd/indexion/plan/unwrap/README.md)

### `indexion plan solid`

#### Overview

`indexion plan solid` builds a solidification plan for extracting duplicated code from multiple source directories into a shared target.

The command parses `--from`, `--to`, `--rules`, `--rule`, `--threshold`, `--strategy`, `--include`, `--exclude`, `--output`, and `--format`, then:

1. collects files from the source directories
2. computes cross-package similarity
3. applies extraction rules to matched files
4. emits a `SolidPlanJSON` summary
5. converts that summary into a `PlanDocument`

The intermediate plan is organized around `ExtractionGroup`, `ExtractionFile`, `UnmatchedFile`, `SolidConfigJSON`, and `SolidSummaryJSON`.

#### Usage

```bash
indexion plan solid --from=pkg1/,pkg2/ --to=components/
indexion plan solid --from=pkg1/,pkg2/ --rules=.solidrc
indexion plan solid --from=pkg1/,pkg2/ --to=components/ --rule="auth/** -> auth/"
```

Important options:

- `--from=DIRS`: comma-separated source directories
- `--to=DIR`: target directory for extracted code
- `--rules=FILE`: load rules from a rules file
- `--rule=RULE`: add inline extraction rules
- `--threshold=FLOAT`: minimum similarity score
- `--strategy=NAME`: similarity strategy such as `tfidf`, `apted`, or `tsed`
- `--include=PATTERN` / `--exclude=PATTERN`: filter collected files
- `--output=FILE`: write the rendered plan to a file
- `--format=md|json|github-issue`: choose the final renderer

Rule syntax is `pattern -> target`. Relative targets use `--to`, and absolute targets can use an `@pkg/...` prefix.


[Full documentation](cmd/indexion/plan/solid/README.md)

### `indexion plan reconcile`

#### Overview

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

#### Usage

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
  --review-results=.indexion/cache/reconcile/reviews.json \
  .
```

Main CLI options:

| Option | Purpose | Default |
|--------|---------|---------|
| `--format=json\|md\|github-issue` | Select report renderer | `json` |
| `--output=FILE`, `-o=` | Write report to a file | stdout |
| `--scope=custom\|package-docs\|tree-docs` | Apply common doc-audit presets | `custom` |
| `--specs=DIR` | Override KGF spec directory | auto-detect |
| `--index-dir=DIR` | Override reconcile cache directory | `.indexion/cache/reconcile` |
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


[Full documentation](cmd/indexion/plan/reconcile/README.md)

### `indexion doc readme`

Extract documentation from source files and generate README files.

#### Overview

Extracts `///` documentation comments from MoonBit source files and
outputs them in various formats. Supports flexible package discovery
with include/exclude patterns.

#### Usage

```bash
indexion doc readme [options] [paths...]
```


[Full documentation](cmd/indexion/doc/readme/README.md)

### `indexion sim`

Calculate text similarity and distance between two texts.

#### Overview

Computes similarity/distance metrics between two text inputs using
various algorithms (TF-IDF cosine similarity, NCD compression distance,
or a weighted hybrid).

#### Usage

```bash
indexion sim [options] <text1> <text2>
```


[Full documentation](cmd/indexion/similarity/README.md)

## Installation

### Quick Install (Linux/macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/trkbt10/indexion/main/install.sh | bash
```

Installs to `~/.indexion/` with KGF language specs. Add to PATH:

```bash
export PATH="$HOME/.indexion/bin:$PATH"
```

### Manual Download

Download from [Releases](https://github.com/trkbt10/indexion/releases):

| Platform | Archive |
|----------|---------|
| Linux x64 | `indexion-linux-x64.tar.gz` |
| macOS ARM64 | `indexion-darwin-arm64.tar.gz` |
| Windows x64 | `indexion-windows-x64.zip` |

Each archive contains:
- `indexion` binary
- `kgfs/` directory (60+ language specifications)

Extract and move to your preferred location:

```bash
tar -xzf indexion-darwin-arm64.tar.gz
mv indexion-darwin-arm64/indexion ~/.local/bin/
mv indexion-darwin-arm64/kgfs ~/.indexion/
```

### From Source

```bash
git clone https://github.com/trkbt10/indexion.git
cd indexion
moon build --target native --release
# Binary: _build/native/release/build/cmd/indexion/indexion.exe
```

### KGF Specs Location

indexion searches for KGF specs in this order:
1. Explicit specs directory CLI option for the command
2. `INDEXION_KGFS_DIR` environment variable
3. `[global].kgfs_dir` in global config
4. `kgfs/` in the target project directory
5. `kgfs/` in the current working directory
6. OS-standard data directory `.../kgfs/` when non-empty

### Claude Code Skills

```bash
claude plugin marketplace add trkbt10/indexion-skills
```

### Requirements

- MoonBit toolchain (for building from source)
- No runtime dependencies

## License

Apache License 2.0

