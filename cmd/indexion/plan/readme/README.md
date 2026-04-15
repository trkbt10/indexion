# indexion plan readme

Generate README documentation writing plans.

## Overview

Analyzes templates with `{{include:...}}` placeholders and generates per-section writing tasks. Outputs plans to a directory for manual or LLM-assisted authoring.

## Usage

```bash
indexion plan readme [options] [directory...]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--template=FILE` | Template file with `{{include:...}}` placeholders (required) | -- |
| `--plans-dir=DIR` | Output directory for plans | `.indexion/plans` |
| `--format=FORMAT` | Output format: `markdown`, `json` | `md` |
| `-o, --output=FILE` | Output file path | stdout |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

## Examples

```bash
# Generate writing plan
indexion plan readme --template=.indexion/readme/template.md .

# Output plans to directory
indexion plan readme --template=readme.md --plans-dir=.indexion/plans .
```
