///|
/// Sidecar file storing the FileSignature for every path that contributed to
/// the persisted reconcile report. Lives next to `manifest.json` and
/// `report.json` inside the reconcile cache directory so the next run can
/// confirm via a stat-only pass that no tracked file drifted before paying
/// the full "discover → read → hash → re-build candidate graph" cost.
///
/// Designed as a sidecar rather than an extension of `ReconcileManifest`
/// (whose schema is `derive(@json.FromJson)` with a fixed set of fields) so
/// older indexion releases can still load the manifest unchanged. Absence of
/// the sidecar is interpreted as "we don't know yet" and forces the
/// existing full-rebuild path, which then writes the sidecar for the run
/// after.
pub struct ReconcileSignaturesFile {
  signatures : Map[String, @pipeline.FileSignature]
}

///|
const RECONCILE_SIGNATURES_FILENAME : String = "signatures.json"

///|
fn reconcile_signatures_path(index_dir : String) -> String {
  @reconcile_store.cache_path(index_dir, RECONCILE_SIGNATURES_FILENAME)
}

///|
/// Load the sidecar from disk. Returns `None` if the file is missing or
/// unreadable — callers treat that the same as "first run after upgrade,
/// do the full rebuild".
pub fn load_signatures(index_dir : String) -> ReconcileSignaturesFile? {
  let path = reconcile_signatures_path(index_dir)
  if !@fs.path_exists(path) {
    return None
  }
  let raw = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(raw) catch { _ => return None }
  match json {
    Object(obj) => {
      let signatures : Map[String, @pipeline.FileSignature] = {}
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
/// are non-fatal: the next run simply rebuilds (same as if the sidecar were
/// missing).
///
/// `mtime_ns` and `size_bytes` are serialized as JSON **strings**, not
/// numbers, because the manifest is round-tripped through the same JSON
/// pipeline as the rest of the cache and JSON `Double` loses precision
/// above 2^53 — nanosecond timestamps cross that threshold around
/// 1970 + ~100 days.
pub fn save_signatures(
  index_dir : String,
  signatures : Array[@pipeline.FileSignature],
) -> Bool {
  match
    @reconcile_store.ensure_cache_dir(index_dir, "reconcile cache directory") {
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
  let path = reconcile_signatures_path(index_dir)
  @fs.write_string_to_file(path, buf.to_string()) catch {
    _ => return false
  }
  true
}

///|
/// Stat every path in the sidecar and report whether the live working tree
/// matches the stored signatures exactly. Returns `false` as soon as any
/// path is missing or has drifted, so the caller falls through to the full
/// rebuild path. An empty sidecar is treated as "no source files were ever
/// tracked" and reports `false` so the caller never short-circuits on an
/// uninitialized snapshot.
pub fn signatures_match_disk(file : ReconcileSignaturesFile) -> Bool {
  if file.signatures.length() == 0 {
    return false
  }
  for entry in file.signatures {
    let (path, expected) = entry
    match @pipeline.signature_for(path) {
      Some(actual) =>
        if actual.mtime_ns != expected.mtime_ns ||
          actual.size_bytes != expected.size_bytes {
          return false
        }
      None => return false
    }
  }
  true
}

///|
/// Capture signatures for every path in a list, dropping paths that vanished
/// between the analysis pass and this stat call. Used to build the sidecar
/// payload from the `all_file_states` array a fresh analysis produces.
pub fn signatures_for_file_states(
  file_states : Array[FileState],
) -> Array[@pipeline.FileSignature] {
  let result : Array[@pipeline.FileSignature] = []
  for state in file_states {
    match @pipeline.signature_for(state.path) {
      Some(sig) => result.push(sig)
      None => ()
    }
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
