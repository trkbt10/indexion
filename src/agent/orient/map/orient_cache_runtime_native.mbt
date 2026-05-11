///|
type OrientNativePersistentDB = @vcdb.PersistentDB[
  @vcdb_storage.NativeFileStorage,
  @vcdb_storage.NativeFileStorage,
]

///|
struct OrientWriterLock {
  file : @async_fs.File
}

///|
pub async fn prepare_orient_cache_runtime(
  config : AgentOrientConfig,
) -> OrientCacheRuntimeReadiness {
  let cache_exists = @async_fs.exists(config.cache_dir)
  let _wal_storage = @vcdb_storage.NativeFileStorage::new(
    orient_cache_db_dir(config),
  )
  let _snapshot_storage = @vcdb_storage.NativeFileStorage::new(
    orient_cache_db_dir(config),
  )
  let persistence_ready = orient_native_db_type_ready(None) &&
    orient_cache_db_name().length() > 0
  let provider = @text_embed.TfidfEmbeddingProvider::new(
    orient_cache_vector_dim(),
  )
  provider.build_vocabulary(["orient cache runtime", config.task])
  let sample_vector = provider.embed(config.cache_dir)
  let path_id = orient_path_vector_id(config.cache_dir)
  let attrs = @vcdb.empty_attrs()
  attrs.set("runtime", @vcdb_types.String("orient"))
  attrs.set("path_id", @vcdb_types.String(path_id.to_display_string()))
  let filter = @vcdb_filter.FilterExpr::match_(
    "runtime",
    @vcdb_types.String("orient"),
  )
  {
    persistence_ready,
    embedding_ready: provider.has_vocabulary() &&
    sample_vector.length() == orient_cache_vector_dim(),
    path_hash_ready: path_id.as_bytes16() is Some(_),
    filter_ready: @vcdb_filter.eval_filter(filter, attrs),
    lock_path: orient_writer_lock_path(config),
    cache_exists,
  }
}

///|
fn orient_native_db_type_ready(_db : OrientNativePersistentDB?) -> Bool {
  true
}

///|
pub async fn try_acquire_orient_writer_lock(
  config : AgentOrientConfig,
) -> OrientWriterLock? {
  if !@async_fs.exists(config.cache_dir) {
    @async_fs.mkdir(config.cache_dir, permission=0o755, recursive=true)
  }
  let path = orient_writer_lock_path(config)
  let file = @async_fs.open(path, mode=ReadWrite, create=0o644)
  let locked = file.try_lock(Exclusive) catch { _ => false }
  if locked {
    Some({ file, })
  } else {
    file.close()
    None
  }
}

///|
pub fn OrientWriterLock::release(self : OrientWriterLock) -> Unit {
  self.file.unlock()
  self.file.close()
}
