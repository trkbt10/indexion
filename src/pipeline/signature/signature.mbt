///|
/// `FileSignature` is the SoT for "has this file changed since the cache
/// snapshot?" across every indexion feature that maintains an on-disk cache
/// (agent orient, digest, reconcile, search, identity, …).
///
/// The signature intentionally does *not* include a content hash. A signature
/// match means "stat metadata is identical" — the corresponding cached
/// content hash can be reused. A signature mismatch means "content must be
/// re-read and re-hashed". This split lets re-update paths avoid reading
/// thousands of unchanged files end to end.
///
/// Adoption pattern (see README.md for migration sketches):
///   1. `discover_signatures(paths, opts, registry)` — stat-only walk.
///   2. For each signature, consult your feature's cache:
///      - `lookup(path)` returns `(cached_signature, cached_source_hash)`.
///      - If signatures match → reuse cached_source_hash (no content read).
///      - Otherwise → `load_content(sig)` and rehash.
pub(all) struct FileSignature {
  path : String
  mtime_ns : Int64
  size_bytes : Int64
} derive(Eq, Debug)

///|
/// Errors raised by signature collection. We deliberately keep this thin —
/// most failure modes (path missing, permission denied) are surfaced as the
/// path being absent from the result, since callers usually treat "stat
/// failure" the same as "file deleted".
pub(all) suberror SignatureError {
  StatFailure(String)
}

///|
#borrow(path)
#borrow(out)
extern "C" fn c_signature_stat(
  path : Bytes,
  path_len : Int,
  out : FixedArray[Int64],
) -> Int = "indexion_signature_stat"

///|
fn encode_path(path : String) -> Bytes {
  @utf8.encode(path)
}

///|
/// Compute the on-disk signature for a single path. Returns `None` if the
/// path no longer exists (or stat fails) — callers should treat that the same
/// as "deleted from the working tree".
pub fn signature_for(path : String) -> FileSignature? {
  let bytes = encode_path(path)
  let out : FixedArray[Int64] = FixedArray::make(2, 0L)
  let ok = c_signature_stat(bytes, bytes.length(), out)
  if ok == 0 {
    None
  } else {
    Some({ path, mtime_ns: out[0], size_bytes: out[1] })
  }
}

///|
/// Discover every file under the given input paths and return only their
/// stat-level signatures — never reads file contents. Use this in place of
/// `@pipeline.collect_supported_file_info` whenever your downstream stage
/// can short-circuit on a signature match against a previous cache snapshot.
pub fn discover_signatures(
  paths : Array[String],
  options : @pipeline.DiscoverOptions,
  registry : @registry.KGFRegistry,
) -> Array[FileSignature] {
  let file_paths = @pipeline.discover_files(paths, options)
  let result : Array[FileSignature] = []
  for path in file_paths {
    match registry.detect_from_path(path) {
      Some(_) =>
        match signature_for(path) {
          Some(sig) => result.push(sig)
          None => () // file vanished between walk and stat — skip
        }
      None => () // KGF doesn't claim this path; ignore
    }
  }
  result
}

///|
/// Re-stat a previously cached set of paths without walking the filesystem.
/// Use this on the warm-cache fast path: when a cache snapshot already lists
/// every path you care about, the only thing left to confirm is whether
/// each one's signature drifted — which is just one `stat()` per path,
/// orders of magnitude cheaper than re-walking the working tree.
///
/// Each returned signature is for a path that currently exists; vanished
/// paths are dropped (their absence is itself information the caller's
/// classify step will surface as "deleted").
pub fn signatures_for_paths(
  paths : Array[String],
) -> Array[FileSignature] {
  let result : Array[FileSignature] = []
  for path in paths {
    match signature_for(path) {
      Some(sig) => result.push(sig)
      None => () // file is gone — classify will report it as deleted
    }
  }
  result
}

///|
/// Load the file content for a previously discovered signature, returning a
/// fully populated `@pipeline.SupportedFile` so downstream stages (graph
/// build, brief construction, embedding, etc.) can run unchanged.
///
/// Returns `None` if the path could not be opened — usually because it was
/// deleted between the signature walk and the content load.
pub fn load_content(
  sig : FileSignature,
  registry : @registry.KGFRegistry,
) -> @pipeline.SupportedFile? {
  let files = @pipeline.load_supported_file_info([sig.path], registry)
  if files.length() == 0 {
    None
  } else {
    Some(files[0])
  }
}

///|
/// Bulk content load for a list of signatures. Preserves input order and
/// silently drops paths that fail to load (deleted, permission, etc.).
pub fn load_contents(
  sigs : Array[FileSignature],
  registry : @registry.KGFRegistry,
) -> Array[@pipeline.SupportedFile] {
  let paths : Array[String] = []
  for sig in sigs {
    paths.push(sig.path)
  }
  @pipeline.load_supported_file_info(paths, registry)
}

///|
/// Classify a fresh set of discovered signatures against a per-path cache
/// snapshot. The cache snapshot maps `path` to its previously recorded
/// signature; mismatches and absent entries become candidates for re-read.
///
/// Returns a partition:
///   - `unchanged` — signatures that exactly match the cached entry. Callers
///     should reuse cached downstream artifacts without reading the file.
///   - `candidates` — signatures whose path is new or whose mtime/size
///     differs. Callers must `load_content` + rehash these and compare the
///     resulting content hash against any cached hash before deciding to
///     rebuild downstream state.
///   - `deleted_paths` — paths present in the cache but absent from the new
///     discovery.
pub fn classify_against_cache(
  fresh : Array[FileSignature],
  cached_by_path : Map[String, FileSignature],
) -> SignatureClassification {
  let unchanged : Array[FileSignature] = []
  let candidates : Array[FileSignature] = []
  let seen : Map[String, Unit] = {}
  for sig in fresh {
    seen.set(sig.path, ())
    match cached_by_path.get(sig.path) {
      Some(cached) if cached.mtime_ns == sig.mtime_ns && cached.size_bytes ==
      sig.size_bytes => unchanged.push(sig)
      _ => candidates.push(sig)
    }
  }
  let deleted_paths : Array[String] = []
  for entry in cached_by_path {
    if !seen.contains(entry.0) {
      deleted_paths.push(entry.0)
    }
  }
  { unchanged, candidates, deleted_paths }
}

///|
pub(all) struct SignatureClassification {
  unchanged : Array[FileSignature]
  candidates : Array[FileSignature]
  deleted_paths : Array[String]
}
