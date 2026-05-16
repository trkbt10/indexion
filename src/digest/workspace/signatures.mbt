///|
/// Sidecar file storing the FileSignature for every path indexed in the
/// digest workspace. Lives next to the digest manifest in
/// `.indexion/digest/signatures.json` so the next update can confirm that
/// nothing has changed via a stat-only pass before re-walking the working
/// tree, re-reading every source file, and re-building the code graph.
///
/// Designed as a sidecar rather than an extension of the `DigestManifest`
/// schema (which is `derive(@json.FromJson)` with required fields) so older
/// indexion releases can still load the manifest unchanged; absence of the
/// sidecar is interpreted as "we don't know yet" and forces a full rebuild,
/// which then persists the sidecar for the run after.
pub struct SignaturesFile {
  signatures : Map[String, @signature.FileSignature]
}

///|
const SIGNATURES_FILENAME : String = "signatures.json"

///|
/// Return the absolute path of the signature sidecar inside `index_dir`.
pub fn signatures_path(index_dir : String) -> String {
  @config.join_path(index_dir, SIGNATURES_FILENAME)
}

///|
/// Load the sidecar from disk. Returns `None` if the file is missing or
/// unreadable — callers should treat that the same as "first run, do the
/// full rebuild".
pub fn load_signatures(index_dir : String) -> SignaturesFile? {
  let path = signatures_path(index_dir)
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
/// Persist a fresh signature snapshot. Returns true on success. Failures are
/// non-fatal: the next run will simply rebuild (same as if the sidecar were
/// missing).
pub fn save_signatures(
  index_dir : String,
  signatures : Array[@signature.FileSignature],
) -> Bool {
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
  let path = signatures_path(index_dir)
  @fs.write_string_to_file(path, buf.to_string()) catch {
    _ => return false
  }
  true
}

///|
/// Stat every path in the sidecar and report whether the live working tree
/// matches the stored signatures exactly. Returns `false` as soon as any
/// path is missing or has drifted, so the caller falls through to the full
/// rebuild path.
pub fn signatures_match_disk(file : SignaturesFile) -> Bool {
  for entry in file.signatures {
    let (path, expected) = entry
    match @signature.signature_for(path) {
      Some(actual) =>
        if actual.mtime_ns != expected.mtime_ns ||
          actual.size_bytes != expected.size_bytes {
          @progress.stage(
            "[digest] signature mismatch",
            "path=" +
            path +
            " expected_mtime=" +
            expected.mtime_ns.to_string() +
            " actual_mtime=" +
            actual.mtime_ns.to_string() +
            " expected_size=" +
            expected.size_bytes.to_string() +
            " actual_size=" +
            actual.size_bytes.to_string(),
            0UL,
          )
          return false
        }
      None => {
        @progress.stage(
          "[digest] signature missing on disk",
          "path=" + path,
          0UL,
        )
        return false
      }
    }
  }
  true
}

///|
fn parse_int64_or_zero(text : String) -> Int64 {
  let trimmed = text.trim(chars=" \t").to_string()
  if trimmed.length() == 0 {
    return 0L
  }
  let negative = trimmed.unsafe_char_at(0) == '-'
  let start = if negative { 1 } else { 0 }
  let mut acc : Int64 = 0L
  let mut i = start
  while i < trimmed.length() {
    let c = trimmed.unsafe_char_at(i)
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
