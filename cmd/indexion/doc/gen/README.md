# indexion doc gen

Generate documentation from source files using KGF-based analysis.

## Overview

Analyzes source code using KGF (Knowledge Graph Format) specifications,
extracts structure and documentation comments, and generates Markdown
or JSON output with optional Mermaid diagrams.

## Usage

```bash
indexion doc gen [options] [files...]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | Output: `markdown`, `json`, `both` | both |
| `--output=DIR` | Output directory | .docgen |
| `--specs=DIR` | KGF specs directory | kgfs |
| `--no-diagrams` | Disable Mermaid diagram generation | false |
| `--config=FILE` | Documentation config file | doc.json |

## Examples

```bash
# Generate docs for all .mbt files
indexion doc gen src/*.mbt

# JSON output only
indexion doc gen --format=json --output=docs src/

# Using custom KGF specs
indexion doc gen --specs=my-kgfs src/
```

## Configuration

Create `doc.json` for advanced configuration:
```json
{
  "packages": [
    {"path": "src/module", "title": "Module Name"}
  ],
  "root": {"output": "README.md"}
}
```
