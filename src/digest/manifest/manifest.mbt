// DigestManifest for incremental function index management.
// Tracks function-level hashes and vector IDs for efficient updates.

///|
/// Entry for a single file in the manifest.
pub struct FileEntry {
  /// File path.
  file_path : String
  /// Content hash of the entire file.
  source_hash : @cas_types.ContentHash
  /// Function IDs declared in this file.
  functions : Array[String]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Entry for a single function in the manifest.
pub struct FunctionEntry {
  /// Function ID (symbol ID).
  function_id : String
  /// Hash of function source.
  source_hash : @types.FunctionHash
  /// Hash including call context.
  context_hash : @types.FunctionHash
  /// vcdb vector ID (None if not yet indexed).
  vector_id : Int64?
  /// Hash of impression (None if no impression).
  impression_hash : @types.FunctionHash?
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// DigestManifest tracks function-level indexing state.
pub struct DigestManifest {
  /// Creation timestamp (ISO 8601).
  created_at : String
  /// Last update timestamp.
  updated_at : String
  /// KGF spec hash for invalidation.
  spec_hash : @cas_types.ContentHash
  /// Embedding provider identifier.
  embedding_provider : String
  /// Embedding dimension.
  embedding_dim : Int
  /// File entries (file_path -> FileEntry).
  files : Map[String, FileEntry]
  /// Function entries (function_id -> FunctionEntry).
  functions : Map[String, FunctionEntry]
  /// Monotonic counter for vector IDs.
  vector_id_counter : Int64
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Create a new DigestManifest.
pub fn DigestManifest::new(
  spec_hash : @cas_types.ContentHash,
  embedding_provider : String,
  embedding_dim : Int,
) -> DigestManifest {
  let now = get_timestamp()
  {
    created_at: now,
    updated_at: now,
    spec_hash,
    embedding_provider,
    embedding_dim,
    files: {},
    functions: {},
    vector_id_counter: 1L,
  }
}

///|
/// Get current timestamp placeholder.
fn get_timestamp() -> String {
  // Placeholder - in real implementation would use system time
  "2026-01-01T00:00:00.000Z"
}

///|
/// Allocate a new vector ID.
pub fn DigestManifest::allocate_vector_id(
  self : DigestManifest,
) -> (DigestManifest, Int64) {
  let id = self.vector_id_counter
  let updated = {
    ..self,
    vector_id_counter: id + 1L,
    updated_at: get_timestamp(),
  }
  (updated, id)
}

///|
/// Check if a function entry is valid (hashes match).
pub fn DigestManifest::is_function_valid(
  self : DigestManifest,
  function_id : String,
  current_source_hash : @types.FunctionHash,
  current_context_hash : @types.FunctionHash,
) -> Bool {
  match self.functions.get(function_id) {
    Some(entry) =>
      entry.source_hash == current_source_hash &&
      entry.context_hash == current_context_hash
    None => false
  }
}

///|
/// Get function entry if exists.
pub fn DigestManifest::get_function(
  self : DigestManifest,
  function_id : String,
) -> FunctionEntry? {
  self.functions.get(function_id)
}

///|
/// Update or add a function entry.
pub fn DigestManifest::update_function(
  self : DigestManifest,
  entry : FunctionEntry,
) -> DigestManifest {
  self.functions.set(entry.function_id, entry)
  { ..self, updated_at: get_timestamp() }
}

///|
/// Remove a function entry.
pub fn DigestManifest::remove_function(
  self : DigestManifest,
  function_id : String,
) -> DigestManifest {
  self.functions.remove(function_id)
  { ..self, updated_at: get_timestamp() }
}

///|
/// Get all function IDs.
pub fn DigestManifest::get_function_ids(self : DigestManifest) -> Array[String] {
  let result : Array[String] = []
  for entry in self.functions {
    result.push(entry.0)
  }
  result
}

///|
/// Find stale functions that need re-indexing.
pub fn DigestManifest::get_stale_functions(
  self : DigestManifest,
  current_units : Array[@types.FunctionUnit],
) -> Array[String] {
  let stale : Array[String] = []
  for unit in current_units {
    if not(
        self.is_function_valid(unit.id(), unit.source_hash, unit.context_hash),
      ) {
      stale.push(unit.id())
    }
  }
  stale
}

///|
/// Find deleted functions (in manifest but not in current units).
pub fn DigestManifest::get_deleted_functions(
  self : DigestManifest,
  current_ids : Array[String],
) -> Array[String] {
  let current_set : Map[String, Bool] = {}
  for id in current_ids {
    current_set.set(id, true)
  }
  let deleted : Array[String] = []
  for entry in self.functions {
    if not(current_set.contains(entry.0)) {
      deleted.push(entry.0)
    }
  }
  deleted
}

///|
/// Remove deleted functions and return their vector IDs for cleanup.
pub fn DigestManifest::remove_deleted_functions(
  self : DigestManifest,
  current_ids : Array[String],
) -> (DigestManifest, Array[Int64]) {
  let deleted = self.get_deleted_functions(current_ids)
  let removed_ids : Array[Int64] = []
  let mut manifest = self
  for id in deleted {
    match manifest.functions.get(id) {
      Some(entry) =>
        match entry.vector_id {
          Some(vid) => removed_ids.push(vid)
          None => ()
        }
      None => ()
    }
    manifest = manifest.remove_function(id)
  }
  (manifest, removed_ids)
}

///|
/// Create a FunctionEntry from a FunctionUnit.
pub fn FunctionEntry::from_unit(
  unit : @types.FunctionUnit,
  vector_id : Int64?,
) -> FunctionEntry {
  let impression_hash = match unit.impression {
    Some(imp) => {
      // Compute hash from impression text
      let text = imp.to_text()
      Some(@types.FunctionHash::from_string(text))
    }
    None => None
  }
  {
    function_id: unit.id(),
    source_hash: unit.source_hash,
    context_hash: unit.context_hash,
    vector_id,
    impression_hash,
  }
}

///|
/// Serialize manifest to JSON string.
pub fn DigestManifest::to_json_string(self : DigestManifest) -> String {
  self.to_json().stringify()
}

///|
/// Parse manifest from JSON string.
pub fn DigestManifest::from_json_string(json_str : String) -> DigestManifest? {
  let json : Json = @json.parse(json_str) catch { _ => return None }
  let manifest : DigestManifest = @json.from_json(json) catch {
    _ => return None
  }
  Some(manifest)
}
