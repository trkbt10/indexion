// White-box tests for manifest management.

///|
test "create_manifest" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let manifest = create_manifest(spec_hash)
  assert_eq(manifest.spec_hash, spec_hash)
  assert_eq(manifest.modules.length(), 0)
}

///|
test "update_manifest" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_eq(updated.modules.length(), 1)
  assert_true(updated.modules.contains("src/main.ts"))
  assert_eq(updated.modules.get("src/main.ts").unwrap(), chunk_hash)
}

///|
test "remove_module" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_eq(updated.modules.length(), 1)
  let removed = remove_module(updated, "src/main.ts")
  assert_eq(removed.modules.length(), 0)
}

///|
test "has_module" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  assert_false(has_module(manifest, "src/main.ts"))
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_true(has_module(updated, "src/main.ts"))
}

///|
test "get_chunk_hash" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  let retrieved = get_chunk_hash(updated, "src/main.ts")
  assert_true(retrieved is Some(_))
  assert_eq(retrieved.unwrap(), chunk_hash)
  let missing = get_chunk_hash(updated, "src/other.ts")
  assert_true(missing is None)
}

///|
test "get_module_ids" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let manifest = create_manifest(spec_hash)
  let updated1 = update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = update_manifest(updated1, "src/b.ts", chunk_hash2)
  let ids = get_module_ids(updated2)
  assert_eq(ids.length(), 2)
}

///|
test "get_chunk_hashes" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let manifest = create_manifest(spec_hash)
  let updated1 = update_manifest(manifest, "src/a.ts", chunk_hash1)
  let updated2 = update_manifest(updated1, "src/b.ts", chunk_hash2)
  let hashes = get_chunk_hashes(updated2)
  assert_eq(hashes.length(), 2)
}

///|
test "module_count" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  assert_eq(module_count(manifest), 0)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_eq(module_count(updated), 1)
}

///|
test "is_empty" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  assert_true(is_empty(manifest))
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_false(is_empty(updated))
}

///|
test "spec_matches" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let other_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  assert_true(spec_matches(manifest, spec_hash))
  assert_false(spec_matches(manifest, other_hash))
}

///|
test "update_spec_hash clears modules" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let new_spec_hash = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let chunk_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let manifest = create_manifest(spec_hash)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)
  assert_eq(module_count(updated), 1)
  let new_manifest = update_spec_hash(updated, new_spec_hash)
  assert_eq(new_manifest.spec_hash, new_spec_hash)
  assert_eq(module_count(new_manifest), 0)
}

///|
test "merge manifests" {
  let spec_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let chunk_hash1 = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let chunk_hash2 = @types.ContentHash::from_string(
    "5678efgh5678efgh5678efgh5678efgh",
  )
  let chunk_hash3 = @types.ContentHash::from_string(
    "99998888777766665555444433332222",
  )
  let manifest1 = create_manifest(spec_hash)
  let m1_updated = update_manifest(manifest1, "src/a.ts", chunk_hash1)
  let manifest2 = create_manifest(spec_hash)
  let m2_updated1 = update_manifest(manifest2, "src/a.ts", chunk_hash2) // Override
  let m2_updated2 = update_manifest(m2_updated1, "src/b.ts", chunk_hash3)
  let merged = merge(m1_updated, m2_updated2)
  assert_eq(module_count(merged), 2)
  // src/a.ts should be overridden by manifest2
  assert_eq(get_chunk_hash(merged, "src/a.ts").unwrap(), chunk_hash2)
  assert_eq(get_chunk_hash(merged, "src/b.ts").unwrap(), chunk_hash3)
}

///|
test "is_chunk_valid" {
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
  store.put(chunk)
  let manifest = create_manifest(spec_hash)
  let updated = update_manifest(manifest, "src/main.ts", chunk_hash)

  // Valid: same source hash
  assert_true(is_chunk_valid(updated, store, "src/main.ts", source_hash))

  // Invalid: different source hash
  let different_source = @types.ContentHash::from_string(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_false(is_chunk_valid(updated, store, "src/main.ts", different_source))

  // Invalid: module not in manifest
  assert_false(is_chunk_valid(updated, store, "src/other.ts", source_hash))
}
