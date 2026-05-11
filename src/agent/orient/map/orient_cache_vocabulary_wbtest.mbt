///|
fn orient_vocabulary_test_config(name : String) -> AgentOrientConfig {
  {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-vocabulary/" + name,
  }
}

///|
async fn reset_orient_vocabulary_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
fn orient_vocabulary_has_signal(vector : Array[Double]) -> Bool {
  for value in vector {
    if value != 0.0 {
      return true
    }
  }
  false
}

///|
async test "orient vocabulary store: fresh build persists and second run loads vocabulary" {
  let config = orient_vocabulary_test_config("load-second-run")
  reset_orient_vocabulary_fixture(config.cache_dir)
  let built_state = load_or_build_provider(
    config,
    Some(["zephyr zephyr zephyr alpha"]),
    2,
  )
  guard built_state is OrientVocabularyBuilt(provider) else {
    fail("expected fresh cache to build a provider from the full corpus")
  }
  assert_true(orient_vocabulary_has_signal(provider.embed("zephyr")))
  assert_true(!orient_vocabulary_has_signal(provider.embed("mistral")))
  persist_provider(config, provider)
  let loaded_state = load_or_build_provider(
    config,
    Some(["mistral mistral mistral"]),
    2,
  )
  guard loaded_state is OrientVocabularyLoaded(loaded_provider) else {
    fail("expected second run to load the persisted vocabulary")
  }
  assert_true(orient_vocabulary_has_signal(loaded_provider.embed("zephyr")))
  assert_true(!orient_vocabulary_has_signal(loaded_provider.embed("mistral")))
}

///|
async test "orient vocabulary store: missing state invalidates without corpus rebuild" {
  let config = orient_vocabulary_test_config("missing-no-rebuild")
  reset_orient_vocabulary_fixture(config.cache_dir)
  let state = load_or_build_provider(config, None, 4)
  guard state is OrientVocabularyInvalid(reason) else {
    fail("expected missing vocabulary to invalidate without implicit rebuild")
  }
  assert_true(reason == MissingVocabulary)
}

///|
async test "orient vocabulary store: empty payload invalidates cache state" {
  let config = orient_vocabulary_test_config("empty-payload")
  reset_orient_vocabulary_fixture(config.cache_dir)
  let layout = orient_cache_layout(config)
  @config_paths.ensure_dir_recursive(layout.root_dir)
  @fs.write_string_to_file(
    layout.vocabulary_path,
    "{ \"dim\": 4, \"vocabulary\": [], \"idf\": [] }\n",
  ) catch {
    _ => fail("failed to write empty vocabulary fixture")
  }
  let state = load_or_build_provider(config, None, 4)
  guard state is OrientVocabularyInvalid(reason) else {
    fail("expected empty vocabulary to invalidate without implicit rebuild")
  }
  assert_true(reason == VocabularyEmpty)
}

///|
async test "orient vocabulary store: mismatched payload prevents database reuse" {
  let config = orient_vocabulary_test_config("dimension-mismatch")
  reset_orient_vocabulary_fixture(config.cache_dir)
  let metadata_provider = @text_embed.TfidfEmbeddingProvider::new(4)
  metadata_provider.build_vocabulary(["alpha beta gamma delta"])
  initialize_orient_cache_layout(config, metadata_provider)
  let mismatched_provider = @text_embed.TfidfEmbeddingProvider::new(2)
  mismatched_provider.build_vocabulary(["alpha beta"])
  persist_provider(config, mismatched_provider)
  assert_eq(
    decide_orient_cache_open(config, OrientCacheReadWrite, metadata_provider),
    OrientCacheFreshBuild(VocabularyDimensionMismatch(2, 4)),
  )
}
