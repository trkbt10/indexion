///|
pub(all) struct RuntimeReadiness {
  persistence_ready : Bool
  embedding_ready : Bool
  path_hash_ready : Bool
  filter_ready : Bool
  lock_path : String
  cache_exists : Bool
} derive(Eq, Debug)

///|
pub(all) suberror WriterLockError {
  WriterAlreadyActive(String)
  WriterLockStorageError(String)
}

///|
#warnings("-unused_value")
fn WriterLockError::diagnostic(self : WriterLockError) -> String {
  match self {
    WriterAlreadyActive(path) =>
      "orient vcdb writer is already active for `" + path + "`"
    WriterLockStorageError(message) => message
  }
}

///|
fn db_dir(config : AgentOrientConfig) -> String {
  layout_for(config).vcdb_dir
}

///|
fn db_name() -> String {
  "orient-files"
}

///|
fn vector_dim() -> Int {
  256
}

///|
pub fn writer_lock_path(config : AgentOrientConfig) -> String {
  layout_for(config).writer_lock_path
}

///|
type NativePersistentDB = @vcdb.PersistentDB[
  @vcdb_storage.NativeFileStorage,
  @vcdb_storage.NativeFileStorage,
]

///|
struct WriterLock {
  file : @async_fs.File
  mut released : Bool
}

///|
pub async fn prepare_runtime(
  config : AgentOrientConfig,
) -> RuntimeReadiness {
  let layout = layout_for(config)
  let cache_exists = @async_fs.exists(layout.root_dir)
  let _wal_storage = @vcdb_storage.NativeFileStorage::new(
    db_dir(config),
  )
  let _snapshot_storage = @vcdb_storage.NativeFileStorage::new(
    db_dir(config),
  )
  let persistence_ready = native_db_type_ready(None) &&
    db_name().length() > 0
  let provider = @text_embed.TfidfEmbeddingProvider::new(
    vector_dim(),
  )
  provider.build_vocabulary(["orient cache runtime", config.task])
  let sample_vector = provider.embed(config.cache_dir)
  let path_id = vector_id_for_path(config.cache_dir)
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
    sample_vector.length() == vector_dim(),
    path_hash_ready: path_id.as_int64() is Some(_),
    filter_ready: @vcdb_filter.eval_filter(filter, attrs),
    lock_path: writer_lock_path(config),
    cache_exists,
  }
}

///|
fn native_db_type_ready(_db : NativePersistentDB?) -> Bool {
  true
}

///|
pub async fn try_acquire_writer_lock(
  config : AgentOrientConfig,
) -> WriterLock raise WriterLockError {
  let layout = layout_for(config)
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
pub fn WriterLock::release(self : WriterLock) -> Unit {
  if !self.released {
    self.released = true
    self.file.unlock()
    self.file.close()
  }
}
