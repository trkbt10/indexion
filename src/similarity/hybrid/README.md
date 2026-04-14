# hybrid

Pairwise string similarity using NCD (Normalized Compression Distance).

Implements the `SimilarityStrategy` trait for use in segmentation
and other contexts that need a `(String, String) -> Double` scorer.

Note: for batch file comparison, use `@batch.compare` with `strategy="hybrid"`
which routes to the multi-signal evidence fusion in `src/pipeline/comparison/hybrid.mbt`.

## API

- **`HybridStrategy`** (Struct) — NCD-based pairwise similarity strategy.
- **`new`** (Function) — Create with default config.
- **`calculate_adjacent_hybrid`** (Function) — NCD distances between adjacent texts.
