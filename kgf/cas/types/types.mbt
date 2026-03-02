// Type definitions for CAS (Content-Addressable Storage).
// CAS enables efficient monorepo analysis through content-addressed chunks.

///|
/// Content hash (SHA-256 truncated to 32 hex characters).
/// Used as content-addressed identifier for chunks.
pub struct ContentHash {
  value : String
} derive(Eq, Show, ToJson, @json.FromJson, Hash)

///|
/// A symbolic reference to an external module (not yet resolved).
/// Examples:
/// - "npm:lodash" - external npm package
/// - "@myorg/core:src/utils.ts" - workspace package module
/// - "shared:src/helpers.ts" - unscoped workspace package
pub struct SymbolicRef {
  /// The symbolic reference string.
  ref_str : String
  /// Edge kind that produced this reference (e.g., "moduleDependsOn", "import").
  edge_kind : String
  /// Original import specifier from source code.
  via : String
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// A chunk represents a single module's contribution to the graph.
/// Each source file produces one chunk containing:
/// - The module node itself
/// - All symbols declared in that module
/// - All edges originating from that module
/// - References to external modules (symbolic, resolved later)
pub struct ModuleChunk {
  /// Content hash of this chunk.
  hash : ContentHash
  /// Module ID (relative path from project root).
  module_id : String
  /// The module node data.
  module_node : @graph.ModuleNode
  /// Symbols declared in this module (id -> symbol).
  symbols : Map[String, @graph.SymbolNode]
  /// Edges originating from this module.
  edges : Array[@graph.Edge]
  /// Source file content hash (for change detection).
  source_hash : ContentHash
  /// KGF spec hash used when generating this chunk.
  spec_hash : ContentHash
  /// Symbolic references to external modules.
  external_refs : Array[SymbolicRef]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Root manifest for a KGF CAS store.
/// This is the entry point for accessing the cached graph.
pub struct CASManifest {
  /// Creation timestamp (ISO 8601).
  created_at : String
  /// Last update timestamp (ISO 8601).
  updated_at : String
  /// KGF spec hash currently in use (for invalidation).
  spec_hash : ContentHash
  /// Map of module ID to chunk hash.
  modules : Map[String, ContentHash]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
/// Error information for indexing failures.
pub struct IndexError {
  module_id : String
  error : String
} derive(Eq, Show)

///|
/// Result of indexing a single module.
pub enum IndexModuleResult {
  /// Successfully indexed the module.
  Success(ModuleChunk)
  /// Module was already cached and valid.
  Cached(ContentHash)
  /// Error occurred during indexing.
  Error(IndexError)
} derive(Eq, Show)

///|
/// Create a new SymbolicRef.
pub fn SymbolicRef::new(
  ref_str : String,
  edge_kind : String,
  via : String
) -> SymbolicRef {
  { ref_str, edge_kind, via }
}

///|
/// Create a new ModuleChunk.
pub fn ModuleChunk::new(
  hash : ContentHash,
  module_id : String,
  module_node : @graph.ModuleNode,
  source_hash : ContentHash,
  spec_hash : ContentHash
) -> ModuleChunk {
  {
    hash,
    module_id,
    module_node,
    symbols: Map::new(),
    edges: [],
    source_hash,
    spec_hash,
    external_refs: [],
  }
}

///|
/// Add a symbol to the chunk.
pub fn ModuleChunk::add_symbol(
  self : ModuleChunk,
  id : String,
  symbol : @graph.SymbolNode
) -> Unit {
  self.symbols.set(id, symbol)
}

///|
/// Add an edge to the chunk.
pub fn ModuleChunk::add_edge(self : ModuleChunk, edge : @graph.Edge) -> Unit {
  self.edges.push(edge)
}

///|
/// Add an external reference to the chunk.
pub fn ModuleChunk::add_external_ref(
  self : ModuleChunk,
  ref : SymbolicRef
) -> Unit {
  self.external_refs.push(ref)
}

///|
/// Get the ContentHash value as a String.
pub fn ContentHash::to_string(self : ContentHash) -> String {
  self.value
}

///|
/// Create a ContentHash from a String (no validation).
pub fn ContentHash::from_string(s : String) -> ContentHash {
  { value: s }
}

///|
/// Create a new CASManifest.
pub fn CASManifest::new(
  created_at : String,
  updated_at : String,
  spec_hash : ContentHash,
  modules : Map[String, ContentHash]
) -> CASManifest {
  { created_at, updated_at, spec_hash, modules }
}

///|
/// Create a new CASManifest with updated modules.
pub fn CASManifest::with_modules(
  self : CASManifest,
  modules : Map[String, ContentHash],
  updated_at : String
) -> CASManifest {
  {
    created_at: self.created_at,
    updated_at,
    spec_hash: self.spec_hash,
    modules,
  }
}

///|
/// Create a new CASManifest with new spec hash (clears modules).
pub fn CASManifest::with_spec_hash(
  self : CASManifest,
  spec_hash : ContentHash,
  updated_at : String
) -> CASManifest {
  {
    created_at: self.created_at,
    updated_at,
    spec_hash,
    modules: Map::new(),
  }
}
