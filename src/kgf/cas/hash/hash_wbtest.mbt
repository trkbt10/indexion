// White-box tests for SHA-256 hashing utilities.

///|
test "compute_hash produces 32-character hex string" {
  let hash = compute_hash("hello world")
  assert_eq(hash.to_string().length(), 32)
}

///|
test "compute_hash is deterministic" {
  let hash1 = compute_hash("test content")
  let hash2 = compute_hash("test content")
  assert_eq(hash1, hash2)
}

///|
test "compute_hash produces different hashes for different content" {
  let hash1 = compute_hash("content A")
  let hash2 = compute_hash("content B")
  assert_true(hash1 != hash2)
}

///|
test "compute_chunk_hash combines module_id, source_hash, spec_hash" {
  let source_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let spec_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let hash1 = compute_chunk_hash("src/main.ts", source_hash, spec_hash)
  let hash2 = compute_chunk_hash("src/other.ts", source_hash, spec_hash)
  assert_true(hash1 != hash2)
}

///|
test "compute_chunk_hash is deterministic" {
  let source_hash = @types.ContentHash::from_string(
    "abcd1234abcd1234abcd1234abcd1234",
  )
  let spec_hash = @types.ContentHash::from_string(
    "1234abcd1234abcd1234abcd1234abcd",
  )
  let hash1 = compute_chunk_hash("src/main.ts", source_hash, spec_hash)
  let hash2 = compute_chunk_hash("src/main.ts", source_hash, spec_hash)
  assert_eq(hash1, hash2)
}

///|
test "compute_spec_hash" {
  let hash = compute_spec_hash("kgf spec content")
  assert_eq(hash.to_string().length(), 32)
}

///|
test "is_valid_hash accepts valid hashes" {
  assert_true(is_valid_hash("abcd1234abcd1234abcd1234abcd1234"))
  assert_true(is_valid_hash("0123456789abcdef0123456789abcdef"))
  assert_true(is_valid_hash("ABCDEF01ABCDEF01ABCDEF01ABCDEF01"))
}

///|
test "is_valid_hash rejects invalid hashes" {
  // Too short
  assert_false(is_valid_hash("abcd1234"))
  // Too long
  assert_false(is_valid_hash("abcd1234abcd1234abcd1234abcd1234abcd1234"))
  // Invalid characters
  assert_false(is_valid_hash("ghij1234ghij1234ghij1234ghij1234"))
  // Empty
  assert_false(is_valid_hash(""))
}

///|
test "as_content_hash validates and returns hash" {
  let valid = as_content_hash("abcd1234abcd1234abcd1234abcd1234")
  assert_true(valid is Some(_))
  let invalid = as_content_hash("invalid")
  assert_true(invalid is None)
}

///|
test "hash produces hex characters only" {
  let hash = compute_hash("test string")
  let hash_str = hash.to_string()
  for i = 0; i < hash_str.length(); i = i + 1 {
    let c = hash_str[i].to_int().unsafe_to_char()
    let valid = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    assert_true(valid)
  }
}

///|
test "empty string produces valid hash" {
  let hash = compute_hash("")
  assert_eq(hash.to_string().length(), 32)
  assert_true(is_valid_hash(hash.to_string()))
}

///|
test "hash is content-dependent" {
  let hash1 = compute_hash("abc")
  let hash2 = compute_hash("abd")
  assert_true(hash1 != hash2)
  // Different length strings
  let hash3 = compute_hash("a")
  let hash4 = compute_hash("abcd")
  assert_true(hash3 != hash4)
}
