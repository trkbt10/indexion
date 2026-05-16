# `src/pipeline/signature` — FileSignature SoT

This package owns the question **"has this file changed since the cache
snapshot?"** for every indexion feature that maintains an on-disk cache.

Until this SoT existed, each cache-bearing feature (`agent orient`, `digest`,
`reconcile`, `search`, `identity`, …) independently read every file's full
content on every run, hashed it, then discarded unchanged work. That made
re-update O(content read) regardless of how few files actually changed.

The signature is intentionally **just `(path, mtime_ns, size_bytes)`** — no
content hash. A signature match means "stat metadata is identical, so the
previously cached content hash can be reused"; a signature mismatch means
"read the content and recompute the hash before deciding to rebuild".

## API surface

```moonbit
pub(all) struct FileSignature {
  path : String
  mtime_ns : Int64
  size_bytes : Int64
}

// Stat-only walk — never reads content.
pub fn discover_signatures(
  paths : Array[String],
  options : @pipeline.DiscoverOptions,
  registry : @registry.KGFRegistry,
) -> Array[FileSignature]

// On-demand content load for a signature (or a batch of them).
pub fn load_content(sig, registry) -> @pipeline.SupportedFile?
pub fn load_contents(sigs, registry) -> Array[@pipeline.SupportedFile]

// Classify a fresh discovery against a per-path cache snapshot.
pub fn classify_against_cache(
  fresh : Array[FileSignature],
  cached_by_path : Map[String, FileSignature],
) -> SignatureClassification {
  unchanged : Array[FileSignature]    // skip content read entirely
  candidates : Array[FileSignature]   // read + re-hash to confirm
  deleted_paths : Array[String]       // present in cache, missing on disk
}
```

## Adoption pattern (the same for every feature)

1. `discover_signatures` → `Array[FileSignature]`.
2. Scan your feature's cache → `Map[path, FileSignature]`.
3. `classify_against_cache` → `unchanged / candidates / deleted_paths`.
4. For `unchanged`: do nothing. Reuse cached downstream artifacts.
5. For `candidates`: `load_content`, recompute the content hash, compare to
   the cached hash:
   - hash matches → "metadata refresh only" — update just the cached
     signature attrs (no re-embed / re-extract / re-parse).
   - hash differs → real change. Rebuild downstream artifacts.
6. For `deleted_paths`: remove from cache.

## Caller cache requirements

Each feature's cache record must persist `mtime_ns` and `size_bytes` next to
its existing `content_hash` (or equivalent). Encode them as **strings**, not
as JSON numbers — the WAL codec in `trkbt10/vcdb` round-trips integers
through JSON `Double`, which loses precision above 2^53; nanosecond
timestamps cross that threshold around 1970 + ~100 days.

Backward compat: records written by an older release should be treated as
having `mtime_ns = 0` and `size_bytes = 0`, which always classifies as
`candidates` on the first signature-aware run and naturally backfills the
attrs.

## Cross-platform notes

The FFI in `signature_stub.c` follows symlinks (matches `stat()`):

- macOS — `st_mtimespec.{tv_sec, tv_nsec}` → full ns precision.
- Linux — `st_mtim.{tv_sec, tv_nsec}` → full ns precision.
- Windows (MSVC) — only `st_mtime` (seconds), packed into ns. Change
  detection within the same second falls back to the content hash check.

`size_bytes` uses `st_size` on every platform.

## Adoption status

| Feature | Status | Notes |
|---|---|---|
| `agent orient` | **adopted** | proof case; cache-valid runs in ~10s instead of ~160s on 1900-file repos |
| `digest` | **adopted** | sidecar at `.indexion/digest/signatures.json`; `update_index_if_stale` short-circuits to a zero-change `UpdateResult` when every tracked path's stat matches |
| `reconcile` | **adopted** | sidecar at `<index_dir>/signatures.json`; `persisted_report` short-circuits via `try_signature_fast_path` when signatures match, the config hash is unchanged, and the review-results file hasn't drifted |
| `spec align` | **adopted** | sidecar at `<cache_dir>/signatures.json`; `snapshot_for_config_async` skips `build_current_file_hashes` and uses the cached snapshot when the sidecar's stat-only classify finds zero candidates and zero deletions; falls back to the content-hash check when the sidecar is absent |
| `search` | pending | no cache today; adopting this primitive would gate cold-start cost |
| `identity` | pending | transient analysis with no on-disk cache; could short-circuit an in-process audit when nothing in scope changed, but not the primary win for this SoT |
| `spec verify` | pending | currently runs against an `align` snapshot; if it grows its own on-disk cache the same pattern applies |
| `wiki ingest`, `doc graph`, `plan refactor`, `segment` | not applicable | either no caching or already path-existence based |

## Migration sketch for the pending features

The general shape, in pseudocode:

```moonbit
// Stage 1: stat-only walk.
let sigs = @signature.discover_signatures(paths, opts, registry)

// Stage 2: project the existing cache into a signature map.
let cached_by_path = build_signature_map_from_<feature>_cache()

// Stage 3: classify.
let { unchanged, candidates, deleted_paths } =
  @signature.classify_against_cache(sigs, cached_by_path)

// Stage 4: content read only for candidates.
let candidate_files = @signature.load_contents(candidates, registry)
let really_changed = candidate_files.filter(fn(f) {
  hash(f.content) != cached_hash_for(f.path)
})

// Stage 5: cheap metadata refresh for candidates that hashed-out unchanged.
//          full rebuild for the actually-changed set.
//          tombstone for deleted_paths.
```

The "cheap metadata refresh" step depends on the feature's storage backend:

- vcdb-backed caches (`agent orient`, `digest` planned): use
  `update_attrs` to rewrite just the signature attrs — no vector re-embed.
- JSON manifest caches (`reconcile`, `wiki`): rewrite the manifest entry's
  signature fields in place.

Do **not** stuff the signature into the content hash. They answer different
questions: "did the stat metadata change?" (fast, sometimes false-positive
on unchanged content) vs "did the bytes change?" (slow, always correct).
The two-tier check uses both — signature for the cheap path, content hash
for the authoritative path.
