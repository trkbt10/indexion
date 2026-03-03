# indexion explore

Analyze similarity across files in a directory.

## Overview

Explores a directory and calculates pairwise similarity between all files.
Useful for understanding code patterns and finding potential duplications.

## Usage

```bash
indexion explore [options] <directory>
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | Output: `matrix`, `list`, `cluster`, `json` | matrix |
| `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | tfidf |
| `--threshold=FLOAT` | Clustering threshold (for cluster format) | 0.5 |
| `--ext=EXT` | File extension filter (repeatable) | all |

## Examples

```bash
# Matrix view of all files
indexion explore src/

# List sorted by similarity
indexion explore --format=list src/

# Cluster similar files (70%+)
indexion explore --format=cluster --threshold=0.7 src/

# Filter by extension
indexion explore --ext=.mbt --ext=.kgf src/
```

## Output Formats

- **matrix**: Grid showing pairwise similarity percentages
- **list**: Pairs sorted by similarity (highest first)
- **cluster**: Groups of files exceeding threshold
- **json**: Machine-readable JSON output
