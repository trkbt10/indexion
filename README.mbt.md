# indexion

<p align="center">
  <img src="docs/logo.svg" alt="indexion" height="64">
</p>

> "The map is not the territory" - Alfred Korzybski

**indexion** is a source code exploration and documentation tool that helps you build dynamic maps of your codebase.

## Features

- **Similarity Analysis**: Find duplicated or similar code patterns
- **Refactoring Planning**: Generate actionable refactoring checklists
- **Documentation Generation**: KGF-based intelligent doc extraction
- **Semantic Search**: Natural language search across code, wiki, and docs
- **Structural Code Search**: KGF-aware token pattern matching (`grep`)
- **MCP Integration**: Expose indexion tools to AI assistants (Claude Code, Cursor)
- **Wiki System**: Internal wiki with GitHub/GitLab export
- **Multi-language Support**: 25+ languages via extensible KGF specifications

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

### `indexion grep`

KGF-aware token pattern search across source files.

#### Overview

Searches source files using KGF token patterns instead of raw text regex.
Token-level matching enables structural searches like "pub fn without doc comment"
or "nested for loops" that are impossible with text-based grep.

#### Usage

```bash
indexion grep [options] <pattern> [paths...]
```


[Full documentation](cmd/indexion/grep/README.md)

### `indexion search`

Semantic search across code, wiki, and documentation.

#### Overview

Searches source files, wiki pages, and documentation using TF-IDF vector
similarity. Automatically detects content type from KGF spec features.
Results can be filtered by node attributes such as `node_type` and `language`.

#### Usage

```bash
indexion search [options] <query> [paths...]
```


[Full documentation](cmd/indexion/search/README.md)

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

### `indexion segment`

Split text into contextual segments.

#### Overview

Splits a text file into segments using divergence-based, TF-IDF, or punctuation strategies. Designed for RAG/embedding pipelines and sub-document similarity analysis.

#### Usage

```bash
indexion segment [options] <input-file> <output-dir>
```


[Full documentation](cmd/indexion/segment/README.md)

### `indexion doc graph`

Generate dependency graph in various formats.

#### Usage

```bash
indexion doc graph [options] [files...]
```


[Full documentation](cmd/indexion/doc/graph/README.md)

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

### `indexion plan documentation`

Generate documentation coverage analysis.

#### Overview

Analyzes public declarations across packages and determines what percentage have doc comments. Uses KGF tokenization for language-agnostic detection.

#### Usage

```bash
indexion plan documentation [options] [directory]
```


[Full documentation](cmd/indexion/plan/documentation/README.md)

### `indexion plan readme`

Generate README documentation writing plans.

#### Overview

Analyzes templates with `{{include:...}}` placeholders and generates per-section writing tasks. Outputs plans to a directory for manual or LLM-assisted authoring.

#### Usage

```bash
indexion plan readme [options] [directory...]
```


[Full documentation](cmd/indexion/plan/readme/README.md)

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


[Full documentation](cmd/indexion/plan/reconcile/README.md)

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

### `indexion digest`

Build and query a purpose-based function index.

#### Overview

Extracts function-level content from the CodeGraph, computes embeddings
(TF-IDF or OpenAI), and builds a queryable vector index. Supports
incremental updates and multiple embedding providers.

#### Usage

```bash
indexion digest <subcommand> [options] <directory>
```


[Full documentation](cmd/indexion/digest/README.md)

### `indexion serve`

Start HTTP server for codebase search, graph, and wiki APIs.

#### Overview

Starts an HTTP server that exposes CodeGraph, Digest index, and wiki content
via REST endpoints. Powers the DeepWiki frontend and supports live rebuild
of the digest index.

#### Usage

```bash
indexion serve [options] [workspace_dir]
```


[Full documentation](cmd/indexion/serve/README.md)

### `indexion mcp`

Start MCP (Model Context Protocol) server exposing indexion tools.

#### Overview

Runs an MCP server that exposes indexion's analysis tools to AI assistants
such as Claude Code, Cursor, and other MCP-compatible editors. Supports
two transport modes: stdio (for editor integration) and HTTP.

#### Usage

```bash
indexion mcp [options] [workspace_dir]
```


[Full documentation](cmd/indexion/mcp/README.md)

### `indexion kgf`

KGF spec management and inspection.

#### Usage

```bash
indexion kgf [options] <command>
```


[Full documentation](cmd/indexion/kgf/README.md)

### `indexion wiki`


[Full documentation](cmd/indexion/wiki/README.md)

### `indexion spec`

Specification-driven analysis: verify conformance, align specs with implementation, and draft SDDs.


[Full documentation](cmd/indexion/spec/README.md)

## Installation

### Quick Install Linux/macOS

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
```

Binary output: `_build/native/release/build/cmd/indexion/indexion.exe`

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

## Documentation

- [Wiki](https://trkbt10.github.io/indexion/wiki) — Interactive wiki with architecture guides, KGF system docs, and CLI reference
- [GitHub Pages](https://trkbt10.github.io/indexion/) — Full documentation site built with `indexion serve export`

## License

Apache License 2.0

