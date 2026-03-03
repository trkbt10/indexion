// White-box tests for graph assembler.

///|
test "assemble_graph empty manifest" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let manifest = @manifest.create_manifest(spec_hash)
  let store = @store.MemoryChunkStore::new()
  let result = assemble_graph(manifest, store)
  assert_eq(result.graph.module_count(), 0)
  assert_eq(result.loaded_chunks.length(), 0)
  assert_eq(result.missing_chunks.length(), 0)
  assert_true(result.is_complete())
}

///|
test "assemble_graph single chunk" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let store = @store.MemoryChunkStore::new()

  // Use helper graph to build the module node
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    chunk_hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )

  // Add a symbol using the helper graph
  let sym = helper.get_or_add_symbol(
    "src/main.ts#foo",
    name="foo",
    kind="function",
    ns="main",
    module_id="src/main.ts",
  )
  chunk.add_symbol("src/main.ts#foo", sym)

  // Add an edge using the helper
  helper.add_edge(
    @graph.EdgeKind::from_string("declares"),
    "src/main.ts",
    "src/main.ts#foo",
    attrs=Map::new(),
  )
  let edges = helper.get_edges()
  if edges.length() > 0 {
    chunk.add_edge(edges[0])
  }
  store.put(chunk)
  let manifest = @manifest.create_manifest(spec_hash)
  let updated = @manifest.update_manifest(manifest, "src/main.ts", chunk_hash)
  let result = assemble_graph(updated, store)
  assert_eq(result.graph.module_count(), 1)
  assert_eq(result.graph.symbol_count(), 1)
  assert_eq(result.graph.edge_count(), 1)
  assert_eq(result.loaded_chunks.length(), 1)
  assert_true(result.is_complete())
}

///|
test "assemble_graph missing chunk" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let store = @store.MemoryChunkStore::new()
  // Don't add chunk to store
  let manifest = @manifest.create_manifest(spec_hash)
  let updated = @manifest.update_manifest(manifest, "src/main.ts", chunk_hash)
  let result = assemble_graph(updated, store)
  assert_eq(result.graph.module_count(), 0)
  assert_eq(result.loaded_chunks.length(), 0)
  assert_eq(result.missing_chunks.length(), 1)
  assert_eq(result.missing_chunks[0], "src/main.ts")
  assert_false(result.is_complete())
}

///|
test "assemble_graph multiple chunks" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let store = @store.MemoryChunkStore::new()
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let mod2 = helper.get_or_add_module("src/b.ts", file=Some("src/b.ts"))
  let chunk1 = @types.ModuleChunk::new(
    chunk_hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  let chunk2 = @types.ModuleChunk::new(
    chunk_hash2, "src/b.ts", mod2, source_hash, spec_hash,
  )
  store.put(chunk1)
  store.put(chunk2)
  let manifest = @manifest.create_manifest(spec_hash)
  let updated1 = @manifest.update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = @manifest.update_manifest(updated1, "src/b.ts", chunk_hash2)
  let result = assemble_graph(updated2, store)
  assert_eq(result.graph.module_count(), 2)
  assert_eq(result.loaded_chunks.length(), 2)
  assert_true(result.is_complete())
}

///|
test "assemble_graph with external refs" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let store = @store.MemoryChunkStore::new()
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    chunk_hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )

  // Add external reference
  let ext_ref = @types.SymbolicRef::new(
    "npm:lodash", "moduleDependsOn", "import _ from 'lodash'",
  )
  chunk.add_external_ref(ext_ref)
  store.put(chunk)
  let manifest = @manifest.create_manifest(spec_hash)
  let updated = @manifest.update_manifest(manifest, "src/main.ts", chunk_hash)
  let result = assemble_graph(updated, store)
  assert_eq(result.unresolved_refs.length(), 1)
  assert_eq(result.unresolved_refs[0], "npm:lodash")
  assert_false(result.all_resolved())
}

///|
test "assemble_partial_graph" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let store = @store.MemoryChunkStore::new()
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let mod2 = helper.get_or_add_module("src/b.ts", file=Some("src/b.ts"))
  let chunk1 = @types.ModuleChunk::new(
    chunk_hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  let chunk2 = @types.ModuleChunk::new(
    chunk_hash2, "src/b.ts", mod2, source_hash, spec_hash,
  )
  store.put(chunk1)
  store.put(chunk2)
  let manifest = @manifest.create_manifest(spec_hash)
  let updated1 = @manifest.update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = @manifest.update_manifest(updated1, "src/b.ts", chunk_hash2)

  // Only assemble src/a.ts
  let result = assemble_partial_graph(updated2, store, ["src/a.ts"])
  assert_eq(result.graph.module_count(), 1)
  assert_eq(result.loaded_chunks.length(), 1)
  assert_true(result.is_complete())
}

///|
test "get_manifest_stats" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let manifest = @manifest.create_manifest(spec_hash)
  let updated1 = @manifest.update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = @manifest.update_manifest(updated1, "src/b.ts", chunk_hash2)
  let (total, unique) = get_manifest_stats(updated2)
  assert_eq(total, 2)
  assert_eq(unique, 2)
}

///|
test "validate_manifest" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let store = @store.MemoryChunkStore::new()

  // Only add chunk1
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let chunk1 = @types.ModuleChunk::new(
    chunk_hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  store.put(chunk1)
  let manifest = @manifest.create_manifest(spec_hash)
  let updated1 = @manifest.update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = @manifest.update_manifest(updated1, "src/b.ts", chunk_hash2)
  let missing = validate_manifest(updated2, store)
  assert_eq(missing.length(), 1)
  assert_eq(missing[0], "src/b.ts")
}

///|
test "AssemblyResult::empty" {
  let result = AssemblyResult::empty()
  assert_eq(result.graph.module_count(), 0)
  assert_true(result.is_complete())
  assert_true(result.all_resolved())
}
