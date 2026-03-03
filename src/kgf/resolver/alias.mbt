///|
/// Applies alias rewrites to a module path.
/// Aliases are applied in order. Each alias pattern is a simple string match.
/// For complex regex patterns, only simple prefix matching is supported.
pub fn apply_aliases(
  module_path : String,
  aliases : Array[@types.ResolverAlias],
) -> String {
  let mut result = module_path
  for a in aliases {
    let pattern = a.get_pattern()
    let replacement = a.get_replace()
    result = apply_single_alias(result, pattern, replacement)
  }
  result
}

///|
/// Applies a single alias pattern to a module path.
/// Supports simple prefix patterns and string replacement.
fn apply_single_alias(
  input : String,
  pattern : String,
  replacement : String,
) -> String {
  // Handle simple prefix patterns (e.g., "^@/" -> "src/")
  let pattern_chars = pattern.to_array()
  if pattern_chars.length() > 0 && pattern_chars[0] == '^' {
    let prefix = substring_from(pattern, 1)
    if input.has_prefix(prefix) {
      return replacement + substring_from(input, prefix.length())
    }
    return input
  }
  // Handle exact match or substring replacement
  replace_first(input, pattern, replacement)
}

///|
/// Returns substring from start position to end of string.
fn substring_from(s : String, start : Int) -> String {
  if start >= s.length() {
    return ""
  }
  let chars = s.to_array()
  let result = StringBuilder::new()
  for i = start; i < chars.length(); i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Returns substring from start to end position (exclusive).
fn substring_range(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  let actual_start = if start < 0 { 0 } else { start }
  if actual_start >= actual_end {
    return ""
  }
  let result = StringBuilder::new()
  for i = actual_start; i < actual_end; i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Replaces the first occurrence of a pattern with a replacement.
fn replace_first(s : String, pattern : String, replacement : String) -> String {
  if pattern.length() == 0 || s.length() == 0 {
    return s
  }
  let pos = find_substring(s, pattern)
  if pos < 0 {
    return s
  }
  let before = substring_range(s, 0, pos)
  let after = substring_from(s, pos + pattern.length())
  before + replacement + after
}

///|
/// Finds the position of a substring in a string.
/// Returns -1 if not found.
fn find_substring(s : String, pattern : String) -> Int {
  if pattern.length() == 0 {
    return 0
  }
  if pattern.length() > s.length() {
    return -1
  }
  let s_chars = s.to_array()
  let pattern_chars = pattern.to_array()
  for i = 0; i <= s_chars.length() - pattern_chars.length(); i = i + 1 {
    let mut match_found = true
    for j = 0; j < pattern_chars.length(); j = j + 1 {
      if s_chars[i + j] != pattern_chars[j] {
        match_found = false
        break
      }
    }
    if match_found {
      return i
    }
  }
  -1
}
