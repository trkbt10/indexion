# CLI Commands

indexion's CLI is organized into command groups. Each group addresses a different aspect of codebase analysis and documentation.

```mermaid
flowchart TD
    INDEXION[indexion]
    INDEXION --> INIT[init]
    INDEXION --> EXPLORE[explore]
    INDEXION --> PLAN[plan]
    INDEXION --> DOC[doc]
    INDEXION --> DIGEST[digest]
    INDEXION --> KGF[kgf]
    INDEXION --> SIM[sim]
    INDEXION --> SEGMENT[segment]
    INDEXION --> PERF[perf]
    INDEXION --> UPDATE[update]
    INDEXION --> GREP[grep]
    INDEXION --> SERVE[serve]
    INDEXION --> SEARCH[search]
    INDEXION --> MCP[mcp]

    PLAN --> PR[refactor]
    PLAN --> PD[documentation]
    PLAN --> PS[solid]
    PLAN --> PU[unwrap]
    PLAN --> PREC[reconcile]
    PLAN --> PREADME[readme]
    PLAN --> PWIKI[wiki]

    DOC --> DI[init]
    DOC --> DG[graph]
    DOC --> DR[readme]
    DOC --> DW[wiki]
```

---

## init

Initialize a project for indexion. Creates the `kgfs/` directory with bundled KGF spec files for supported languages.

```bash
indexion init
```

**When to use:** First time setting up indexion in a project. Run once, commit the `kgfs/` directory.

---

## explore

Analyze pairwise similarity between files in one or more directories. This is the fundamental building block -- most other commands build on the same comparison engine.

