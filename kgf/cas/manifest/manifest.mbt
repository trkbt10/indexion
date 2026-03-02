// Manifest management for KGF Content-Addressable Storage.
// The manifest ties together module chunks with their content hashes.

///|
/// Create an empty manifest with the given spec hash.
pub fn create_manifest(spec_hash : @types.ContentHash) -> @types.CASManifest {
  let now = get_timestamp()
  @types.CASManifest::new(now, now, spec_hash, Map::new())
}

///|
/// Get current timestamp as ISO 8601 string.
/// Note: This is a placeholder implementation for MoonBit.
/// In production, this would use actual system time.
fn get_timestamp() -> String {
  "2026-01-01T00:00:00.000Z"
}

///|
/// Update manifest with a new module chunk.
/// Returns a new manifest with the updated module mapping.
pub fn update_manifest(
  manifest : @types.CASManifest,
  module_id : String,
  chunk_hash : @types.ContentHash
) -> @types.CASManifest {
  let new_modules : Map[String, @types.ContentHash] = Map::new()
  for entry in manifest.modules {
    new_modules.set(entry.0, entry.1)
  }
  new_modules.set(module_id, chunk_hash)
  manifest.with_modules(new_modules, get_timestamp())
}

///|
/// Remove a module from the manifest.
/// Returns a new manifest without the specified module.
pub fn remove_module(
  manifest : @types.CASManifest,
  module_id : String
) -> @types.CASManifest {
  let new_modules : Map[String, @types.ContentHash] = Map::new()
  for entry in manifest.modules {
    if entry.0 != module_id {
      new_modules.set(entry.0, entry.1)
    }
  }
  manifest.with_modules(new_modules, get_timestamp())
}

///|
/// Check if a chunk for a module is still valid given the current source hash.
/// A chunk is valid if:
/// 1. The module exists in the manifest
/// 2. The chunk exists in the store
/// 3. The source hash matches
/// 4. The spec hash matches
pub fn is_chunk_valid(
  manifest : @types.CASManifest,
  store : @store.MemoryChunkStore,
  module_id : String,
  current_source_hash : @types.ContentHash
) -> Bool {
  // Check if module exists in manifest
  match manifest.modules.get(module_id) {
    None => false
    Some(chunk_hash) =>
      // Check if chunk exists in store
      match store.get(chunk_hash) {
        None => false
        Some(chunk) =>
          // Check source hash and spec hash match
          chunk.source_hash == current_source_hash &&
          chunk.spec_hash == manifest.spec_hash
      }
  }
}

///|
/// Get the chunk hash for a module if it exists.
pub fn get_chunk_hash(
  manifest : @types.CASManifest,
  module_id : String
) -> @types.ContentHash? {
  manifest.modules.get(module_id)
}

///|
/// Check if a module exists in the manifest.
pub fn has_module(manifest : @types.CASManifest, module_id : String) -> Bool {
  manifest.modules.contains(module_id)
}

///|
/// Get all module IDs in the manifest.
pub fn get_module_ids(manifest : @types.CASManifest) -> Array[String] {
  let ids : Array[String] = []
  for entry in manifest.modules {
    ids.push(entry.0)
  }
  ids
}

///|
/// Get all chunk hashes referenced in the manifest.
pub fn get_chunk_hashes(
  manifest : @types.CASManifest
) -> Array[@types.ContentHash] {
  let hashes : Array[@types.ContentHash] = []
  for entry in manifest.modules {
    hashes.push(entry.1)
  }
  hashes
}

///|
/// Count the number of modules in the manifest.
pub fn module_count(manifest : @types.CASManifest) -> Int {
  manifest.modules.length()
}

///|
/// Check if the manifest is empty.
pub fn is_empty(manifest : @types.CASManifest) -> Bool {
  manifest.modules.length() == 0
}

///|
/// Check if the spec hash matches.
pub fn spec_matches(
  manifest : @types.CASManifest,
  spec_hash : @types.ContentHash
) -> Bool {
  manifest.spec_hash == spec_hash
}

///|
/// Create a new manifest with updated spec hash.
/// This effectively invalidates all cached chunks.
pub fn update_spec_hash(
  manifest : @types.CASManifest,
  new_spec_hash : @types.ContentHash
) -> @types.CASManifest {
  manifest.with_spec_hash(new_spec_hash, get_timestamp())
}

///|
/// Merge another manifest into this one.
/// Modules from the other manifest override this one.
pub fn merge(
  manifest : @types.CASManifest,
  other : @types.CASManifest
) -> @types.CASManifest {
  let new_modules : Map[String, @types.ContentHash] = Map::new()
  // Copy this manifest's modules
  for entry in manifest.modules {
    new_modules.set(entry.0, entry.1)
  }
  // Override with other manifest's modules
  for entry in other.modules {
    new_modules.set(entry.0, entry.1)
  }
  manifest.with_modules(new_modules, get_timestamp())
}
