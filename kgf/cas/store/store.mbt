// Chunk store interfaces and implementations for Content-Addressable Storage.

///|
/// Chunk store trait for reading/writing module chunks.
pub trait ChunkStore {
  /// Read a chunk by its hash.
  get(Self, @types.ContentHash) -> @types.ModuleChunk?
  /// Write a chunk (stores using its hash).
  put(Self, @types.ModuleChunk) -> Unit
  /// Check if a chunk exists.
  has(Self, @types.ContentHash) -> Bool
  /// Delete a chunk.
  delete(Self, @types.ContentHash) -> Bool
  /// List all chunk hashes.
  list(Self) -> Array[@types.ContentHash]
}

///|
/// In-memory chunk store implementation.
/// Useful for testing and short-lived sessions where persistence isn't needed.
pub struct MemoryChunkStore {
  chunks : Map[@types.ContentHash, @types.ModuleChunk]
}

///|
/// Create a new in-memory chunk store.
pub fn MemoryChunkStore::new() -> MemoryChunkStore {
  { chunks: Map::new() }
}

///|
/// Read a chunk by its hash.
pub fn MemoryChunkStore::get(
  self : MemoryChunkStore,
  hash : @types.ContentHash
) -> @types.ModuleChunk? {
  self.chunks.get(hash)
}

///|
/// Write a chunk (stores using its hash).
pub fn MemoryChunkStore::put(
  self : MemoryChunkStore,
  chunk : @types.ModuleChunk
) -> Unit {
  self.chunks.set(chunk.hash, chunk)
}

///|
/// Check if a chunk exists.
pub fn MemoryChunkStore::has(
  self : MemoryChunkStore,
  hash : @types.ContentHash
) -> Bool {
  self.chunks.contains(hash)
}

///|
/// Delete a chunk.
pub fn MemoryChunkStore::delete(
  self : MemoryChunkStore,
  hash : @types.ContentHash
) -> Bool {
  match self.chunks.get(hash) {
    Some(_) => {
      self.chunks.remove(hash)
      true
    }
    None => false
  }
}

///|
/// List all chunk hashes.
pub fn MemoryChunkStore::list(
  self : MemoryChunkStore
) -> Array[@types.ContentHash] {
  let hashes : Array[@types.ContentHash] = []
  for entry in self.chunks {
    hashes.push(entry.0)
  }
  hashes
}

///|
/// Get the number of chunks in the store.
pub fn MemoryChunkStore::size(self : MemoryChunkStore) -> Int {
  self.chunks.size()
}

///|
/// Clear all chunks from the store.
pub fn MemoryChunkStore::clear(self : MemoryChunkStore) -> Unit {
  self.chunks.clear()
}

///|
/// Find orphaned chunks (chunks not referenced in a set of known hashes).
pub fn MemoryChunkStore::find_orphans(
  self : MemoryChunkStore,
  referenced : Array[@types.ContentHash]
) -> Array[@types.ContentHash] {
  let ref_set : Map[@types.ContentHash, Unit] = Map::new()
  for hash in referenced {
    ref_set.set(hash, ())
  }
  let orphans : Array[@types.ContentHash] = []
  for entry in self.chunks {
    if not(ref_set.contains(entry.0)) {
      orphans.push(entry.0)
    }
  }
  orphans
}

///|
/// Clean up orphaned chunks.
/// Returns the number of chunks deleted.
pub fn MemoryChunkStore::clean_orphans(
  self : MemoryChunkStore,
  referenced : Array[@types.ContentHash]
) -> Int {
  let orphans = self.find_orphans(referenced)
  for hash in orphans {
    self.chunks.remove(hash)
  }
  orphans.length()
}
