<!-- indexion:sources docs/templates/ -->
# docs/templates -- Document Templates

The `docs/templates/` directory contains templates used by `indexion doc readme` to generate README files. Templates use a simple directive syntax to include other documentation fragments and inject dynamic content from source code analysis.

## Contents

```
docs/templates/
└── readme.md    # Main README generation template
```

### readme.md

The primary README template. It composes the final project README by including documentation fragments and injecting package listings:

```
{{include:docs/intro.md}}

## Packages

{{packages}}

{{include:docs/installation.md}}

## License

Apache License 2.0
```

**Template directives:**

- `{{include:path}}` -- Include the contents of another file at this position. Paths are relative to the project root.
- `{{packages}}` -- Inject an auto-generated listing of all packages discovered by indexion's source analysis.

## Usage

```bash
# Generate README using this template
indexion doc readme --template=docs/templates/readme.md .

# Generate per-package READMEs (skips packages with existing README.md)
indexion doc readme --per-package src/ cmd/indexion/

# Initialize templates (creates docs/templates/ if missing)
indexion doc init .
```

The template is designed to be composable: each `{{include:...}}` fragment (`intro.md`, `installation.md`) can be edited independently, and the generated README stays in sync by re-running the generation command.

> Source: `docs/templates/`
