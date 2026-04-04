# indexion grep

KGF-aware token pattern search across source files.

## Overview

Searches source files using KGF token patterns instead of raw text regex.
Token-level matching enables structural searches like "pub fn without doc comment"
or "nested for loops" that are impossible with text-based grep.

## Usage

```bash
indexion grep [options] <pattern> [paths...]
```

## Pattern Syntax

- `KW_fn` -- match token kind exactly
- `Ident:foo` -- match kind and text (`kind:text`)
- `*` -- match any single token
- `...` -- match zero or more tokens (non-greedy)
- `!KW_pub` -- negation (any token except this kind)

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--include=PATTERN` | Include file glob pattern (repeatable) | `*` |
| `--exclude=PATTERN` | Exclude file glob pattern (repeatable) | -- |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |
| `--context=INT` | Lines of context around matches | `0` |
| `--semantic=QUERY` | Semantic query: `proxy`, `short:N`, `long:N`, `params-gte:N`, `name:substr`, `undocumented`, `similar:QUERY` | -- |
| `--undocumented` | Find pub declarations without doc comments | false |
| `--count` | Show match count per file only | false |
| `--files` | Show matching file paths only | false |

## Examples

```bash
# Find all pub fn declarations
indexion grep "KW_pub KW_fn Ident" src/

# Find undocumented public declarations
indexion grep --undocumented src/

# Find nested for loops
indexion grep "KW_for ... KW_for" src/

# Find functions named "sort"
indexion grep "KW_fn Ident:sort" src/

# Semantic query: find short functions
indexion grep --semantic="short:5" src/
```

## API

- **`GrepConfig`** (Struct) -- CLI configuration for grep.
- **`TokenMatcher`** (Enum) -- A single token matcher in a pattern.
- **`SemanticQuery`** (Enum) -- A semantic query type.
- **`GrepMatch`** (Struct) -- A match result with position information.
- **`SemanticMatch`** (Struct) -- A semantic match result.
- **`parse_pattern`** (Function) -- Parse a space-separated pattern string into token matchers.
- **`parse_semantic_query`** (Function) -- Parse a semantic query string.
- **`run_pattern_search`** (Function) -- Run token pattern search across files.
- **`run_semantic_search`** (Function) -- Run a semantic query search across files.
- **`run_similar_search`** (Function) -- Run vector similarity search across the codebase.
