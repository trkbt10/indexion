///|
fn orient_layout_test_config(name : String) -> AgentOrientConfig {
  {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-layout/" + name,
  }
}

///|
fn orient_layout_test_provider(dim : Int) -> @text_embed.TfidfEmbeddingProvider {
  let provider = @text_embed.TfidfEmbeddingProvider::new(dim)
  provider.build_vocabulary([
    "owner implementation cache metadata", "consumer surface vocabulary storage",
  ])
  provider
}

///|
fn observe_layout_init_error(
  config : AgentOrientConfig,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> String? {
  try {
    initialize_layout_for(config, provider)
    None
  } catch {
    LayoutStorageError(message) => Some(message)
  }
}

///|
async fn reset_orient_layout_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "orient vcdb layout: paths live under versioned cache root" {
  let config = orient_layout_test_config("paths")
  reset_orient_layout_fixture(config.cache_dir)
  let layout = layout_for(config)
  assert_eq(layout.root_dir, config.cache_dir + "/orient-vcdb")
  assert_eq(
    layout.metadata_path,
    config.cache_dir + "/orient-vcdb/metadata.json",
  )
  assert_eq(
    layout.vocabulary_path,
    config.cache_dir + "/orient-vcdb/tfidf-vocabulary.json",
  )
  assert_eq(
    layout.writer_lock_path,
    config.cache_dir + "/orient-vcdb/writer.lock",
  )
  assert_eq(layout.vcdb_dir, config.cache_dir + "/orient-vcdb/vcdb")
  assert_eq(layout.old_map_path, config.cache_dir + "/orient-map.json")
  assert_eq(writer_lock_path(config), layout.writer_lock_path)
  assert_eq(db_dir(config), layout.vcdb_dir)
}

///|
async test "orient vcdb layout: initializing fresh cache writes bounded metadata and vocabulary" {
  let config = orient_layout_test_config("fresh")
  reset_orient_layout_fixture(config.cache_dir)
  let provider = orient_layout_test_provider(8)
  initialize_layout_for(config, provider)
  let layout = layout_for(config)
  assert_true(@fs.path_exists(layout.metadata_path))
  assert_true(@fs.path_exists(layout.vocabulary_path))
  assert_true(@fs.path_exists(layout.vcdb_dir))
  guard read_metadata(layout) is Some(metadata) else {
    fail("expected orient cache metadata")
  }
  assert_eq(metadata.cache_version, cache_version())
  assert_eq(metadata.cache_version, "agent-orient-vcdb-v1")
  assert_eq(metadata.schema_version, cache_schema_version())
  assert_eq(metadata.dim, provider.dim())
  assert_eq(metadata.created_by, "indexion-agent-orient")
  let decision = decide_open(config, ReadWrite, provider)
  assert_eq(decision, Ready(layout))
}

///|
async test "orient vcdb layout: old json cache path is recognized without parsing" {
  let config = orient_layout_test_config("old-json")
  reset_orient_layout_fixture(config.cache_dir)
  @config_paths.ensure_dir_recursive(config.cache_dir)
  @fs.write_string_to_file(@map.orient_map_path(config), "{not valid json") catch {
    _ => fail("failed to write old cache fixture")
  }
  let provider = orient_layout_test_provider(8)
  assert_eq(decide_open(config, ReadWrite, provider), FreshBuild(OldJsonLayout))
}

///|
async test "orient vcdb layout: cache version metadata mismatch invalidates cache" {
  let config = orient_layout_test_config("metadata-version")
  reset_orient_layout_fixture(config.cache_dir)
  let provider = orient_layout_test_provider(8)
  initialize_layout_for(config, provider)
  let layout = layout_for(config)
  @fs.write_string_to_file(
    layout.metadata_path,
    "{\n" +
    "  \"cache_version\": \"agent-orient-map-v1\",\n" +
    "  \"schema_version\": 1,\n" +
    "  \"dim\": 8,\n" +
    "  \"created_by\": \"legacy\"\n" +
    "}\n",
  ) catch {
    _ => fail("failed to write mismatched metadata fixture")
  }
  assert_eq(
    decide_open(config, ReadWrite, provider),
    FreshBuild(CacheVersionMismatch("agent-orient-map-v1")),
  )
}

///|
async test "orient vcdb layout: read only invalid cache reports unavailable and does not mutate" {
  let config = orient_layout_test_config("read-only-old-json")
  reset_orient_layout_fixture(config.cache_dir)
  @config_paths.ensure_dir_recursive(config.cache_dir)
  @fs.write_string_to_file(@map.orient_map_path(config), "{still not json") catch {
    _ => fail("failed to write old cache fixture")
  }
  let provider = orient_layout_test_provider(8)
  let layout = layout_for(config)
  assert_eq(decide_open(config, ReadOnly, provider), Unavailable(OldJsonLayout))
  assert_true(!@fs.path_exists(layout.root_dir))
}

///|
async test "orient vcdb layout: missing vocabulary invalidates otherwise current metadata" {
  let config = orient_layout_test_config("missing-vocabulary")
  reset_orient_layout_fixture(config.cache_dir)
  let provider = orient_layout_test_provider(8)
  initialize_layout_for(config, provider)
  let layout = layout_for(config)
  @fs.remove_file(layout.vocabulary_path) catch {
    _ => fail("failed to remove vocabulary fixture")
  }
  assert_eq(
    decide_open(config, ReadWrite, provider),
    FreshBuild(MissingVocabulary),
  )
}

///|
async test "orient vcdb layout: metadata write failure is observable" {
  let config = orient_layout_test_config("metadata-write-error")
  reset_orient_layout_fixture(config.cache_dir)
  let provider = orient_layout_test_provider(8)
  let layout = layout_for(config)
  @config_paths.ensure_dir_recursive(layout.metadata_path)
  guard observe_layout_init_error(config, provider) is Some(message) else {
    fail("expected metadata write failure to be observable")
  }
  assert_true(message.contains("metadata"))
  assert_true(message.contains(layout.metadata_path))
}

///|
async test "orient vcdb layout: vocabulary write failure is observable" {
  let config = orient_layout_test_config("vocabulary-write-error")
  reset_orient_layout_fixture(config.cache_dir)
  let provider = orient_layout_test_provider(8)
  let layout = layout_for(config)
  @config_paths.ensure_dir_recursive(layout.vocabulary_path)
  guard observe_layout_init_error(config, provider) is Some(message) else {
    fail("expected vocabulary write failure to be observable")
  }
  assert_true(message.contains("vocabulary"))
  assert_true(message.contains(layout.vocabulary_path))
}
