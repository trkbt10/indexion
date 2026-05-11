///|
fn orient_store_test_config(name : String) -> AgentOrientConfig {
  {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-store/" + name,
  }
}

///|
fn orient_store_test_provider() -> @text_embed.TfidfEmbeddingProvider {
  let provider = @text_embed.TfidfEmbeddingProvider::new(8)
  provider.build_vocabulary([
    "alpha router implementation source cache", "beta http consumer surface client",
    "gamma documentation guide reference",
  ])
  provider
}

///|
fn orient_store_test_brief(
  path : String,
  role : String,
  hash : String,
  summary : String,
) -> LocalFileBrief {
  {
    path,
    role,
    source_hash: hash,
    structural_summary: "structure for " + path,
    summary,
    structural_terms: [],
    summary_terms: [],
    score: 0.0,
    matched_terms: [],
  }
}

///|
async fn reset_orient_store_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
fn orient_store_role_filter(role : String) -> @vcdb_filter.FilterExpr {
  @vcdb_filter.FilterExpr::match_("role", @vcdb_types.AttrValue::String(role))
}

///|
async test "orient cache store: create reopen query update remove and checkpoint" {
  let config = orient_store_test_config("roundtrip")
  reset_orient_store_fixture(config.cache_dir)
  let provider = orient_store_test_provider()
  let implementation = orient_store_test_brief(
    "src/agent/orient/map/orient_cache_store.mbt", "implementation", "hash-implementation-v1",
    "alpha router implementation source cache",
  )
  let consumer = orient_store_test_brief(
    "cmd/indexion/agent/agent_orient_cli.mbt", "consumer", "hash-consumer-v1", "beta http consumer surface client",
  )
  let handle = rebuild_empty_cache(config, provider)
  assert_eq(handle.dim(), provider.dim())
  assert_eq(handle.count(), 0)
  handle.upsert_many([implementation, consumer], timestamp_ns=100L)
  assert_eq(handle.count(), 2)
  assert_true(handle.db.has(vector_id_for_path(implementation.path)))
  assert_true(handle.db.has(vector_id_for_path(consumer.path)))
  guard handle.lookup_path(implementation.path) is Some(cached_impl) else {
    fail("expected implementation record lookup by path")
  }
  assert_eq(cached_impl.vector_id, vector_id_for_path(implementation.path))
  assert_eq(cached_impl.source_hash, "hash-implementation-v1")
  let updated_implementation = orient_store_test_brief(
    implementation.path,
    "implementation",
    "hash-implementation-v2",
    "alpha router implementation source cache updated",
  )
  handle.upsert_brief(updated_implementation, timestamp_ns=150L)
  assert_eq(handle.count(), 2)
  guard handle.lookup_path(implementation.path) is Some(updated_impl) else {
    fail("expected implementation record update by path")
  }
  assert_eq(updated_impl.vector_id, cached_impl.vector_id)
  assert_eq(updated_impl.source_hash, "hash-implementation-v2")
  assert_eq(
    updated_impl.summary_preview,
    "alpha router implementation source cache updated",
  )
  guard handle.lookup_id(vector_id_for_path(implementation.path))
    is Some(cached_by_id) else {
    fail("expected implementation record lookup by id")
  }
  assert_eq(cached_by_id.path, implementation.path)
  assert_eq(cached_by_id.source_hash, "hash-implementation-v2")
  let consumer_filter = orient_store_role_filter("consumer")
  let consumers = handle.scan(filter=Some(consumer_filter), limit=10)
  assert_eq(consumers.length(), 1)
  assert_eq(consumers[0].path, consumer.path)
  assert_eq(handle.count(filter=Some(consumer_filter)), 1)
  let hits = handle.search(
    provider.embed("beta consumer client"),
    5,
    filter=Some(consumer_filter),
  )
  assert_true(hits.length() > 0)
  assert_eq(hits[0].file.path, consumer.path)
  checkpoint_cache(handle)
  let reopened = open_cache(config, OrientCacheReadOnly, provider)
  assert_eq(reopened.dim(), provider.dim())
  assert_eq(reopened.count(), 2)
  guard reopened.lookup_path(consumer.path) is Some(reopened_consumer) else {
    fail("expected consumer record after reopen")
  }
  assert_eq(
    reopened_consumer.summary_preview,
    "beta http consumer surface client",
  )
  let mutable = open_cache(config, OrientCacheReadWrite, provider)
  assert_true(mutable.remove_path(consumer.path, timestamp_ns=200L))
  assert_eq(mutable.count(), 1)
  checkpoint_cache(mutable)
  let after_remove = open_cache(config, OrientCacheReadOnly, provider)
  assert_eq(after_remove.count(), 1)
  assert_true(after_remove.lookup_path(consumer.path) is None)
}

///|
async test "orient cache store: read only invalid open reports cache error without mutation" {
  let config = orient_store_test_config("readonly-invalid")
  reset_orient_store_fixture(config.cache_dir)
  @config_paths.ensure_dir_recursive(config.cache_dir)
  @fs.write_string_to_file(orient_map_path(config), "{legacy json not parsed") catch {
    _ => fail("failed to write legacy map fixture")
  }
  let provider = orient_store_test_provider()
  let layout = orient_cache_layout(config)
  try {
    let _ = open_cache(config, OrientCacheReadOnly, provider)
    fail("expected read-only invalid cache to raise a cache error")
  } catch {
    OrientCacheUnavailable(message) =>
      assert_true(message.contains("legacy orient-map.json"))
    _ => fail("expected OrientCacheUnavailable")
  }
  assert_true(!@fs.path_exists(layout.root_dir))
  assert_true(!@fs.path_exists(layout.metadata_path))
  assert_true(!@fs.path_exists(layout.vocabulary_path))
}

///|
async test "orient cache store: remove accepts logical path-derived vector id" {
  let config = orient_store_test_config("remove-logical-id")
  reset_orient_store_fixture(config.cache_dir)
  let provider = orient_store_test_provider()
  let brief = orient_store_test_brief(
    "src/agent/orient/map/remove_target.mbt", "implementation", "hash-remove-target-v1",
    "alpha implementation remove target",
  )
  let handle = rebuild_empty_cache(config, provider)
  handle.upsert_brief(brief, timestamp_ns=100L)
  let logical_id = vector_id_for_path(brief.path)
  assert_true(handle.remove_id(logical_id, timestamp_ns=200L))
  assert_eq(handle.count(), 0)
  assert_true(handle.lookup_path(brief.path) is None)
}

///|
async test "orient cache store: checkpoint storage failure is surfaced as cache error" {
  let config = orient_store_test_config("checkpoint-error")
  reset_orient_store_fixture(config.cache_dir)
  let provider = orient_store_test_provider()
  let handle = rebuild_empty_cache(config, provider)
  let layout = orient_cache_layout(config)
  @async_fs.rmdir(layout.vcdb_dir, recursive=true) catch {
    _ => fail("failed to remove vcdb dir fixture")
  }
  @fs.write_string_to_file(layout.vcdb_dir, "not a directory\n") catch {
    _ => fail("failed to replace vcdb dir fixture")
  }
  try {
    checkpoint_cache(handle)
    fail("expected checkpoint failure to raise a cache error")
  } catch {
    OrientCacheCheckpointFailure(message) =>
      assert_true(message.contains("checkpoint"))
    _ => fail("expected OrientCacheCheckpointFailure")
  }
}