```bash
indexion explore [options] <directory...>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | `matrix`, `list`, `cluster`, `json` | `matrix` |
| `--strategy=NAME` | `tfidf`, `ncd`, `hybrid`, `apted`, `tsed` | `tfidf` |
| `--threshold=FLOAT` | Minimum similarity for output | `0.5` |
| `--ext=EXT` | File extension filter (repeatable) | all |
| `--include=PATTERN` | Include glob pattern (repeatable) | `*` |
| `--exclude=PATTERN` | Exclude glob pattern (repeatable) | -- |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

**Output formats:**

- **matrix** -- grid showing similarity percentages between all files
- **list** -- pairs sorted by similarity (highest first), filtered by threshold
- **cluster** -- groups of files exceeding threshold
- **json** -- machine-readable output with file list and pair scores

**When to use:** Quick exploration. "Are there duplicates in this directory?" Start with `--format=list` to see the most similar pairs.

```bash
indexion explore --format=list --threshold=0.8 src/
```

---

## plan

Generate planning documents for various code quality concerns. All subcommands produce Markdown by default and support `--format=json` for tooling.

### plan refactor

Find duplicate and near-duplicate code. Generates a refactoring checklist.

```bash
indexion plan refactor [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--threshold=FLOAT` | Similarity threshold | `0.7` |
| `--strategy=NAME` | Comparison algorithm | `hybrid` |
| `--style=STYLE` | `raw` (similarity data) or `structured` (plan) | `raw` |
| `--include` / `--exclude` | Glob filters | -- |
| `-o=FILE` | Output to file | stdout |

**When to use:** Before a refactoring sprint. Identify consolidation opportunities.

### plan documentation

Analyze documentation coverage across all public symbols.

```bash
indexion plan documentation [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--style=STYLE` | `full` or `coverage` | `full` |
| `--format=FORMAT` | `md`, `json`, `github-issue` | `md` |
| `--name=NAME` | Project name (auto-detected from moon.mod.json) | -- |
| `--template=FILE` | GitHub Issue Form template (.yml) | -- |

**When to use:** Track doc coverage over time. Generate GitHub issues for documentation tasks.

### plan solid

Plan extraction of common code from multiple packages into a shared location.

```bash
indexion plan solid --from=dir1/,dir2/ --to=shared/ [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--from=DIRS` | Comma-separated source directories | required |
| `--to=DIR` | Target directory for extracted code | required |
| `--rules=FILE` | Rules file (.solidrc) | -- |
| `--rule=RULE` | Inline rule (repeatable), e.g. `"auth/** -> auth/"` | -- |
| `--threshold=FLOAT` | Similarity threshold | `0.9` |

**When to use:** Multiple packages have converged on similar implementations and you want to extract the common parts.

### plan unwrap

Detect wrapper functions that simply delegate to another function.

```bash
indexion plan unwrap [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Preview edits without applying | -- |
| `--fix` | Apply edits to source files | -- |
| `--include-self` | Include self-referencing wrappers | false |
| `--include-bare` | Include bare delegation (no arguments) | false |

**When to use:** After a refactoring that introduced indirection layers. Clean up trivial proxies.

### plan reconcile

Detect drift between documentation and implementation.

```bash
indexion plan reconcile [options] <directory>
```

**When to use:** Before a release, to ensure documentation is up to date with code changes.

### plan readme

Generate a task list of missing package READMEs.

```bash
indexion plan readme [options] <directory>
```

**When to use:** Planning a documentation sprint. Produces tasks that can be assigned to humans or LLMs.

### plan wiki

Analyze project structure and generate a wiki writing plan. Proposes concept-based page structure and detects pages that need updates based on source changes.

```bash
indexion plan wiki [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | `md`, `json`, `github-issue` | `md` |
| `--wiki-dir=DIR` | Wiki directory | `.indexion/wiki` |
| `-o=FILE` | Output to file | stdout |

**When to use:** Planning wiki documentation. Generates a page structure proposal and identifies stale pages.

---

## doc

Documentation generation commands.

### doc init

Create documentation templates (README.md scaffolds).

```bash
indexion doc init [options] <directory>
```

### doc graph

Generate a dependency graph from the CodeGraph.

```bash
indexion doc graph [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | `mermaid`, `json`, `dot`, `d2`, `text`, `codegraph` | `mermaid` |

**When to use:** Visualize module dependencies. The `mermaid` format can be embedded directly in Markdown. The `codegraph` format produces the full CodeGraph JSON used by the serve API.

### doc readme

Generate README files from source doc comments.

```bash
indexion doc readme [options] <directory>
```

| Option | Description |
|--------|-------------|
| `--per-package` | Generate one README per package (skips existing) |
| `--template=FILE` | Custom template file |

**When to use:** Bootstrap documentation from existing doc comments. Use `--per-package` for monorepos.

### doc wiki

Convert wiki between indexion's internal format and external wiki formats (GitHub, GitLab).

```bash
indexion doc wiki <subcommand> [options]
```

#### doc wiki export

Export the indexion wiki (`.indexion/wiki/`) to an external wiki format.

```bash
indexion doc wiki export --format=github --input=.indexion/wiki --output=./wiki
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | | Target format: `github`, `gitlab` | required |
| `--input` | `-i` | Input wiki directory | `.indexion/wiki` |
| `--output` | `-o` | Output directory | required |
| `--force` | `-f` | Overwrite existing files | false |

#### doc wiki import

Import an external wiki into indexion's internal format.

```bash
indexion doc wiki import --input=./github-wiki --output=.indexion/wiki
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | | Source format: `github`, `gitlab`, `auto` | `auto` |
| `--input` | `-i` | Input wiki directory | required |
| `--output` | `-o` | Output directory | `.indexion/wiki` |
| `--title` | | Wiki title for manifest | `Wiki` |
| `--force` | `-f` | Overwrite existing files | false |

**When to use:** Syncing wiki content between indexion's internal format and GitHub/GitLab wikis. Use `export` to publish, `import` to pull external changes back.

---

## digest

Build and query a purpose-based function index.

```bash
indexion digest <subcommand> [options] <directory>
```

### digest build

Build or incrementally update the vector index.

| Option | Description | Default |
|--------|-------------|---------|
| `--provider=TYPE` | `auto`, `tfidf`, `openai` | `auto` |
| `--dim=INT` | Embedding dimension | `256` (tfidf) / `1536` (openai) |
| `--strategy=NAME` | vcdb strategy: `bruteforce`, `hnsw`, `ivf` | `hnsw` |
| `--index-dir=DIR` | Where to store the index | `.indexion/digest` |

### digest query

Search the index by purpose.

| Option | Description | Default |
|--------|-------------|---------|
| `--purpose=TEXT` | What the function does | required |
| `--top-k=INT` | Number of results | `10` |
| `--min-score=FLOAT` | Minimum similarity | `0.1` |

**When to use:** "Where is the function that does X?" Faster and more semantic than grep.

---

## kgf

Inspect and debug KGF spec parsing.

```bash
indexion kgf <subcommand> [options] <file>
```

| Subcommand | Output |
|------------|--------|
| `inspect` | Full parsing result (tokens + events + edges) |
| `tokens` | Tokenization only |
| `events` | Parse events only |
| `edges` | Generated edges only |

| Option | Description |
|--------|-------------|
| `--spec=NAME` | Force a specific spec (default: auto-detect) |

**When to use:** Developing or debugging a KGF spec. Verify that a file is tokenized and parsed correctly.

---

## grep

KGF-aware token pattern search across source files. Unlike text-based grep, this matches on token kinds, enabling structural queries like "public function without doc comment."

```bash
indexion grep [options] <pattern> [paths...]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--include=PATTERN` | Include file glob pattern (repeatable) | `*` |
| `--exclude=PATTERN` | Exclude file glob pattern (repeatable) | -- |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |
| `--context=INT` | Lines of context around matches | `0` |
| `--semantic=QUERY` | Semantic query: `proxy`, `short:N`, `long:N`, `params-gte:N`, `name:substr`, `undocumented`, `similar:QUERY` | -- |

| Flag | Description |
|------|-------------|
| `--undocumented` | Find pub declarations without doc comments |
| `--count` | Show match count per file only |
| `--files` | Show matching file paths only |

**Pattern syntax:** Space-separated token matchers. `KW_fn` matches a token kind exactly, `Ident:foo` matches kind and text, `*` matches any single token, `...` matches zero or more tokens, `!KW_pub` negates.

**Examples:**

```bash
# Find all pub fn declarations
indexion grep "KW_pub KW_fn Ident" src/

# Find undocumented public declarations
indexion grep --undocumented src/

# Find nested for loops
indexion grep "KW_for ... KW_for" src/

# Find functions named "sort"
indexion grep "KW_fn Ident:sort" src/
```

**When to use:** Structural code search. "Find all functions that don't have a doc comment" or "find nested for loops."

---

## sim

Calculate text similarity or distance between two inputs.

```bash
indexion sim [options]
```

**When to use:** Ad-hoc similarity checks. Testing algorithm behavior on specific inputs.

---

## segment

Split text into contextual segments using various strategies.

```bash
indexion segment [options] <file>
```

**When to use:** Preparing text for RAG pipelines, embedding, or other chunk-based processing.

---

## perf

Performance benchmarking.

```bash
indexion perf kgf [options]
```

**When to use:** Measuring KGF parser throughput on your codebase.

---

## update

Check for and install updates.

```bash
indexion update
```

---

## serve

Start an HTTP server that exposes the CodeGraph, Digest index, and wiki content via REST endpoints. Powers the DeepWiki frontend and supports live rebuild of the digest index.

```bash
indexion serve [options] [workspace_dir]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--port=INT` | Listen port | `3741` |
| `--host=HOST` | Listen address | `127.0.0.1` |
| `--static-dir=DIR` | Static file directory for SPA serving | -- |
| `--provider=TYPE` | Embedding provider: `tfidf`, `openai`, `auto` | `auto` |
| `--dim=INT` | Embedding dimension | `256` (tfidf) / `1536` (openai) |
| `--strategy=NAME` | vcdb strategy: `bruteforce`, `hnsw`, `ivf` | `hnsw` |
| `--specs=DIR` | KGF specs directory | `kgfs` |
| `--index-dir=DIR` | Digest index directory | project-based |
| `--cors` | Enable CORS headers | false |

**REST API endpoints (POST):**

| Endpoint | Description |
|----------|-------------|
| `/api/digest/rebuild` | Trigger rebuild of the digest index |
| `/api/digest/query` | Query the digest index by purpose |
| `/api/wiki/search` | Search wiki pages |
| `/api/explore` | Run explore analysis |
| `/api/kgf/tokens` | KGF tokenization |
| `/api/kgf/edges` | KGF edge extraction |
| `/api/doc/graph` | Dependency graph generation |
| `/api/plan/refactor` | Refactoring plan |
| `/api/plan/documentation` | Documentation coverage |
| `/api/plan/reconcile` | Doc/code drift detection |
| `/api/plan/solid` | Code solidification plan |
| `/api/plan/unwrap` | Wrapper function detection |
| `/api/plan/readme` | README generation plan |

### serve export

Export a self-contained static site (wiki + explorer) for GitHub Pages or GitLab Pages.

```bash
indexion serve export --format=github --output=dist/pages
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format` | | Target format: `github`, `gitlab` | required |
| `--input` | `-i` | Input wiki directory | `.indexion/wiki` |
| `--output` | `-o` | Output directory | `dist/pages` |
| `--force` | `-f` | Overwrite existing files | false |

**When to use:** Running the DeepWiki frontend, building custom tooling against the indexion API, or exporting a static wiki site.

---

## search

Semantic search across code, wiki, and documentation. Uses TF-IDF vectors to find relevant content and supports filtering by node attributes.

```bash
indexion search [options] <query> [paths...]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--top-k` | `-k` | Number of results | `20` |
| `--min-score=FLOAT` | | Minimum similarity threshold | `0.05` |
| `--include=PATTERN` | | Include files matching glob pattern (repeatable) | -- |
| `--exclude=PATTERN` | | Exclude files matching glob pattern (repeatable) | -- |
| `--specs-dir=DIR` | | KGF specs directory | `kgfs` |
| `--filter` | `-f` | Filter by attributes (e.g. `node_type:code`, `language:moonbit`). Comma-separated. | -- |

| Flag | Description |
|------|-------------|
| `--files` | Show matching file paths only |
| `--json` | Output as JSON |

**Examples:**

```bash
# Search for error handling code
indexion search "error handling" src/

# Search wiki content
indexion search "SemanticSearch" .indexion/wiki/

# Filter by language
indexion search "parser" --filter="language:moonbit" src/

# Filter by node type
indexion search "query" --filter="node_type:code" src/ .indexion/wiki/
```

**When to use:** Finding relevant code or documentation by natural language query. More context-aware than text grep, faster than manual browsing.

---

## mcp

Start an MCP (Model Context Protocol) server that exposes indexion tools to AI assistants like Claude Code and Cursor.

```bash
indexion mcp [options] [workspace_dir]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--transport=MODE` | Transport mode: `stdio`, `http` | `stdio` |
| `--port=INT` | HTTP server port (http transport only) | `3741` |
| `--host=HOST` | HTTP server host (http transport only) | `127.0.0.1` |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

**Transport modes:**

- **stdio** -- reads JSON-RPC from stdin, writes to stdout. Use this with Claude Code, Cursor, and other MCP-compatible editors.
- **http** -- serves MCP over HTTP POST `/mcp` endpoint.

**Examples:**

```bash
# stdio mode (for Claude Code, Cursor, etc.)
indexion mcp

# HTTP mode
indexion mcp --transport=http --port=3741
```

**When to use:** Integrating indexion's analysis capabilities into AI-powered development workflows. The MCP server exposes tools for code search, graph analysis, and documentation queries.

> **Source:** `cmd/indexion/main.mbt`, `cmd/indexion/*/cli.mbt`
