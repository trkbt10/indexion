# indexion plan documentation

Generate documentation coverage analysis.

## Overview

Analyzes public declarations across packages and determines what percentage have doc comments. Uses KGF tokenization for language-agnostic detection.

## Usage

```bash
indexion plan documentation [options] [directory]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--style=STYLE` | Output style: `coverage`, `full` | `full` |
| `--format=FORMAT` | Output format: `md`, `json`, `github-issue` | `md` |
| `--template=FILE` | GitHub Issue Form template (.yml) | -- |
| `--name=NAME` | Project name (auto-detect from project manifest) | auto |
| `-o, --output=FILE` | Output file path | stdout |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

## Examples

```bash
# Quick coverage overview (~8s on large codebases)
indexion plan documentation --style=coverage .

# Full plan with action items
indexion plan documentation .

# GitHub Issue format
indexion plan documentation --format=github-issue .
```
