///|
/// Sidecar file storing the FileSignature for every spec/impl file that
/// contributed to the persisted alignment snapshot. Lives next to
/// `manifest.json` inside the spec/align cache directory so the next run
/// can confirm via a stat-only pass that no tracked input drifted before
/// paying the full BM25 + NCD rebuild.
///
/// Designed as a sidecar rather than an extension of `AlignCacheManifest`
/// so older indexion releases can still load the manifest unchanged.
/// Absence of the sidecar (or any sidecar key mismatch) falls back safely
/// to the existing `build_current_file_hashes` content-read path, which
/// then writes the sidecar for the run after.
pub struct AlignSignaturesFile {
  signatures : Map[String, @signature.FileSignature]
}

///|
const ALIGN_SIGNATURES_FILENAME : String = "signatures.json"

///|
fn align_signatures_path(cache_dir : String) -> String {
  @reconcile_store.cache_path(cache_dir, ALIGN_SIGNATURES_FILENAME)
}

///|
/// Load the sidecar from disk. Returns `None` if the file is missing or
/// unreadable — callers treat that the same as "first signature-aware run,
/// do the full rebuild".
pub fn load_signatures(cache_dir : String) -> AlignSignaturesFile? {
  let path = align_signatures_path(cache_dir)
  if !@fs.path_exists(path) {
    return None
  }
  let raw = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(raw) catch { _ => return None }
  match json {
    Object(obj) => {
      let signatures : Map[String, @signature.FileSignature] = {}
      for entry in obj {
        let (k, v) = entry
        match v {
          Object(fields) => {
            let mtime_ns = match fields.get("mtime_ns") {
              Some(String(s)) => parse_int64_or_zero(s)
              _ => 0L
            }
            let size_bytes = match fields.get("size_bytes") {
              Some(String(s)) => parse_int64_or_zero(s)
              _ => 0L
            }
            signatures.set(k, { path: k, mtime_ns, size_bytes })
          }
          _ => ()
        }
      }
      Some({ signatures, })
    }
    _ => None
  }
}

///|
/// Persist a fresh signature snapshot. Returns `true` on success. Failures
/// are non-fatal: the next run simply rebuilds.
///
/// `mtime_ns` and `size_bytes` are serialized as JSON **strings**, not
/// numbers, because JSON `Double` loses precision above 2^53 — nanosecond
/// timestamps cross that threshold around 1970 + ~100 days.
pub fn save_signatures(
  cache_dir : String,
  signatures : Array[@signature.FileSignature],
) -> Bool {
  match @reconcile_store.ensure_cache_dir(cache_dir, "align cache directory") {
    Err(_) => return false
    Ok(_) => ()
  }
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  let mut first = true
  for sig in signatures {
    if !first {
      buf.write_string(",\n")
    }
    first = false
    buf.write_string("  ")
    buf.write_string(Json::string(sig.path).stringify())
    buf.write_string(": {\"mtime_ns\": \"")
    buf.write_string(sig.mtime_ns.to_string())
    buf.write_string("\", \"size_bytes\": \"")
    buf.write_string(sig.size_bytes.to_string())
    buf.write_string("\"}")
  }
  buf.write_string("\n}\n")
  let path = align_signatures_path(cache_dir)
  @fs.write_string_to_file(path, buf.to_string()) catch {
    _ => return false
  }
  true
}

///|
/// Walk spec_path and impl_path stat-only, applying the same content-type
/// filter as `discover_spec_files` and `discover_impl_files`. Returns the
/// set of signatures that the snapshot would have built from — without
/// reading file contents.
///
/// Spec scope picks document-typed files. Impl scope prefers code-typed
/// files and falls back to document-typed files only when no code file
/// exists, mirroring `discover_impl_files`.
pub fn discover_signatures_for_align(
  config : SpecAlignConfig,
  registry : @registry.KGFRegistry,
) -> Array[@signature.FileSignature] {
  let result : Array[@signature.FileSignature] = []
  for sig in discover_signatures_doc_only(config.spec_path, registry) {
    result.push(sig)
  }
  let impl_code : Array[@signature.FileSignature] = []
  let impl_doc : Array[@signature.FileSignature] = []
  for sig in discover_signatures_kgf(config.impl_path, registry) {
    match @kgf_features.content_type_for_file(sig.path, Some(registry)) {
      Some("document") => impl_doc.push(sig)
      _ => impl_code.push(sig)
    }
  }
  let impl_picked = if impl_code.length() > 0 { impl_code } else { impl_doc }
  for sig in impl_picked {
    result.push(sig)
  }
  result
}

///|
/// Stat-only walk under `root` that retains only KGF-tracked files whose
/// content type is `document` — used for the spec scope.
fn discover_signatures_doc_only(
  root : String,
  registry : @registry.KGFRegistry,
) -> Array[@signature.FileSignature] {
  let raw = discover_signatures_kgf(root, registry)
  let result : Array[@signature.FileSignature] = []
  for sig in raw {
    if @kgf_features.content_type_for_file(sig.path, Some(registry)) ==
      Some("document") {
      result.push(sig)
    }
  }
  result
}

///|
/// Stat-only walk under `root` that retains every KGF-tracked file
/// regardless of content type. Empty input path returns an empty array.
///
/// A single-file `root` is treated the same as `discover_spec_files` and
/// `discover_impl_files` do — we stat just that file, skipping the
/// directory walk.
fn discover_signatures_kgf(
  root : String,
  registry : @registry.KGFRegistry,
) -> Array[@signature.FileSignature] {
  if root.length() == 0 || !@fs.path_exists(root) {
    return []
  }
  let result : Array[@signature.FileSignature] = []
  let is_dir = @fs.is_dir(root) catch { _ => false }
  if !is_dir {
    if registry.detect_from_path(root) is Some(_) {
      match @signature.signature_for(root) {
        Some(sig) => result.push(sig)
        None => ()
      }
    }
    return result
  }
  let kgf_ignore = registry.collect_ignore_patterns()
  let opts = @pipeline.DiscoverOptions::new(kgf_ignore~, root_dir=root)
  for sig in @signature.discover_signatures([root], opts, registry) {
    result.push(sig)
  }
  result
}

///|
fn parse_int64_or_zero(text : String) -> Int64 {
  let trimmed = text.trim(chars=" \t").to_owned()
  if trimmed.length() == 0 {
    return 0L
  }
  let negative = trimmed.get_char(0).unwrap() == '-'
  let start = if negative { 1 } else { 0 }
  let mut acc : Int64 = 0L
  let mut i = start
  while i < trimmed.length() {
    let c = trimmed.get_char(i).unwrap()
    if c < '0' || c > '9' {
      return 0L
    }
    acc = acc * 10L + (c.to_int() - '0'.to_int()).to_int64()
    i = i + 1
  }
  if negative {
    -acc
  } else {
    acc
  }
}
