///|
fn orient_update_test_config(name : String) -> AgentOrientConfig {
  {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-update/" + name,
  }
}

///|
fn orient_update_test_provider() -> @text_embed.TfidfEmbeddingProvider {
  let provider = @text_embed.TfidfEmbeddingProvider::new(8)
  provider.build_vocabulary([
    "unchanged implementation original cache", "changed implementation original source",
    "changed implementation refreshed source", "new command consumer surface", "deleted report implementation",
    "documentation cache guide",
  ])
  provider
}

///|
fn orient_update_test_brief(
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
async fn reset_orient_update_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "orient cache update: applies new changed deleted and skips unchanged" {
  let config = orient_update_test_config("mixed-decisions")
  reset_orient_update_fixture(config.cache_dir)
  let provider = orient_update_test_provider()
  let unchanged_original = orient_update_test_brief(
    "src/agent/orient/map/unchanged.mbt", "implementation", "hash-unchanged-v1",
    "unchanged implementation original cache",
  )
  let changed_original = orient_update_test_brief(
    "src/agent/orient/source/changed.mbt", "implementation", "hash-changed-v1", "changed implementation original source",
  )
  let deleted_original = orient_update_test_brief(
    "src/agent/orient/report/deleted.mbt", "implementation", "hash-deleted-v1", "deleted report implementation",
  )
  let handle = rebuild_empty_cache(config, provider)
  handle.upsert_many(
    [unchanged_original, changed_original, deleted_original],
    timestamp_ns=100L,
  )
  guard handle.lookup_path(changed_original.path) is Some(changed_before) else {
    fail("expected changed record before update")
  }
  let unchanged_current = orient_update_test_brief(
    unchanged_original.path,
    "implementation",
    "hash-unchanged-v1",
    "this summary must not overwrite unchanged cache",
  )
  let changed_current = orient_update_test_brief(
    changed_original.path,
    "implementation",
    "hash-changed-v2",
    "changed implementation refreshed source",
  )
  let new_current = orient_update_test_brief(
    "cmd/indexion/agent/new_cli.mbt", "consumer", "hash-new-v1", "new command consumer surface",
  )
  let result = apply_incremental_cache_updates(
    handle,
    [unchanged_current, changed_current, new_current],
    timestamp_ns=200L,
  )
  assert_eq(result.new_files, [new_current.path])
  assert_eq(result.changed_files, [changed_current.path])
  assert_eq(result.unchanged_files, [unchanged_current.path])
  assert_eq(result.deleted_files.length(), 1)
  assert_eq(result.deleted_files[0], deleted_original.path)
  assert_eq(result.upserted_files.length(), 2)
  assert_true(result.upserted_files.contains(changed_current.path))
  assert_true(result.upserted_files.contains(new_current.path))
  assert_eq(result.embedding_count, 2)
  assert_eq(result.upsert_count, 2)
  assert_eq(result.remove_count, 1)
  assert_eq(handle.count(), 3)
  guard handle.lookup_path(unchanged_original.path) is Some(unchanged_after) else {
    fail("expected unchanged record after update")
  }
  assert_eq(
    unchanged_after.summary_preview,
    "unchanged implementation original cache",
  )
  guard handle.lookup_path(changed_current.path) is Some(changed_after) else {
    fail("expected changed record after update")
  }
  assert_eq(changed_after.vector_id, changed_before.vector_id)
  assert_eq(changed_after.source_hash, "hash-changed-v2")
  assert_eq(
    changed_after.summary_preview,
    "changed implementation refreshed source",
  )
  guard handle.lookup_path(new_current.path) is Some(new_after) else {
    fail("expected new record after update")
  }
  assert_eq(new_after.source_hash, "hash-new-v1")
  assert_true(handle.lookup_path(deleted_original.path) is None)
  assert_eq(result.status.total_files, 3)
  assert_eq(result.status.total_owners, 3)
  assert_eq(result.status.total_doc_sources, 0)
  assert_false(result.status.knowledge_changed)
  assert_true(
    result.status.refreshed_owners.contains("src/agent/orient/source"),
  )
  assert_true(result.status.refreshed_owners.contains("cmd/indexion/agent"))
  assert_true(
    result.status.refreshed_owners.contains("src/agent/orient/report"),
  )
  assert_eq(result.status.reused_owners, ["src/agent/orient/map"])
}

///|
async test "orient cache update: no-op refresh performs zero record work and reports cache status" {
  let config = orient_update_test_config("noop")
  reset_orient_update_fixture(config.cache_dir)
  let provider = orient_update_test_provider()
  let implementation = orient_update_test_brief(
    "src/agent/orient/map/noop_impl.mbt", "implementation", "hash-impl-v1", "unchanged implementation original cache",
  )
  let documentation = orient_update_test_brief(
    "docs/orient-cache.md", "documentation", "hash-doc-v1", "documentation cache guide",
  )
  let handle = rebuild_empty_cache(config, provider)
  handle.upsert_many([implementation, documentation], timestamp_ns=100L)
  let implementation_current = orient_update_test_brief(
    implementation.path,
    "implementation",
    "hash-impl-v1",
    "this implementation summary must be skipped",
  )
  let documentation_current = orient_update_test_brief(
    documentation.path,
    "documentation",
    "hash-doc-v1",
    "this documentation summary must be skipped",
  )
  let result = apply_incremental_cache_updates(
    handle,
    [implementation_current, documentation_current],
    timestamp_ns=200L,
  )
  assert_eq(result.new_files.length(), 0)
  assert_eq(result.changed_files.length(), 0)
  assert_eq(result.deleted_files.length(), 0)
  assert_eq(result.unchanged_files.length(), 2)
  assert_eq(result.upserted_files.length(), 0)
  assert_eq(result.removed_files.length(), 0)
  assert_eq(result.embedding_count, 0)
  assert_eq(result.upsert_count, 0)
  assert_eq(result.remove_count, 0)
  assert_eq(result.status.total_files, 2)
  assert_eq(result.status.total_owners, 2)
  assert_eq(result.status.total_doc_sources, 1)
  assert_false(result.status.knowledge_changed)
  assert_eq(result.status.refreshed_owners.length(), 0)
  assert_true(result.status.reused_owners.contains("src/agent/orient/map"))
  assert_true(result.status.reused_owners.contains("docs"))
  guard handle.lookup_path(implementation.path) is Some(cached_impl) else {
    fail("expected implementation after no-op update")
  }
  assert_eq(
    cached_impl.summary_preview,
    "unchanged implementation original cache",
  )
  guard handle.lookup_path(documentation.path) is Some(cached_doc) else {
    fail("expected documentation after no-op update")
  }
  assert_eq(cached_doc.summary_preview, "documentation cache guide")
  assert_true(cached_doc.summary_full == Some("documentation cache guide"))
}
