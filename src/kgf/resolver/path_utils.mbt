///|
/// Joins path parts into a single path string.
/// Parts are joined with "/" separator. Empty parts are filtered out.
pub fn join_path(parts : Array[String]) -> String {
  let result : Array[String] = []
  for part in parts {
    if part.length() > 0 {
      result.push(part)
    }
  }
  if result.length() == 0 {
    return ""
  }
  let mut path = result[0]
  for i = 1; i < result.length(); i = i + 1 {
    let part = result[i]
    if path.length() > 0 && not(path.has_suffix("/")) {
      path = path + "/"
    }
    path = path + part
  }
  normalize_path(path)
}

///|
/// Returns the directory name of a path.
/// For example, dirname("/a/b/c.txt") returns "/a/b"
pub fn dirname(path : String) -> String {
  if path.length() == 0 {
    return "."
  }
  let normalized = normalize_path(path)
  let last_slash = find_last_char(normalized, '/')
  if last_slash < 0 {
    return "."
  }
  if last_slash == 0 {
    return "/"
  }
  substr(normalized, 0, last_slash)
}

///|
/// Returns the base name of a path.
/// For example, basename("/a/b/c.txt") returns "c.txt"
pub fn basename(path : String) -> String {
  if path.length() == 0 {
    return ""
  }
  let normalized = normalize_path(path)
  let last_slash = find_last_char(normalized, '/')
  if last_slash < 0 {
    return normalized
  }
  substr_from(normalized, last_slash + 1)
}

///|
/// Normalizes a path by removing redundant slashes and resolving . and ..
pub fn normalize_path(path : String) -> String {
  if path.length() == 0 {
    return ""
  }
  let path_chars = path.to_array()
  let is_abs = path_chars[0] == '/'
  let parts = split_string(path, '/')
  let stack : Array[String] = []
  for part in parts {
    if part == "." || part == "" {
      continue
    } else if part == ".." {
      if stack.length() > 0 && stack[stack.length() - 1] != ".." {
        let _ = stack.pop()
      } else if not(is_abs) {
        stack.push("..")
      }
    } else {
      stack.push(part)
    }
  }
  if stack.length() == 0 {
    if is_abs {
      return "/"
    }
    return "."
  }
  let result = join_array_strings(stack, "/")
  if is_abs {
    "/" + result
  } else {
    result
  }
}

///|
/// Computes the relative path from one path to another.
/// Both paths should be absolute or both relative.
pub fn relative_path(from : String, to : String) -> String {
  let from_normalized = normalize_path(from)
  let to_normalized = normalize_path(to)
  if from_normalized == to_normalized {
    return "."
  }
  let from_parts = split_string(from_normalized, '/')
  let to_parts = split_string(to_normalized, '/')
  // Filter empty parts
  let from_filtered : Array[String] = []
  for part in from_parts {
    if part.length() > 0 {
      from_filtered.push(part)
    }
  }
  let to_filtered : Array[String] = []
  for part in to_parts {
    if part.length() > 0 {
      to_filtered.push(part)
    }
  }
  // Find common prefix length
  let mut common = 0
  let min_len = if from_filtered.length() < to_filtered.length() {
    from_filtered.length()
  } else {
    to_filtered.length()
  }
  while common < min_len && from_filtered[common] == to_filtered[common] {
    common = common + 1
  }
  // Build relative path
  let result : Array[String] = []
  // Add .. for each remaining part in from
  for j = common; j < from_filtered.length(); j = j + 1 {
    result.push("..")
  }
  // Add remaining parts from to
  for i = common; i < to_filtered.length(); i = i + 1 {
    result.push(to_filtered[i])
  }
  if result.length() == 0 {
    return "."
  }
  join_array_strings(result, "/")
}

///|
/// Checks if a path is absolute (starts with /).
pub fn is_absolute(path : String) -> Bool {
  let chars = path.to_array()
  chars.length() > 0 && chars[0] == '/'
}

///|
/// Finds the last occurrence of a character in a string.
/// Returns -1 if not found.
fn find_last_char(s : String, c : Char) -> Int {
  let chars = s.to_array()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    if chars[i] == c {
      return i
    }
  }
  -1
}

///|
/// Returns substring from start to end position (exclusive).
fn substr(s : String, start : Int, end : Int) -> String {
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
/// Returns substring from start position to end of string.
fn substr_from(s : String, start : Int) -> String {
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
/// Splits a string by a delimiter character.
fn split_string(s : String, delim : Char) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for c in s {
    if c == delim {
      result.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  result.push(current.to_string())
  result
}

///|
/// Joins an array of strings with a separator.
fn join_array_strings(arr : Array[String], sep : String) -> String {
  if arr.length() == 0 {
    return ""
  }
  let result = StringBuilder::new()
  result.write_string(arr[0])
  for i = 1; i < arr.length(); i = i + 1 {
    result.write_string(sep)
    result.write_string(arr[i])
  }
  result.to_string()
}
