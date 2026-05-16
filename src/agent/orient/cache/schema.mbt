///|
pub let summary_preview_limit : Int = 512

///|
let attr_path : String = "path"

///|
let attr_role : String = "role"

///|
let attr_owner : String = "owner"

///|
let attr_source_hash : String = "source_hash"

///|
let attr_structural_summary : String = "structural_summary"

///|
let attr_summary_preview : String = "summary_preview"

///|
let attr_summary_full : String = "summary_full"

///|
let attr_mtime_ns : String = "mtime_ns"

///|
let attr_size_bytes : String = "size_bytes"

///|
pub(all) struct CachedFile {
  vector_id : @vcdb_types.VectorId
  path : String
  role : String
  owner : String
  source_hash : String
  structural_summary : String
  summary_preview : String
  summary_full : String?
  // FileSignature SoT — mtime/size attrs default to zero on records written
  // by older indexion releases, which is the same as "treat as unknown" and
  // forces a content re-read on first contact. Once a record is upserted by a
  // signature-aware build, subsequent runs skip content reads entirely while
  // the file remains untouched.
  mtime_ns : Int64
  size_bytes : Int64
} derive(Eq)

///|
pub(all) suberror RecordSchemaError {
  PathIdentityCollision(String, String, String)
  MissingRecordPath(String)
  MissingRecordAttr(String)
  NonStringRecordAttr(String, String)
}

///|
#warnings("-unused_value")
fn RecordSchemaError::diagnostic(
  self : RecordSchemaError,
) -> String {
  match self {
    PathIdentityCollision(expected, existing, vector_id) =>
      "orient vcdb path identity collision for `" +
      vector_id +
      "`: expected `" +
      expected +
      "`, existing `" +
      existing +
      "`"
    MissingRecordPath(vector_id) =>
      "orient vcdb record `" + vector_id + "` is missing path attr"
    MissingRecordAttr(attr) =>
      "orient vcdb record is missing `" + attr + "` attr"
    NonStringRecordAttr(attr, vector_id) =>
      "orient vcdb record `" +
      vector_id +
      "` has non-string `" +
      attr +
      "` attr"
  }
}

///|
pub fn vector_id_for_path(path : String) -> @vcdb_types.VectorId {
  let hash = @cas_hash.compute_hash(path).to_string()
  @vcdb_types.VectorId::from_int64(path_hash_to_int64(hash))
}

///|
fn path_hash_to_int64(hash : String) -> Int64 {
  // Current vcdb upsert indexes ids as Int64, so orient reduces the
  // path digest by parsing its first 16 hex chars as a big-endian Int64.
  (hex_byte_at(hash, 0).to_int64() << 56) |
  (hex_byte_at(hash, 2).to_int64() << 48) |
  (hex_byte_at(hash, 4).to_int64() << 40) |
  (hex_byte_at(hash, 6).to_int64() << 32) |
  (hex_byte_at(hash, 8).to_int64() << 24) |
  (hex_byte_at(hash, 10).to_int64() << 16) |
  (hex_byte_at(hash, 12).to_int64() << 8) |
  hex_byte_at(hash, 14).to_int64()
}

///|
fn hex_byte_at(hash : String, offset : Int) -> Byte {
  let high = hash[offset].to_int().unsafe_to_char()
  let low = hash[offset + 1].to_int().unsafe_to_char()
  ((hex_nibble(high) << 4) | hex_nibble(low)).to_byte()
}

///|
fn hex_nibble(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    0
  }
}

///|
pub fn attrs_from_brief(
  brief : LocalFileBrief,
  preview_limit? : Int = summary_preview_limit,
) -> @vcdb_types.Attrs {
  let attrs = @vcdb_types.empty_attrs()
  attrs.set(attr_path, @vcdb_types.AttrValue::String(brief.path))
  attrs.set(attr_role, @vcdb_types.AttrValue::String(brief.role))
  attrs.set(
    attr_owner,
    @vcdb_types.AttrValue::String(@map.owner_dir(brief.path)),
  )
  attrs.set(
    attr_source_hash,
    @vcdb_types.AttrValue::String(brief.source_hash),
  )
  attrs.set(
    attr_structural_summary,
    @vcdb_types.AttrValue::String(brief.structural_summary),
  )
  attrs.set(
    attr_summary_preview,
    @vcdb_types.AttrValue::String(
      bounded_summary_preview(brief.summary, preview_limit),
    ),
  )
  if is_documentation_record(brief) {
    attrs.set(
      attr_summary_full,
      @vcdb_types.AttrValue::String(bounded_summary_full(brief.summary)),
    )
  }
  // Store FileSignature fields as strings rather than Int(Int64). The vcdb
  // WAL codec routes Int through JSON Double, which loses precision above
  // 2^53 — nanosecond timestamps cross that threshold around 1970 + ~100
  // days, so any modern mtime would silently round-trip into Float. String
  // encoding is round-trip lossless and trivially decoded.
  attrs.set(
    attr_mtime_ns,
    @vcdb_types.AttrValue::String(brief.mtime_ns.to_string()),
  )
  attrs.set(
    attr_size_bytes,
    @vcdb_types.AttrValue::String(brief.size_bytes.to_string()),
  )
  attrs
}

