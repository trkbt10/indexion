# indexion doc readme

Extract documentation from source files and generate README files.

## Overview

Extracts `///` documentation comments from MoonBit source files and
outputs them in various formats. Supports flexible package discovery
with include/exclude patterns.

## Usage

```bash
indexion doc readme [options] [paths...]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--include=PATTERN` | Include packages matching glob (repeatable) | all |
| `--exclude=PATTERN` | Exclude packages matching glob (repeatable) | none |
| `--recursive` | Scan directories recursively | true |
| `--no-recursive` | Do not scan recursively | |
| `--format=FORMAT` | Output: `markdown`, `json`, `raw` | markdown |
| `--output=FILE` | Output to file | stdout |
| `--per-package` | Generate README.md per package (skips existing) | false |
| `--template=FILE` | Use a template file with `{{include:path}}` and `{{packages}}` placeholders | none |
| `--config=FILE` | Use a `doc.json` configuration file for structured README generation | auto from `.indexion.toml` |
| `--specs-dir=DIR` | KGF specs directory | kgfs |

## Config-based Generation

When `--config` is specified (or `[doc].config_path` is set in `.indexion.toml`), the command
reads a `doc.json` file that defines which packages to include, section filters, and static
file inclusions. This is the recommended approach for project-level README generation.

```json
{
  "packages": [
    { "path": "cmd/indexion/explore", "title": "explore", "include_in_root": true, "sections": ["overview", "usage"] }
  ],
  "root": {
    "output": "README.mbt.md",
    "sections": [
      { "type": "static", "file": "docs/intro.md" },
      { "type": "toc", "title": "Commands" },
      { "type": "packages", "filter": "cmd/**" },
      { "type": "static", "file": "docs/installation.md" }
    ]
  }
}
```

## Template Syntax

Templates support simple placeholder substitution:
- `{{include:path}}` -- Include file contents
- `{{packages}}` -- Render all discovered packages
- `{{module_doc}}` -- Render module-level documentation only

## Examples

```bash
# Extract docs from current directory
indexion doc readme

# Generate README from doc.json config
indexion doc readme --config=doc.json

# Generate per-package READMEs (skips existing)
indexion doc readme --per-package src/

# Generate README from template
indexion doc readme --template=docs/templates/readme.md --output=README.md

# Filter packages
indexion doc readme --include="cmd/*" --exclude="*test*"
```
