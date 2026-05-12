# indexion plan drift

Detect translation / documentation drift between two files.

## Overview

Compares two files (e.g. `README.md` ↔ `README-ja.md`, or the same
README before and after a change) and reports per-direction drift
terms plus cosine distance. Vocab sub-tokenization delegates to the
natural-language KGFs in `kgfs/natural/`, so cross-lingual pairs are
first-class: Kanji / Hiragana / Katakana / Hanzi / Hangul are
segmented by their own lexers, and POS-style stop classes (Article,
Preposition, Joshi, Particle, Ending, …) are excluded by token kind.

Reuses the same `@vocab.measure_divergence` SoT as `plan reconcile`,
opted into natural-language mode via `include_vocab_terms: true`.

## Usage

```bash
indexion plan drift [options] <file_a> <file_b>
indexion plan drift README.md README-ja.md
indexion plan drift --format=json README.md README-ja.md
indexion plan drift --vocab-threshold=0.3 README.md README-ja.md   # exits 1 if exceeded
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o`, `--output <path>` | Write report to file (default: stdout) | stdout |
| `--format <fmt>` | Output format: `text`, `md`, `json` | `text` |
| `--top <n>` | Max gap terms reported per direction (0 = unlimited) | `10` |
| `--vocab-threshold <d>` | Cosine-distance threshold; exit non-zero if exceeded | (off) |
| `--specs-dir <dir>` | KGF specs directory | auto-detect |

## Output

The `text` and `md` formats are human-readable. The `json` shape is
derived from `DriftReport`'s `ToJson` and is suitable for CI / tooling.

## API

- **`run_matches`** (Function) — Argparse entry point used by the CLI dispatcher.
- **`build_report`** (Function) — Build a `DriftReport` from a `DriftConfig`. Exposed for integration tests; the CLI dispatch routes through `run_matches`.
- **`render_output`** (Function) — Render a `DriftReport` as text, markdown, or JSON.
- **`DriftConfig`** (Struct) — Run configuration for one `plan drift` invocation.
- **`DriftReport`** (Struct) — Full drift report for one file pair.
- **`DriftDirection`** (Struct) — Drift terms surfaced from one direction of comparison.
- **`DriftGapTerm`** (Struct) — One drift term: feature kind, sub-token value, TF-IDF weight.
