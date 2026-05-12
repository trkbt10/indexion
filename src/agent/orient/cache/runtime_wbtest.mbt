///|
async test "orient cache runtime: native primitives are reachable" {
  let config = {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-runtime-integration",
  }
  let runtime = prepare_runtime(config)
  assert_true(runtime.persistence_ready)
  assert_true(runtime.embedding_ready)
  assert_true(runtime.path_hash_ready)
  assert_true(runtime.filter_ready)
  let lock = try_acquire_writer_lock(config)
  lock.release()
}

///|
async fn reset_orient_runtime_fixture(cache_dir : String) -> Unit {
  @async_fs.rmdir(cache_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async fn observe_writer_lock_conflict(config : AgentOrientConfig) -> String? {
  try {
    let lock = try_acquire_writer_lock(config)
    lock.release()
    None
  } catch {
    WriterAlreadyActive(path) => Some(path)
    WriterLockStorageError(message) =>
      fail("unexpected writer lock storage error: " + message)
  }
}

///|
async test "orient cache runtime: second writer gets typed conflict before cache mutation" {
  let config = {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-runtime-conflict",
  }
  reset_orient_runtime_fixture(config.cache_dir)
  let layout = layout_for(config)
  let lock = try_acquire_writer_lock(config)
  guard observe_writer_lock_conflict(config) is Some(path) else {
    lock.release()
    fail("expected second writer lock acquisition to raise WriterAlreadyActive")
  }
  assert_eq(path, layout.writer_lock_path)
  assert_true(@fs.path_exists(layout.writer_lock_path))
  assert_true(!@fs.path_exists(layout.metadata_path))
  assert_true(!@fs.path_exists(layout.vocabulary_path))
  assert_true(!@fs.path_exists(layout.vcdb_dir))
  lock.release()
  lock.release()
  let after_release = try_acquire_writer_lock(config)
  after_release.release()
}
