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
  let hash = @cas_hash.compute_hash(path).to_string()
  @vcdb_types.VectorId::from_bytes16(hash_to_bytes16(hash))
}

///|
fn hash_to_bytes16(hash : String) -> @vcdb_types.Bytes16 {
  @vcdb_types.Bytes16::new(
    hex_byte_at(hash, 0),
    hex_byte_at(hash, 2),
    hex_byte_at(hash, 4),
    hex_byte_at(hash, 6),
    hex_byte_at(hash, 8),
    hex_byte_at(hash, 10),
    hex_byte_at(hash, 12),
    hex_byte_at(hash, 14),
    hex_byte_at(hash, 16),
    hex_byte_at(hash, 18),
    hex_byte_at(hash, 20),
    hex_byte_at(hash, 22),
    hex_byte_at(hash, 24),
    hex_byte_at(hash, 26),
    hex_byte_at(hash, 28),
    hex_byte_at(hash, 30),
  )
}

///|
fn hex_byte_at(hash : String, offset : Int) -> Byte {
  let high = hash[offset].to_int().unsafe_to_char()
  let low = hash[offset + 1].to_int().unsafe_to_char()
  ((hex_nibble(high) << 4) | hex_nibble(low)).to_byte()
}

///|
fn hex_nibble(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    0
  }
}