///|
/// Rebuild the complete attrs set for a cached record while overriding just
/// the FileSignature fields. vcdb's `update_attrs` replaces the entire attrs
/// map, so any field omitted here would be lost on the next read.
pub fn signature_refresh_attrs(
  cached : CachedFile,
  mtime_ns : Int64,
  size_bytes : Int64,
) -> @vcdb_types.Attrs {
  let attrs = @vcdb_types.empty_attrs()
  attrs.set(attr_path, @vcdb_types.AttrValue::String(cached.path))
  attrs.set(attr_role, @vcdb_types.AttrValue::String(cached.role))
  attrs.set(attr_owner, @vcdb_types.AttrValue::String(cached.owner))
  attrs.set(
    attr_source_hash, @vcdb_types.AttrValue::String(cached.source_hash),
  )
  attrs.set(
    attr_structural_summary,
    @vcdb_types.AttrValue::String(cached.structural_summary),
  )
  attrs.set(
    attr_summary_preview,
    @vcdb_types.AttrValue::String(cached.summary_preview),
  )
  match cached.summary_full {
    Some(text) =>
      attrs.set(attr_summary_full, @vcdb_types.AttrValue::String(text))
    None => ()
  }
  attrs.set(
    attr_mtime_ns, @vcdb_types.AttrValue::String(mtime_ns.to_string()),
  )
  attrs.set(
    attr_size_bytes, @vcdb_types.AttrValue::String(size_bytes.to_string()),
  )
  attrs
}

///|
fn is_documentation_record(brief : LocalFileBrief) -> Bool {
  brief.role == "documentation" || @map.is_documentation_path(brief.path)
}

///|
let summary_full_max_bytes : Int = 65536

///|
fn bounded_summary_preview(text : String, limit : Int) -> String {
  // Cheap O(1) check via UTF-16 length: when it already fits under limit
  // there is no need to materialize a Char array. For a 100MB document the
  // old `text.to_array().length()` pass allocated ~100M chars just to read
  // the length, which abort()ed the runtime on large source trees.
  let limit = if limit < 0 { 0 } else { limit }
  if text.length() <= limit {
    text
  } else {
    @config_paths.substring(text, 0, limit)
  }
}

///|
/// Cap the `summary_full` blob stored in the vcdb. Documentation records keep
/// the source body so reconcile / wiki paths can reuse it, but unbounded
/// content (e.g. multi-MB HTML fixtures) blows out the WAL and triggers OOM
/// during attrs encoding. We keep only the prefix — downstream callers that
/// need the full document re-read it from disk via the recorded path.
fn bounded_summary_full(text : String) -> String {
  if text.length() <= summary_full_max_bytes {
    text
  } else {
    @config_paths.substring(text, 0, summary_full_max_bytes)
  }
}

///|
pub fn validate_record_path_for_overwrite(
  expected_path : String,
  record : @vcdb_types.VectorRecord,
) -> Unit raise RecordSchemaError {
  let vector_id = vector_id_for_path(expected_path).to_display_string()
  let existing_path = record_required_path(record, vector_id)
  if existing_path != expected_path {
    raise PathIdentityCollision(expected_path, existing_path, vector_id)
  }
}

///|
pub fn record_to_cached_file(
  id : @vcdb_types.VectorId,
  record : @vcdb_types.VectorRecord,
) -> CachedFile? raise RecordSchemaError {
  let vector_id = id.to_display_string()
  let path = record_required_path(record, vector_id)
  let expected_id = vector_id_for_path(path)
  if expected_id != id {
    raise PathIdentityCollision(path, path, vector_id)
  }
  Some({
    vector_id: id,
    path,
    role: record_required_string_attr(record, attr_role, vector_id),
    owner: record_required_string_attr(record, attr_owner, vector_id),
    source_hash: record_required_string_attr(
      record, attr_source_hash, vector_id,
    ),
    structural_summary: record_required_string_attr(
      record, attr_structural_summary, vector_id,
    ),
    summary_preview: record_required_string_attr(
      record, attr_summary_preview, vector_id,
    ),
    summary_full: record_optional_string_attr(
      record, attr_summary_full, vector_id,
    ),
    mtime_ns: record_optional_int64_attr(record, attr_mtime_ns),
    size_bytes: record_optional_int64_attr(record, attr_size_bytes),
  })
}

///|
fn record_optional_int64_attr(
  record : @vcdb_types.VectorRecord,
  attr : String,
) -> Int64 {
  match record.attrs.get(attr) {
    Some(@vcdb_types.AttrValue::Int(value)) => value
    // Older records (and the live encoding) carry signature integers as
    // strings to avoid the JSON Double precision floor on Int64.
    Some(@vcdb_types.AttrValue::String(s)) => parse_int64_or_zero(s)
    _ => 0L
  }
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

///|
fn record_required_path(
  record : @vcdb_types.VectorRecord,
  vector_id : String,
) -> String raise RecordSchemaError {
  match record.attrs.get(attr_path) {
    Some(@vcdb_types.AttrValue::String(path)) => path
    Some(_) => raise NonStringRecordAttr(attr_path, vector_id)
    None => raise MissingRecordPath(vector_id)
  }
}

///|
fn record_required_string_attr(
  record : @vcdb_types.VectorRecord,
  key : String,
  vector_id : String,
) -> String raise RecordSchemaError {
  match record.attrs.get(key) {
    Some(@vcdb_types.AttrValue::String(value)) => value
    Some(_) => raise NonStringRecordAttr(key, vector_id)
    None => raise MissingRecordAttr(key)
  }
}

///|
fn record_optional_string_attr(
  record : @vcdb_types.VectorRecord,
  key : String,
  vector_id : String,
) -> String? raise RecordSchemaError {
  match record.attrs.get(key) {
    Some(@vcdb_types.AttrValue::String(value)) => Some(value)
    Some(_) => raise NonStringRecordAttr(key, vector_id)
    None => None
  }
}
