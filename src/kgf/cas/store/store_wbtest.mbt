// White-box tests for chunk store.

///|
test "MemoryChunkStore::new creates empty store" {
  let store = MemoryChunkStore::new()
  assert_eq(store.size(), 0)
}

///|
test "MemoryChunkStore::put and get" {
  let store = MemoryChunkStore::new()
  let hash = @types.ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let spec_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )
  store.put(chunk)
  assert_eq(store.size(), 1)
  let retrieved = store.get(hash)
  assert_true(retrieved is Some(_))
  assert_eq(retrieved.unwrap().module_id, "src/main.ts")
}

///|
test "MemoryChunkStore::has" {
  let store = MemoryChunkStore::new()
  let hash = @types.ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let spec_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )
  assert_false(store.has(hash))
  store.put(chunk)
  assert_true(store.has(hash))
}

///|
test "MemoryChunkStore::delete" {
  let store = MemoryChunkStore::new()
  let hash = @types.ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let spec_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )
  store.put(chunk)
  assert_true(store.has(hash))
  let deleted = store.delete(hash)
  assert_true(deleted)
  assert_false(store.has(hash))
  // Delete non-existent returns false
  let deleted_again = store.delete(hash)
  assert_false(deleted_again)
}

///|
test "MemoryChunkStore::list" {
  let store = MemoryChunkStore::new()
  let hash1 = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let hash2 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let source_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let spec_hash = @types.ContentHash::from_string(
    "9876dcba9876dcba9876dcba9876dcba",
  )
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let mod2 = helper.get_or_add_module("src/b.ts", file=Some("src/b.ts"))
  let chunk1 = @types.ModuleChunk::new(
    hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  let chunk2 = @types.ModuleChunk::new(
    hash2, "src/b.ts", mod2, source_hash, spec_hash,
  )
  store.put(chunk1)
  store.put(chunk2)
  let hashes = store.list()
  assert_eq(hashes.length(), 2)
}

///|
test "MemoryChunkStore::clear" {
  let store = MemoryChunkStore::new()
  let hash = @types.ContentHash::from_string("abcd1234abcd1234abcd1234abcd1234")
  let source_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let spec_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let helper = @graph.CodeGraph::new()
  let mod_node = helper.get_or_add_module(
    "src/main.ts",
    file=Some("src/main.ts"),
  )
  let chunk = @types.ModuleChunk::new(
    hash, "src/main.ts", mod_node, source_hash, spec_hash,
  )
  store.put(chunk)
  assert_eq(store.size(), 1)
  store.clear()
  assert_eq(store.size(), 0)
}

///|
test "MemoryChunkStore::find_orphans" {
  let store = MemoryChunkStore::new()
  let hash1 = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let hash2 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let source_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let spec_hash = @types.ContentHash::from_string(
    "9876dcba9876dcba9876dcba9876dcba",
  )
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let mod2 = helper.get_or_add_module("src/b.ts", file=Some("src/b.ts"))
  let chunk1 = @types.ModuleChunk::new(
    hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  let chunk2 = @types.ModuleChunk::new(
    hash2, "src/b.ts", mod2, source_hash, spec_hash,
  )
  store.put(chunk1)
  store.put(chunk2)

  // Only hash1 is referenced
  let referenced = [hash1]
  let orphans = store.find_orphans(referenced)
  assert_eq(orphans.length(), 1)
  assert_eq(orphans[0], hash2)
}

///|
test "MemoryChunkStore::clean_orphans" {
  let store = MemoryChunkStore::new()
  let hash1 = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let hash2 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let source_hash = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let spec_hash = @types.ContentHash::from_string(
    "9876dcba9876dcba9876dcba9876dcba",
  )
  let helper = @graph.CodeGraph::new()
  let mod1 = helper.get_or_add_module("src/a.ts", file=Some("src/a.ts"))
  let mod2 = helper.get_or_add_module("src/b.ts", file=Some("src/b.ts"))
  let chunk1 = @types.ModuleChunk::new(
    hash1, "src/a.ts", mod1, source_hash, spec_hash,
  )
  let chunk2 = @types.ModuleChunk::new(
    hash2, "src/b.ts", mod2, source_hash, spec_hash,
  )
  store.put(chunk1)
  store.put(chunk2)
  assert_eq(store.size(), 2)

  // Only hash1 is referenced
  let referenced = [hash1]
  let deleted_count = store.clean_orphans(referenced)
  assert_eq(deleted_count, 1)
  assert_eq(store.size(), 1)
  assert_true(store.has(hash1))
  assert_false(store.has(hash2))
}
