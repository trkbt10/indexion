// DigestManifest for incremental function index management.
// Tracks function-level hashes and vector IDs for efficient updates.
//
// v4: N-provider support. Each embedding provider has its own vector ID space.
// Providers are identified by string keys (e.g. "tfidf", "text-embedding-3-small").

///|
/// Entry for a single file in the manifest.
pub struct FileEntry {
  /// File path.
  file_path : String
  /// Content hash of the entire file.
  source_hash : @cas_types.ContentHash
  /// Function IDs declared in this file.
  functions : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Entry for a single function in the manifest.
pub struct FunctionEntry {
  /// Function ID (symbol ID).
  function_id : String
  /// Hash of function source.
  source_hash : @types.FunctionHash
  /// Hash including call context.
  context_hash : @types.FunctionHash
  /// Vector IDs per provider (provider_key -> vector_id).
  vector_ids : Map[String, Int64]
  /// Hash of impression (None if no impression).
  impression_hash : @types.FunctionHash?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Per-provider metadata stored in the manifest.
pub(all) struct ProviderMeta {
  /// Provider kind: "tfidf" or "remote".
  kind : String
  /// Embedding vector dimension.
  dim : Int
  /// Model name for display (e.g. "text-embedding-3-small").
  model : String?
  /// API base URL for remote providers (stored without api_key).
  base_url : String?
  /// Monotonic counter for vector IDs in this provider's space.
  vector_id_counter : Int64
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Current manifest schema version. Increment when making incompatible changes.
/// v4: N-provider (dynamic provider registry).
pub const MANIFEST_VERSION : Int = 4

///|
/// DigestManifest tracks function-level indexing state.
pub struct DigestManifest {
  /// Schema version for forward/backward compatibility.
  version : Int
  /// Creation timestamp (ISO 8601).
  created_at : String
  /// Last update timestamp.
  updated_at : String
  /// KGF spec hash for invalidation.
  spec_hash : @cas_types.ContentHash
  /// Provider registry (provider_key -> metadata + counter).
  providers : Map[String, ProviderMeta]
  /// File entries (file_path -> FileEntry).
  files : Map[String, FileEntry]
  /// Function entries (function_id -> FunctionEntry).
  functions : Map[String, FunctionEntry]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Create a new DigestManifest with the given provider registry.
pub fn DigestManifest::new(
  spec_hash : @cas_types.ContentHash,
  providers : Map[String, ProviderMeta],
) -> DigestManifest {
  let now = get_timestamp()
  {
    version: MANIFEST_VERSION,
    created_at: now,
    updated_at: now,
    spec_hash,
    providers,
    files: {},
    functions: {},
  }
}

///|
/// Get current timestamp placeholder.
fn get_timestamp() -> String {
  // Placeholder - in real implementation would use system time
  "2026-01-01T00:00:00.000Z"
}

///|
/// Allocate a new vector ID for a given provider.
pub fn DigestManifest::allocate_vector_id(
  self : DigestManifest,
  provider_key : String,
) -> (DigestManifest, Int64) {
  match self.providers.get(provider_key) {
    Some(meta) => {
      let id = meta.vector_id_counter
      self.providers.set(provider_key, { ..meta, vector_id_counter: id + 1L })
      ({ ..self, updated_at: get_timestamp() }, id)
    }
    None =>
      // Provider not registered — should not happen, but handle gracefully
      (self, 0L)
  }
}

///|
/// Get provider keys.
pub fn DigestManifest::provider_keys(self : DigestManifest) -> Array[String] {
  let keys : Array[String] = []
  for entry in self.providers {
    keys.push(entry.0)
  }
  keys
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
    if !self.is_function_valid(unit.id(), unit.source_hash, unit.context_hash) {
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
    if !current_set.contains(entry.0) {
      deleted.push(entry.0)
    }
  }
  deleted
}

///|
/// Remove deleted functions and return their vector IDs for cleanup.
/// Returns (updated manifest, provider_key -> removed vector IDs).
pub fn DigestManifest::remove_deleted_functions(
  self : DigestManifest,
  current_ids : Array[String],
) -> (DigestManifest, Map[String, Array[Int64]]) {
  let deleted = self.get_deleted_functions(current_ids)
  let removed : Map[String, Array[Int64]] = {}
  let mut manifest = self
  for id in deleted {
    match manifest.functions.get(id) {
      Some(entry) =>
        for vid_entry in entry.vector_ids {
          let key = vid_entry.0
          let vid = vid_entry.1
          match removed.get(key) {
            Some(arr) => arr.push(vid)
            None => removed.set(key, [vid])
          }
        }
      None => ()
    }
    manifest = manifest.remove_function(id)
  }
  (manifest, removed)
}

///|
/// Create a FunctionEntry from a FunctionUnit.
pub fn FunctionEntry::from_unit(
  unit : @types.FunctionUnit,
  vector_ids : Map[String, Int64],
) -> FunctionEntry {
  let impression_hash = match unit.impression {
    Some(imp) => {
      let text = imp.to_text()
      Some(@types.FunctionHash::from_string(text))
    }
    None => None
  }
  {
    function_id: unit.id(),
    source_hash: unit.source_hash,
    context_hash: unit.context_hash,
    vector_ids,
    impression_hash,
  }
}

///|
/// Check if a file's content hash matches the stored hash.
pub fn DigestManifest::is_file_unchanged(
  self : DigestManifest,
  file_path : String,
  current_hash : @cas_types.ContentHash,
) -> Bool {
  match self.files.get(file_path) {
    Some(entry) => entry.source_hash == current_hash
    None => false
  }
}

///|
/// Update or add a file entry in the manifest.
pub fn DigestManifest::update_file(
  self : DigestManifest,
  file_path : String,
  content_hash : @cas_types.ContentHash,
  function_ids : Array[String],
) -> DigestManifest {
  let entry : FileEntry = {
    file_path,
    source_hash: content_hash,
    functions: function_ids,
  }
  self.files.set(file_path, entry)
  { ..self, updated_at: get_timestamp() }
}

///|
/// Serialize manifest to JSON string.
pub fn DigestManifest::to_json_string(self : DigestManifest) -> String {
  self.to_json().stringify()
}

///|
/// Parse manifest from JSON string.
/// Returns None if the JSON is invalid or the manifest version is incompatible,
/// which causes the caller to trigger a full rebuild.
pub fn DigestManifest::from_json_string(json_str : String) -> DigestManifest? {
  let json : Json = @json.parse(json_str) catch { _ => return None }
  match json {
    { "version": Number(v, ..), .. } =>
      if v.to_int() != MANIFEST_VERSION {
        return None
      }
    _ => return None
  }
  let manifest : DigestManifest = @json.from_json(json) catch {
    _ => return None
  }
  Some(manifest)
}

///|
/// Provider description for display purposes.
pub fn DigestManifest::provider_description(self : DigestManifest) -> String {
  let parts : Array[String] = []
  for entry in self.providers {
    let key = entry.0
    let meta = entry.1
    let desc = match meta.model {
      Some(model) => key + " (" + model + ", " + meta.dim.to_string() + " dims)"
      None => key + " (" + meta.kind + ", " + meta.dim.to_string() + " dims)"
    }
    parts.push(desc)
  }
  if parts.length() == 0 {
    "none"
  } else {
    parts.join(" + ")
  }
}
