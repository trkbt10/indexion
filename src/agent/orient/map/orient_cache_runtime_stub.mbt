///|
struct OrientWriterLock {}

///|
#warnings("-unused_async")
pub async fn prepare_orient_cache_runtime(
  config : AgentOrientConfig,
) -> OrientCacheRuntimeReadiness {
  let provider = @text_embed.TfidfEmbeddingProvider::new(
    orient_cache_vector_dim(),
  )
  let attrs = @vcdb.empty_attrs()
  attrs.set("runtime", @vcdb_types.String("orient"))
  let filter = @vcdb_filter.FilterExpr::match_(
    "runtime",
    @vcdb_types.String("orient"),
  )
  let _storage = @vcdb_storage.MemoryStorage::new()
  {
    persistence_ready: false,
    embedding_ready: provider.dim() == orient_cache_vector_dim(),
    path_hash_ready: orient_path_vector_id(config.cache_dir).as_bytes16()
    is Some(_),
    filter_ready: @vcdb_filter.eval_filter(filter, attrs),
    lock_path: orient_writer_lock_path(config),
    cache_exists: false,
  }
}

///|
#warnings("-unused_async")
pub async fn try_acquire_orient_writer_lock(
  config : AgentOrientConfig,
) -> OrientWriterLock raise OrientWriterLockError {
  raise WriterLockStorageError(
    "orient vcdb writer lock is unavailable on this target for `" +
    orient_writer_lock_path(config) +
    "`",
  )
}

///|
pub fn OrientWriterLock::release(_self : OrientWriterLock) -> Unit {
  ()
}
