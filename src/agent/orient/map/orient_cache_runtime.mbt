///|
pub(all) struct OrientCacheRuntimeReadiness {
  persistence_ready : Bool
  embedding_ready : Bool
  path_hash_ready : Bool
  filter_ready : Bool
  lock_path : String
  cache_exists : Bool
} derive(Eq, Debug)

///|
pub(all) suberror OrientWriterLockError {
  WriterAlreadyActive(String)
  WriterLockStorageError(String)
}

///|
#warnings("-unused_value")
fn OrientWriterLockError::diagnostic(self : OrientWriterLockError) -> String {
  match self {
    WriterAlreadyActive(path) =>
      "orient vcdb writer is already active for `" + path + "`"
    WriterLockStorageError(message) => message
  }
}

///|
fn orient_cache_db_dir(config : AgentOrientConfig) -> String {
  orient_cache_layout(config).vcdb_dir
}

///|
fn orient_cache_db_name() -> String {
  "orient-files"
}

///|
fn orient_cache_vector_dim() -> Int {
  256
}

///|
pub fn orient_writer_lock_path(config : AgentOrientConfig) -> String {
  orient_cache_layout(config).writer_lock_path
}

///|
pub fn orient_path_vector_id(path : String) -> @vcdb_types.VectorId {
  vector_id_for_path(path)
}

///|
type OrientNativePersistentDB = @vcdb.PersistentDB[
  @vcdb_storage.NativeFileStorage,
  @vcdb_storage.NativeFileStorage,
]

///|
struct OrientWriterLock {
  file : @async_fs.File
  mut released : Bool
}

///|
pub async fn prepare_orient_cache_runtime(
  config : AgentOrientConfig,
) -> OrientCacheRuntimeReadiness {
  let layout = orient_cache_layout(config)
  let cache_exists = @async_fs.exists(layout.root_dir)
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
    path_hash_ready: path_id.as_int64() is Some(_),
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
) -> OrientWriterLock raise OrientWriterLockError {
  let layout = orient_cache_layout(config)
  let root_exists = @async_fs.exists(layout.root_dir) catch {
    err =>
      raise WriterLockStorageError(
        "failed to inspect orient vcdb lock directory `" +
        layout.root_dir +
        "`: " +
        err.to_string(),
      )
  }
  if !root_exists {
    @async_fs.mkdir(layout.root_dir, permission=0o755, recursive=true) catch {
      err =>
        raise WriterLockStorageError(
          "failed to create orient vcdb lock directory `" +
          layout.root_dir +
          "`: " +
          err.to_string(),
        )
    }
  }
  let path = layout.writer_lock_path
  let file = @async_fs.open(path, mode=ReadWrite, create=0o644) catch {
    err =>
      raise WriterLockStorageError(
        "failed to open orient vcdb writer lock `" +
        path +
        "`: " +
        err.to_string(),
      )
  }
  let locked = file.try_lock(Exclusive) catch {
    err => {
      file.close()
      raise WriterLockStorageError(
        "failed to lock orient vcdb writer lock `" +
        path +
        "`: " +
        err.to_string(),
      )
    }
  }
  if locked {
    { file, released: false }
  } else {
    file.close()
    raise WriterAlreadyActive(path)
  }
}

///|
pub fn OrientWriterLock::release(self : OrientWriterLock) -> Unit {
  if !self.released {
    self.released = true
    self.file.unlock()
    self.file.close()
  }
}
