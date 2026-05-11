///|
async test "orient cache runtime: native primitives are reachable" {
  let config = {
    ..AgentOrientConfig::default(),
    cache_dir: "_build/orient-cache-runtime-integration",
  }
  let runtime = prepare_orient_cache_runtime(config)
  assert_true(runtime.persistence_ready)
  assert_true(runtime.embedding_ready)
  assert_true(runtime.path_hash_ready)
  assert_true(runtime.filter_ready)
  let first_lock = try_acquire_orient_writer_lock(config)
  guard first_lock is Some(lock) else {
    fail("expected first writer lock acquisition to succeed")
  }
  let second_lock = try_acquire_orient_writer_lock(config)
  assert_true(second_lock is None)
  lock.release()
}
