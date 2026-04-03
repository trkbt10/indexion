<!-- indexion:sources docs/ -->
# docs -- Project Documentation

The `docs/` directory contains the core documentation files for the indexion project. These are source fragments used both in the project README and on the GitHub Pages documentation site. The directory also includes the project logo and a `templates/` subdirectory for document generation templates.

## Contents

```
docs/
├── intro.md          # Project introduction and feature overview
├── installation.md   # Installation instructions (all platforms)
├── documentation.md  # Links to wiki and GitHub Pages site
├── license.md        # License declaration (Apache-2.0)
├── logo.svg          # Project logo (SVG)
└── templates/
    └── readme.md     # README generation template
```

### intro.md

The main project introduction, used at the top of the generated README. Contains the logo embed, tagline ("The map is not the territory"), and a feature summary covering similarity analysis, refactoring planning, documentation generation, and multi-language support.

### installation.md

Comprehensive installation instructions including:

- Quick install via curl (Linux/macOS)
- Manual download from GitHub Releases (Linux x64, macOS ARM64, Windows x64)
- Building from source with MoonBit toolchain
- KGF specs search order (6 fallback locations)
- Claude Code skills plugin installation

### documentation.md

Links to the interactive wiki and the GitHub Pages documentation site built with `indexion serve export`.

### license.md

Short license declaration: Apache License 2.0.

### logo.svg

The indexion project logo in SVG format.

## Usage

These documentation files are primarily consumed by the README generation pipeline. The `docs/templates/readme.md` template uses `{{include:docs/intro.md}}` directives to compose the final README.

```bash
# Generate README from template
indexion doc readme --template=docs/templates/readme.md .

# Initialize documentation templates
indexion doc init .
```

> Source: `docs/`
