///|
pub let orient_summary_preview_limit : Int = 512

///|
let orient_attr_path : String = "path"

///|
let orient_attr_role : String = "role"

///|
let orient_attr_owner : String = "owner"

///|
let orient_attr_source_hash : String = "source_hash"

///|
let orient_attr_structural_summary : String = "structural_summary"

///|
let orient_attr_summary_preview : String = "summary_preview"

///|
let orient_attr_summary_full : String = "summary_full"

///|
pub(all) struct OrientCachedFile {
  vector_id : @vcdb_types.VectorId
  path : String
  role : String
  owner : String
  source_hash : String
  structural_summary : String
  summary_preview : String
  summary_full : String?
} derive(Eq)

///|
pub(all) suberror OrientRecordSchemaError {
  PathIdentityCollision(String, String, String)
  MissingRecordPath(String)
  MissingRecordAttr(String)
  NonStringRecordAttr(String, String)
}

///|
#warnings("-unused_value")
fn OrientRecordSchemaError::diagnostic(
  self : OrientRecordSchemaError,
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
  @vcdb_types.VectorId::from_bytes16(hash_to_bytes16(hash))
}

///|
fn hash_to_bytes16(hash : String) -> @vcdb_types.Bytes16 {
  @vcdb_types.Bytes16::new(
    hex_byte_at(hash, 0),
    hex_byte_at(hash, 2),
    hex_byte_at(hash, 4),
    hex_byte_at(hash, 6),
    hex_byte_at(hash, 8),
    hex_byte_at(hash, 10),
    hex_byte_at(hash, 12),
    hex_byte_at(hash, 14),
    hex_byte_at(hash, 16),
    hex_byte_at(hash, 18),
    hex_byte_at(hash, 20),
    hex_byte_at(hash, 22),
    hex_byte_at(hash, 24),
    hex_byte_at(hash, 26),
    hex_byte_at(hash, 28),
    hex_byte_at(hash, 30),
  )
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
  preview_limit? : Int = orient_summary_preview_limit,
) -> @vcdb_types.Attrs {
  let attrs = @vcdb_types.empty_attrs()
  attrs.set(orient_attr_path, @vcdb_types.AttrValue::String(brief.path))
  attrs.set(orient_attr_role, @vcdb_types.AttrValue::String(brief.role))
  attrs.set(
    orient_attr_owner,
    @vcdb_types.AttrValue::String(owner_dir(brief.path)),
  )
  attrs.set(
    orient_attr_source_hash,
    @vcdb_types.AttrValue::String(brief.source_hash),
  )
  attrs.set(
    orient_attr_structural_summary,
    @vcdb_types.AttrValue::String(brief.structural_summary),
  )
  attrs.set(
    orient_attr_summary_preview,
    @vcdb_types.AttrValue::String(
      bounded_summary_preview(brief.summary, preview_limit),
    ),
  )
  if is_documentation_record(brief) {
    attrs.set(
      orient_attr_summary_full,
      @vcdb_types.AttrValue::String(brief.summary),
    )
  }
  attrs
}

///|
fn is_documentation_record(brief : LocalFileBrief) -> Bool {
  brief.role == "documentation" || is_documentation_path(brief.path)
}

///|
fn bounded_summary_preview(text : String, limit : Int) -> String {
  let limit = if limit < 0 { 0 } else { limit }
  if text.to_array().length() <= limit {
    text
  } else {
    @config_paths.substring(text, 0, limit)
  }
}

///|
pub fn validate_record_path_for_overwrite(
  expected_path : String,
  record : @vcdb_types.VectorRecord,
) -> Unit raise OrientRecordSchemaError {
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
) -> OrientCachedFile? raise OrientRecordSchemaError {
  let vector_id = id.to_display_string()
  let path = record_required_path(record, vector_id)
  let expected_id = vector_id_for_path(path)
  if expected_id != id {
    raise PathIdentityCollision(path, path, vector_id)
  }
  Some({
    vector_id: id,
    path,
    role: record_required_string_attr(record, orient_attr_role, vector_id),
    owner: record_required_string_attr(record, orient_attr_owner, vector_id),
    source_hash: record_required_string_attr(
      record, orient_attr_source_hash, vector_id,
    ),
    structural_summary: record_required_string_attr(
      record, orient_attr_structural_summary, vector_id,
    ),
    summary_preview: record_required_string_attr(
      record, orient_attr_summary_preview, vector_id,
    ),
    summary_full: record_optional_string_attr(
      record, orient_attr_summary_full, vector_id,
    ),
  })
}

///|
fn record_required_path(
  record : @vcdb_types.VectorRecord,
  vector_id : String,
) -> String raise OrientRecordSchemaError {
  match record.attrs.get(orient_attr_path) {
    Some(@vcdb_types.AttrValue::String(path)) => path
    Some(_) => raise NonStringRecordAttr(orient_attr_path, vector_id)
    None => raise MissingRecordPath(vector_id)
  }
}

///|
fn record_required_string_attr(
  record : @vcdb_types.VectorRecord,
  key : String,
  vector_id : String,
) -> String raise OrientRecordSchemaError {
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
) -> String? raise OrientRecordSchemaError {
  match record.attrs.get(key) {
    Some(@vcdb_types.AttrValue::String(value)) => Some(value)
    Some(_) => raise NonStringRecordAttr(key, vector_id)
    None => None
  }
}
