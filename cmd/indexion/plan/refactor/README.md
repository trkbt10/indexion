# indexion plan refactor

Generate refactoring plan based on file similarity analysis.

## Overview

Analyzes files in a directory, identifies similar code patterns using
TF-IDF or NCD algorithms, and generates a Markdown checklist for
refactoring candidates.

## Usage

```bash
indexion plan refactor [options] <directory>
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--threshold=FLOAT` | Similarity threshold (0.0-1.0) | 0.7 |
| `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | tfidf |
| `--include=PATTERN` | Include files matching glob pattern | * |
| `--exclude=PATTERN` | Exclude files matching glob pattern | - |
| `--output=FILE`, `-o=` | Output file path | stdout |

## Examples

```bash
# Basic usage - analyze src/ with 70% threshold
indexion plan refactor src/

# Higher threshold, exclude tests
indexion plan refactor --threshold=0.85 --exclude='*_wbtest.mbt' src/

# Output to file
indexion plan refactor --include='*.mbt' -o=refactor-plan.md src/
```

## Output Format

Generates Markdown with:
- Configuration summary
- Grouped similar files (clustered by similarity)
- Similarity matrix per group
- Action item checklist
