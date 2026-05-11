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
