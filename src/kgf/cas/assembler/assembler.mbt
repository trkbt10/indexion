// Graph assembler for Content-Addressable Storage.
// Assembles a complete CodeGraph from cached chunks.

///|
/// Result of graph assembly.
pub struct AssemblyResult {
  /// Assembled graph.
  graph : @graph.CodeGraph
  /// Chunks that were loaded.
  loaded_chunks : Array[@types.ContentHash]
  /// Missing chunks (referenced but not found).
  missing_chunks : Array[String]
  /// Unresolved references.
  unresolved_refs : Array[String]
} derive(Eq, Show)

///|
/// Assemble a complete CodeGraph from cached chunks.
pub fn assemble_graph(
  manifest : @types.CASManifest,
  store : @store.MemoryChunkStore,
) -> AssemblyResult {
  let graph = @graph.CodeGraph::new()
  let loaded_chunks : Array[@types.ContentHash] = []
  let missing_chunks : Array[String] = []
  let unresolved_refs : Array[String] = []
  let loaded_chunk_data : Array[@types.ModuleChunk] = []

  // Load and merge chunks for all modules in manifest
  for entry in manifest.modules {
    let module_id = entry.0
    let hash = entry.1
    match store.get(hash) {
      None => missing_chunks.push(module_id)
      Some(chunk) => {
        merge_chunk(graph, chunk)
        loaded_chunks.push(hash)
        loaded_chunk_data.push(chunk)
      }
    }
  }

  // Collect unresolved external references
  for chunk in loaded_chunk_data {
    for ext_ref in chunk.external_refs {
      // Check if the referenced module exists in the graph
      if not(graph.modules.contains(ext_ref.ref_str)) {
        unresolved_refs.push(ext_ref.ref_str)
      }
    }
  }

  { graph, loaded_chunks, missing_chunks, unresolved_refs }
}

///|
/// Merge a chunk into the graph.
fn merge_chunk(graph : @graph.CodeGraph, chunk : @types.ModuleChunk) -> Unit {
  // Add module
  let _ = graph.get_or_add_module(chunk.module_id, file=chunk.module_node.file)

  // Add symbols
  for entry in chunk.symbols {
    let id = entry.0
    let sym = entry.1
    let _ = graph.get_or_add_symbol(
      id,
      name=sym.name,
      kind=sym.kind,
      ns=sym.ns,
      module_id=sym.module_id,
    )
  }

  // Add edges
  for edge in chunk.edges {
    graph.add_edge(edge.kind, edge.from, edge.to, attrs=edge.attrs)
  }
}

///|
/// Assemble graph for specific modules only.
pub fn assemble_partial_graph(
  manifest : @types.CASManifest,
  store : @store.MemoryChunkStore,
  module_ids : Array[String],
) -> AssemblyResult {
  let graph = @graph.CodeGraph::new()
  let loaded_chunks : Array[@types.ContentHash] = []
  let missing_chunks : Array[String] = []
  let unresolved_refs : Array[String] = []
  let loaded_chunk_data : Array[@types.ModuleChunk] = []

  // Load and merge chunks for specified modules
  for module_id in module_ids {
    match manifest.modules.get(module_id) {
      None => missing_chunks.push(module_id)
      Some(hash) =>
        match store.get(hash) {
          None => missing_chunks.push(module_id)
          Some(chunk) => {
            merge_chunk(graph, chunk)
            loaded_chunks.push(hash)
            loaded_chunk_data.push(chunk)
          }
        }
    }
  }

  // Collect unresolved external references
  for chunk in loaded_chunk_data {
    for ext_ref in chunk.external_refs {
      if not(graph.modules.contains(ext_ref.ref_str)) {
        unresolved_refs.push(ext_ref.ref_str)
      }
    }
  }

  { graph, loaded_chunks, missing_chunks, unresolved_refs }
}

///|
/// Get summary statistics for the manifest.
pub fn get_manifest_stats(manifest : @types.CASManifest) -> (Int, Int) {
  // Returns (total_modules, unique_hashes)
  let unique_hashes : Map[@types.ContentHash, Unit] = Map::new()
  for entry in manifest.modules {
    unique_hashes.set(entry.1, ())
  }
  (manifest.modules.length(), unique_hashes.length())
}

///|
/// Validate that all chunks referenced in manifest exist in store.
pub fn validate_manifest(
  manifest : @types.CASManifest,
  store : @store.MemoryChunkStore,
) -> Array[String] {
  let missing : Array[String] = []
  for entry in manifest.modules {
    let module_id = entry.0
    let hash = entry.1
    if not(store.has(hash)) {
      missing.push(module_id)
    }
  }
  missing
}

///|
/// Create an empty assembly result.
pub fn AssemblyResult::empty() -> AssemblyResult {
  {
    graph: @graph.CodeGraph::new(),
    loaded_chunks: [],
    missing_chunks: [],
    unresolved_refs: [],
  }
}

///|
/// Check if the assembly was successful (no missing chunks).
pub fn AssemblyResult::is_complete(self : AssemblyResult) -> Bool {
  self.missing_chunks.length() == 0
}

///|
/// Check if all references were resolved.
pub fn AssemblyResult::all_resolved(self : AssemblyResult) -> Bool {
  self.unresolved_refs.length() == 0
}
