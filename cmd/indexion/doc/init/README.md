# indexion doc init

Initialize documentation template structure.

## Usage

```bash
indexion doc init [options] [directory]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `-f, --force` | Overwrite existing files | false |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

## What It Creates

Creates `.indexion/readme/` directory with:
- `template.md` — README template with `{{include:...}}` placeholders
- `doc.json` — Documentation config (sections, packages, output path)

Use with `indexion doc readme --template=.indexion/readme/template.md` or `indexion doc readme --config=.indexion/readme/doc.json`.
