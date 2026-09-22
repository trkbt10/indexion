///|
/// Converts a module identifier to a filesystem path according to the style.
/// - Dot style: "a.b.c" -> "a/b/c"
/// - ColonColon style: "a::b::c" -> "a/b/c"
/// - Backslash style: "a\b\c" -> "a/b/c"
/// - Slash style: "a/b/c" -> "a/b/c" (no change)
///
/// A leading run of the spec's `relative_prefixes` (e.g. "./", "../") is the
/// resolver's own navigation syntax, not part of the module identifier, so it
/// is kept verbatim and only the remainder is converted: with dot style,
/// "../a.b" -> "../a/b". Converting the prefix too would turn "../" into
/// "///" and silently drop the parent step.
pub fn module_to_path(
  mod_str : String,
  style : @types.ModulePathStyle,
  relative_prefixes? : Array[String] = [],
) -> String {
  let prefix_len = leading_prefix_run_length(mod_str, relative_prefixes)
  let prefix = mod_str[0:prefix_len].to_owned()
  let rest = mod_str[prefix_len:].to_owned()
  let converted = match style {
    Dot => replace_all(rest, ".", "/")
    ColonColon => replace_all(rest, "::", "/")
    Backslash => replace_all(rest, "\\", "/")
    Slash => rest
  }
  prefix + converted
}

///|
/// Length of the leading run of declared prefixes in `path`: at each step the
/// longest declared prefix that matches is consumed, until none matches.
fn leading_prefix_run_length(path : String, prefixes : Array[String]) -> Int {
  let chars = path.to_array()
  let mut pos = 0
  while pos < chars.length() {
    let mut best = 0
    for prefix in prefixes {
      let prefix_chars = prefix.to_array()
      if prefix_chars.length() > best &&
        starts_with_at_arr(chars, prefix_chars, pos) {
        best = prefix_chars.length()
      }
    }
    if best == 0 {
      break
    }
    pos = pos + best
  }
  pos
}

///|
/// Replaces all occurrences of a substring with another substring.
fn replace_all(s : String, pattern : String, replacement : String) -> String {
  if pattern.length() == 0 || s.length() == 0 {
    return s
  }
  let result = StringBuilder()
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
