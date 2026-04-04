# indexion serve

Start HTTP server for codebase search, graph, and wiki APIs.

## Overview

Starts an HTTP server that exposes CodeGraph, Digest index, and wiki content
via REST endpoints. Powers the DeepWiki frontend and supports live rebuild
of the digest index.

## Usage

```bash
indexion serve [options] [workspace_dir]
```

## Options

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

## REST API Endpoints (POST)

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

## Subcommands

### serve export

Export a self-contained static site for GitHub Pages or GitLab Pages.

```bash
indexion serve export --format=github --output=dist/pages
```

| Option | Description | Default |
|--------|-------------|---------|
| `--format` | Target format: `github`, `gitlab` | required |
| `--input` | Input wiki directory | `.indexion/wiki` |
| `--output` | Output directory | `dist/pages` |
| `--force` | Overwrite existing files | false |

## Configuration

Respects `.indexion.toml` settings (digest provider, strategy, etc.)
with CLI arguments taking precedence.

## API

- **`ServerState`** (Struct) -- Mutable server state, replaced atomically on rebuild.
- **`build_get_routes`** (Function) -- Build lookup table of all GET API routes.
- **`build_config_json`** (Function) -- Build readonly config JSON from ServeConfig.
