# Getting Started

## What is indexion?

indexion is a source code exploration and documentation tool. Named after Korzybski's principle "the map is not the territory," it builds dynamic maps of your codebase -- graphs, similarity matrices, documentation reports, and purpose-based function indexes.

indexion is language-agnostic. Language support is defined declaratively through KGF (Knowledge Graph Framework) spec files rather than hard-coded parsers.

## Installation

### Build from source

indexion is written in [MoonBit](https://www.moonbitlang.com/) and targets the native backend.

```bash
git clone https://github.com/trkbt10/indexion.git
cd indexion
moon build --target native
```

The binary is produced at the standard MoonBit output path. You can run it directly with `moon run`:

```bash
moon run cmd/indexion --target native -- --help
```

### Download a release

Pre-built binaries are available on the [GitHub releases page](https://github.com/trkbt10/indexion/releases).

## Project setup

Before running any commands, place KGF spec files in a `kgfs/` directory at the root of your project. indexion auto-detects which spec to use based on file extensions declared in each spec's `=== resolver` section.

```bash
# Initialize a project with default KGF specs
indexion init
```

This creates the `kgfs/` directory with bundled specs for supported languages.

## First commands

### Explore similarity

The `explore` command calculates pairwise similarity between files in a directory. This is the fastest way to spot duplicated or structurally similar code.

```bash
# Matrix view (default)
indexion explore src/

# Sorted list of similar pairs
indexion explore --format=list --threshold=0.7 src/

# Filter to specific file types
indexion explore --include='*.mbt' --exclude='*_wbtest.mbt' src/
```

### Generate a refactoring plan

The `plan refactor` command builds on explore results to produce an actionable Markdown checklist of refactoring candidates.

```bash
# Basic refactoring plan at 70% similarity
indexion plan refactor --threshold=0.7 src/

# Stricter threshold, output to file
indexion plan refactor --threshold=0.9 -o=refactor-plan.md src/
```

### Generate README documentation

The `doc readme` command creates README files from doc comments already present in your source code.

```bash
# Generate per-package READMEs (skips existing ones)
indexion doc readme --per-package src/

# Generate a single project-level README
indexion doc readme src/
```

### Generate a dependency graph

```bash
# Mermaid diagram
indexion doc graph --format=mermaid src/

# Graphviz DOT format
indexion doc graph --format=dot src/
```

### Query functions by purpose

The `digest` command builds a vector index of all functions in your codebase, then lets you search by what a function does rather than what it is named.

```bash
# Build the index
indexion digest build src/

# Query by purpose
indexion digest query --purpose="parse JSON from file" src/
```

## What to read next

- [Core Concepts](wiki://core-concepts) -- understand KGF, CodeGraph, and Digest at a conceptual level
- [CLI Commands](wiki://cli-commands) -- full reference for every command and flag
- [Analysis Tools](wiki://analysis-tools) -- deep dive into the plan commands and similarity algorithms

> **Source:** `cmd/indexion/main.mbt`, `cmd/indexion/explore/cli.mbt`, `cmd/indexion/plan/refactor/cli.mbt`, `cmd/indexion/doc/readme/cli.mbt`
