///|
/// Converts a module identifier to a filesystem path according to the style.
/// - Dot style: "a.b.c" -> "a/b/c"
/// - ColonColon style: "a::b::c" -> "a/b/c"
/// - Slash style: "a/b/c" -> "a/b/c" (no change)
pub fn module_to_path(
  mod_str : String,
  style : @types.ModulePathStyle,
) -> String {
  match style {
    Dot => replace_all(mod_str, ".", "/")
    ColonColon => replace_all(mod_str, "::", "/")
    Slash => mod_str
  }
}

///|
/// Replaces all occurrences of a substring with another substring.
fn replace_all(s : String, pattern : String, replacement : String) -> String {
  if pattern.length() == 0 || s.length() == 0 {
    return s
  }
  let result = StringBuilder::new()
  let chars = s.to_array()
  let pattern_chars = pattern.to_array()
  let mut i = 0
  while i < chars.length() {
    if starts_with_at_arr(chars, pattern_chars, i) {
      result.write_string(replacement)
      i = i + pattern_chars.length()
    } else {
      result.write_char(chars[i])
      i = i + 1
    }
  }
  result.to_string()
}

///|
/// Checks if a char array starts with a pattern at a given position.
fn starts_with_at_arr(
  s : Array[Char],
  pattern : Array[Char],
  pos : Int,
) -> Bool {
  if pos + pattern.length() > s.length() {
    return false
  }
  for i = 0; i < pattern.length(); i = i + 1 {
    if s[pos + i] != pattern[i] {
      return false
    }
  }
  true
}
