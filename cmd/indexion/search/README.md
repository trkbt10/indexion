# indexion search

Semantic search across code, wiki, and documentation.

## Overview

Searches source files, wiki pages, and documentation using TF-IDF vector
similarity. Automatically detects content type from KGF spec features.
Results can be filtered by node attributes such as `node_type` and `language`.

## Usage

```bash
indexion search [options] <query> [paths...]
```

## Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--top-k` | `-k` | Number of results | `20` |
| `--min-score=FLOAT` | | Minimum similarity threshold | `0.05` |
| `--include=PATTERN` | | Include files matching glob (repeatable) | -- |
| `--exclude=PATTERN` | | Exclude files matching glob (repeatable) | -- |
| `--specs-dir=DIR` | | KGF specs directory | `kgfs` |
| `--filter` | `-f` | Filter by attributes (e.g. `node_type:code`, `language:moonbit`). Comma-separated. | -- |
| `--files` | | Show matching file paths only | false |
| `--json` | | Output as JSON | false |

## Examples

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

## API

- **`build_corpus`** (Function) -- Build a search corpus from the given paths.
