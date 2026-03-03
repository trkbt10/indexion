# indexion sim

Calculate text similarity and distance between two texts.

## Overview

Computes similarity/distance metrics between two text inputs using
various algorithms (TF-IDF cosine similarity, NCD compression distance,
or a weighted hybrid).

## Usage

```bash
indexion sim [options] <text1> <text2>
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--strategy=NAME` | Algorithm: `tfidf`, `ncd`, `hybrid` | hybrid |
| `--ncd-weight=FLOAT` | NCD weight in hybrid mode | 0.5 |
| `--tfidf-weight=FLOAT` | TF-IDF weight in hybrid mode | 0.5 |
| `--format=FORMAT` | Output: `both`, `similarity`, `distance` | both |

## Examples

```bash
# Basic comparison
indexion sim "hello world" "hello there"

# Using TF-IDF only
indexion sim --strategy=tfidf "hello world" "hello there"

# Custom hybrid weights
indexion sim --ncd-weight=0.3 --tfidf-weight=0.7 "text1" "text2"
```

## Algorithms

- **tfidf**: TF-IDF cosine similarity (fast, token-based)
- **ncd**: Normalized Compression Distance (compression-based)
- **hybrid**: Weighted combination of both
