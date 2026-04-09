# skills/skills -- Individual Skill Definitions

The `skills/skills/` directory contains 12 individual skill definitions for the indexion Claude Code plugin. Each skill is a directory containing a single `SKILL.md` file that defines the skill's metadata (name, description, trigger conditions) and comprehensive usage documentation including CLI commands, options, workflows, and dogfooding lessons.

## Contents

```
skills/skills/
├── indexion-explore/       # File similarity analysis
│   └── SKILL.md
├── indexion-segment/       # Text segmentation
│   └── SKILL.md
├── indexion-kgf/           # KGF spec inspection and debugging
│   └── SKILL.md
├── indexion-grep/          # KGF-aware pattern and semantic search
│   └── SKILL.md
├── indexion-doc/           # Dependency graphs and README generation
│   └── SKILL.md
├── indexion-wiki/          # Wiki building, maintenance, and verification
│   └── SKILL.md
├── indexion-plan-refactor/ # Refactoring plan generation
│   └── SKILL.md
├── indexion-plan-docs/     # Documentation coverage analysis
│   └── SKILL.md
├── indexion-plan-reconcile/# Implementation/documentation drift detection
│   └── SKILL.md
├── indexion-plan-solid/    # Cross-directory common code extraction
│   └── SKILL.md
├── indexion-plan-readme/   # README writing task generation
│   └── SKILL.md
└── indexion-plan-unwrap/   # Unnecessary wrapper function detection
    └── SKILL.md
```

## Skill Summaries

### indexion-explore

Find similar files, detect duplicates, and analyze code similarity. Supports multiple strategies (tfidf, hybrid, ncd, apted, tsed) and output formats (matrix, list, cluster, json). Typically used as a first pass before `plan refactor`.

### indexion-grep

KGF-aware token pattern search, structural queries, and vector similarity search. Patterns use space-separated token matchers with auto-aliasing (e.g. `pub` resolves to `KW_pub`). Supports semantic queries (`--semantic=proxy`, `--semantic=long:30`, `--semantic=name:sort`, `--semantic="similar:..."`) and undocumented declaration search (`--undocumented`).

### indexion-segment

Split text into contextual segments using window divergence, TF-IDF, or punctuation strategies. Designed for RAG/embedding pipelines and sub-document similarity analysis. Configurable segment sizes, thresholds, and hybrid NCD+TF-IDF mode.

### indexion-kgf

Inspect and debug KGF language specs. Subcommands: `inspect` (full pipeline), `tokens` (tokenization), `events` (parse events), `edges` (dependency edges). Essential for debugging grep patterns that don't match expected tokens.

### indexion-doc

Generate dependency graphs (`doc graph`) in mermaid, dot, d2, text, or json formats. Generate READMEs (`doc readme`) from source doc comments using templates. Initialize templates (`doc init`). Supports `--per-package` mode that skips existing READMEs.

### indexion-wiki

Build, maintain, and verify project wiki pages at `.indexion/wiki/`. Covers the full agent workflow: navigating via `index.md`, detecting stale pages with `ingest`, writing/updating pages with `add-page`/`update-page`, verifying structural integrity with `lint`, and regenerating the navigation index. Includes guidance on provenance fields (`extracted`/`synthesized`/`manual`), cross-reference management, and the three-layer model (sources → wiki → checks).

### indexion-plan-refactor

Generate structured refactoring plans from file similarity analysis. Outputs duplicate code blocks, function-level duplicates, and same-file duplicates. Start with `--threshold=0.9` and work down. Combine with `grep` to trace references before consolidating.

### indexion-plan-docs

Analyze documentation coverage and generate prioritized action items. `--style=coverage` provides a quick per-package breakdown with percentages. Detects public items using KGF tokenization (language-agnostic) and associates doc comments with declarations.

### indexion-plan-reconcile

Detect implementation/documentation drift by comparing timestamps and content relationships. Uses inverted-index-accelerated matching and optional fork-based parallelism. Supports scoped checks (`package-docs`, `tree-docs`), document path/spec filtering, and logical review mode.

### indexion-plan-solid

Generate solidification plans for extracting common code across directories. Unlike `plan refactor` (which finds internal duplication), `plan solid` identifies cross-directory overlap using `--from=dirA,dirB` and optionally `--to=targetDir`.

### indexion-plan-readme

Generate README writing plans based on templates and source analysis. Produces tasks for manual or LLM authoring. Requires a `--template` file and outputs to `--plans-dir`.

### indexion-plan-unwrap

Detect unnecessary wrapper functions that simply delegate to another function. Three modes: report (default), preview (`--dry-run`), and auto-fix (`--fix`). Flags functions whose body is a single call with simple identifier arguments and no control flow. Use `--all` to include self-delegation and bare constructor wrappers.

## Usage

Each skill is automatically loaded by Claude Code when the plugin is installed. Skills trigger based on their description metadata -- for example, `indexion-explore` activates when the user asks to find duplicate or similar files.

Skills can also be invoked explicitly as slash commands:

```
/indexion-explore
/indexion-grep
/indexion-wiki
/indexion-plan-refactor
```

### SKILL.md Format

Each `SKILL.md` follows a standard structure:

```markdown
---
name: skill-name
description: Trigger description for Claude Code
---

# Command Name

{Overview}

## When to Use
## Usage
## Options
## Workflow
## Dogfooding Lessons
```

The YAML frontmatter (`name` and `description`) is used by the Claude Code plugin system to register the skill and determine when to trigger it.

> Source: `skills/skills/`
