# indexion doc readme

Generate README.md files from source code documentation.

## Overview

Extracts `///` documentation comments from MoonBit source files and
generates README.md files for each package, plus an aggregated root README.

## Usage

```bash
indexion doc readme [options] [directory]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--config=FILE` | Configuration file | doc.json |
| `--root-only` | Generate only root README | false |
| `--packages-only` | Generate only package READMEs | false |

## Examples

```bash
# Generate all READMEs from doc.json config
indexion doc readme

# Generate only root README
indexion doc readme --root-only

# Use custom config
indexion doc readme --config=custom-doc.json
```
