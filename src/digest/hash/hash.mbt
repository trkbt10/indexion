// Function-level hashing for digest module.
// Reuses CAS hash infrastructure for consistency.

///|
/// Compute hash of function source content.
/// Used for detecting changes to function body.
pub fn compute_source_hash(source_content : String) -> @types.FunctionHash {
  let content_hash = @cas_hash.compute_hash(source_content)
  @types.FunctionHash::from_string(content_hash.to_string())
}

///|
/// Compute context hash that includes call relationships.
/// This hash changes when:
/// - Function source changes
/// - List of callers changes
/// - List of callees changes
pub fn compute_context_hash(
  source_hash : @types.FunctionHash,
  callers : Array[String],
  callees : Array[String],
) -> @types.FunctionHash {
  // Sort for deterministic hashing
  let sorted_callers = callers.copy()
  sorted_callers.sort()
  let sorted_callees = callees.copy()
  sorted_callees.sort()
  // Combine into single string for hashing
  let parts : Array[String] = []
  parts.push("src:")
  parts.push(source_hash.to_string())
  parts.push("\u0000callers:")
  for caller in sorted_callers {
    parts.push(caller)
    parts.push(",")
  }
  parts.push("\u0000callees:")
  for callee in sorted_callees {
    parts.push(callee)
    parts.push(",")
  }
  let combined = parts.join("")
  let content_hash = @cas_hash.compute_hash(combined)
  @types.FunctionHash::from_string(content_hash.to_string())
}

///|
/// Compute hash from impression content.
/// Used to detect when impression needs regeneration.
pub fn compute_impression_hash(
  impression : @types.Impression,
) -> @types.FunctionHash {
  let text = impression.to_text()
  let content_hash = @cas_hash.compute_hash(text)
  @types.FunctionHash::from_string(content_hash.to_string())
}

///|
/// Combine multiple hashes into one (for manifest or batch operations).
pub fn combine_hashes(
  hashes : Array[@types.FunctionHash],
) -> @types.FunctionHash {
  let parts : Array[String] = []
  for hash in hashes {
    parts.push(hash.to_string())
    parts.push("\u0000")
  }
  let combined = parts.join("")
  let content_hash = @cas_hash.compute_hash(combined)
  @types.FunctionHash::from_string(content_hash.to_string())
}

///|
/// Convert FunctionHash to ContentHash (for CAS compatibility).
pub fn to_content_hash(hash : @types.FunctionHash) -> @cas_types.ContentHash {
  @cas_types.ContentHash::from_string(hash.to_string())
}

///|
/// Convert ContentHash to FunctionHash.
pub fn from_content_hash(hash : @cas_types.ContentHash) -> @types.FunctionHash {
  @types.FunctionHash::from_string(hash.to_string())
}

///|
/// Validate that a string looks like a valid FunctionHash.
pub fn is_valid_hash(hash : String) -> Bool {
  @cas_hash.is_valid_hash(hash)
}
