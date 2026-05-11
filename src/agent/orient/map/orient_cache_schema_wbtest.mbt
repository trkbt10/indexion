///|
fn orient_schema_test_brief(
  path : String,
  role : String,
  summary : String,
) -> LocalFileBrief {
  {
    path,
    role,
    source_hash: "hash-" + path,
    structural_summary: "symbols and edges for " + path,
    summary,
    structural_terms: [],
    summary_terms: [],
    score: 0.0,
    matched_terms: [],
  }
}

///|
fn attr_string(attrs : @vcdb_types.Attrs, key : String) -> String? {
  match attrs.get(key) {
    Some(@vcdb_types.AttrValue::String(value)) => Some(value)
    _ => None
  }
}

///|
fn expect_schema_attr(attrs : @vcdb_types.Attrs, key : String) -> String raise {
  match attr_string(attrs, key) {
    Some(value) => value
    None => fail("expected string attr `" + key + "`")
  }
}

///|
fn assert_no_json_packed_schema_attr(attrs : @vcdb_types.Attrs) -> Unit raise {
  assert_true(attrs.keys().contains("path"))
  assert_true(attrs.keys().contains("role"))
  assert_true(attrs.keys().contains("owner"))
  assert_true(attrs.keys().contains("source_hash"))
  assert_true(attrs.keys().contains("structural_summary"))
  assert_true(attrs.keys().contains("summary_preview"))
  assert_true(!attrs.keys().contains("json"))
  assert_true(!attrs.keys().contains("record"))
}

///|
test "orient vcdb schema: vector id is stable for normalized path" {
  let path = "src/agent/orient/map/orient_cache_schema.mbt"
  let first = vector_id_for_path(path)
  let second = vector_id_for_path(path)
  let other = vector_id_for_path("src/agent/orient/map/other.mbt")
  assert_eq(first, second)
  assert_true(first != other)
  assert_true(first.as_bytes16() is Some(_))
  assert_eq(first, orient_path_vector_id(path))
}

///|
test "orient vcdb schema: code brief attrs are discrete strings with bounded preview" {
  let summary = "0123456789abcdefghijklmnopqrstuvwxyz"
  let brief = orient_schema_test_brief(
    "src/agent/orient/map/orient_cache_schema.mbt", "implementation", summary,
  )
  let attrs = attrs_from_brief(brief, preview_limit=12)
  assert_eq(attrs.size(), 6)
  assert_no_json_packed_schema_attr(attrs)
  assert_eq(expect_schema_attr(attrs, "path"), brief.path)
  assert_eq(expect_schema_attr(attrs, "role"), "implementation")
  assert_eq(expect_schema_attr(attrs, "owner"), "src/agent/orient/map")
  assert_eq(expect_schema_attr(attrs, "source_hash"), brief.source_hash)
  assert_eq(
    expect_schema_attr(attrs, "structural_summary"),
    brief.structural_summary,
  )
  assert_eq(expect_schema_attr(attrs, "summary_preview"), "0123456789ab")
  assert_true(attr_string(attrs, "summary_full") is None)
}

///|
test "orient vcdb schema: documentation keeps full summary separately" {
  let summary = "# Cache migration\n\nFull documentation summary text."
  let brief = orient_schema_test_brief(
    "docs/orient-vcdb-migration.md", "documentation", summary,
  )
  let attrs = attrs_from_brief(brief, preview_limit=18)
  assert_eq(attrs.size(), 7)
  assert_no_json_packed_schema_attr(attrs)
  assert_eq(expect_schema_attr(attrs, "summary_preview"), "# Cache migration\n")
  assert_eq(expect_schema_attr(attrs, "summary_full"), summary)
}

///|
test "orient vcdb schema: role attr is directly filter eligible" {
  let brief = orient_schema_test_brief(
    "cmd/indexion/agent/agent_orient_cli.mbt", "consumer", "CLI consumer surface summary",
  )
  let attrs = attrs_from_brief(brief, preview_limit=64)
  let consumer_filter = @vcdb_filter.FilterExpr::match_(
    "role",
    @vcdb_types.AttrValue::String("consumer"),
  )
  let implementation_filter = @vcdb_filter.FilterExpr::match_(
    "role",
    @vcdb_types.AttrValue::String("implementation"),
  )
  assert_true(@vcdb_filter.eval_filter(consumer_filter, attrs))
  assert_false(@vcdb_filter.eval_filter(implementation_filter, attrs))
}

///|
fn observe_path_identity_collision(
  path : String,
  record : @vcdb_types.VectorRecord,
) -> String? raise {
  try {
    validate_record_path_for_overwrite(path, record)
    None
  } catch {
    PathIdentityCollision(expected, existing, _) =>
      Some(expected + "|" + existing)
    MissingRecordPath(_) => fail("expected collision, got missing path")
    MissingRecordAttr(_) => fail("expected collision, got missing attr")
    NonStringRecordAttr(_, _) => fail("expected collision, got non-string attr")
  }
}

///|
test "orient vcdb schema: existing record path is validated before overwrite" {
  let existing = orient_schema_test_brief(
    "src/agent/orient/map/existing.mbt", "implementation", "Existing file summary",
  )
  let record : @vcdb_types.VectorRecord = {
    vector: [0.0, 1.0],
    attrs: attrs_from_brief(existing, preview_limit=64),
  }
  validate_record_path_for_overwrite(existing.path, record)
  assert_true(
    observe_path_identity_collision(
      "src/agent/orient/map/new-colliding-path.mbt", record,
    ) ==
    Some(
      "src/agent/orient/map/new-colliding-path.mbt|src/agent/orient/map/existing.mbt",
    ),
  )
}

///|
test "orient vcdb schema: record projection preserves flat cached file fields" {
  let brief = orient_schema_test_brief(
    "README.mbt.md", "documentation", "Project docs summary",
  )
  let id = vector_id_for_path(brief.path)
  let record : @vcdb_types.VectorRecord = {
    vector: [1.0, 0.0],
    attrs: attrs_from_brief(brief, preview_limit=7),
  }
  guard record_to_cached_file(id, record) is Some(cached) else {
    fail("expected cached file projection")
  }
  assert_eq(cached.vector_id, id)
  assert_eq(cached.path, brief.path)
  assert_eq(cached.role, "documentation")
  assert_eq(cached.owner, "README.mbt.md")
  assert_eq(cached.source_hash, brief.source_hash)
  assert_eq(cached.structural_summary, brief.structural_summary)
  assert_eq(cached.summary_preview, "Project")
  assert_true(cached.summary_full == Some("Project docs summary"))
}
