# indexion digest

Build and query a purpose-based function index.

## Overview

Extracts function-level content from the CodeGraph, computes embeddings
(TF-IDF or OpenAI), and builds a queryable vector index. Supports
incremental updates and multiple embedding providers.

## Usage

```bash
indexion digest <subcommand> [options] <directory>
```

## Subcommands

### digest build

Build or incrementally update the vector index.

```bash
indexion digest build [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--provider=TYPE` | Embedding provider: `auto`, `tfidf`, `openai` | `auto` |
| `--dim=INT` | Embedding dimension | `256` (tfidf) / `1536` (openai) |
| `--strategy=NAME` | vcdb strategy: `bruteforce`, `hnsw`, `ivf` | `hnsw` |
| `--index-dir=DIR` | Where to store the index | `.indexion/digest` |
| `--specs=DIR` | KGF specs directory | `kgfs` |
| `--graph=FILE` | Load graph from JSON file instead of building | -- |

### digest query

Search the index by purpose.

```bash
indexion digest query [options] <directory>
```

| Option | Description | Default |
|--------|-------------|---------|
| `--purpose=TEXT` | What the function does | required |
| `--top-k=INT` | Number of results | `10` |
| `--min-score=FLOAT` | Minimum similarity | `0.1` |

### digest stats

Show index statistics and health information.

```bash
indexion digest stats <directory>
```

## Configuration

Respects `.indexion.toml` settings (`[digest]` section):

```toml
[digest]
provider = "openai"
strategy = "hnsw"
# dim = 256
# api_key_env = "OPENAI_API_KEY"
# model = "text-embedding-3-small"
```

CLI arguments take precedence over config file settings.

## API

- **`build_digest_config`** (Function) -- Build DigestConfig from CLI config.
- **`resolve_provider`** (Function) -- Resolve embedding provider from config.
- **`build_graph_from_source`** (Function) -- Build graph from source directory.
- **`run_stats`** (Function) -- Show index statistics.
