///|
/// Simple glob pattern matching.
/// Supports:
/// - * matches any sequence of characters (except /)
/// - ** matches any sequence including /
/// - ? matches single character
/// - [abc] matches any character in set
/// - [!abc] matches any character not in set
/// - [a-z] matches character range
pub fn glob_match(path : String, pattern : String) -> Bool {
  glob_match_impl(pattern.to_array(), 0, path.to_array(), 0)
}

///|
/// Match pattern anywhere in the path (useful for unanchored patterns).
pub fn glob_match_anywhere(path : String, pattern : String) -> Bool {
  // Try matching at every position
  let path_chars = path.to_array()
  for i = 0; i <= path_chars.length(); i = i + 1 {
    // Only try at start or after /
    if i == 0 || (i > 0 && path_chars[i - 1] == '/') {
      let suffix = substring_from_glob(path, i)
      if glob_match(suffix, pattern) || glob_match(suffix, pattern + "/**") {
        return true
      }
    }
  }
  false
}

///|
fn substring_from_glob(s : String, start : Int) -> String {
  let chars = s.to_array()
  if start >= chars.length() {
    return ""
  }
  let buf : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    buf.push(chars[i])
  }
  String::from_array(buf)
}

///|
fn glob_match_impl(
  pattern : Array[Char],
  pi : Int,
  path : Array[Char],
  si : Int,
) -> Bool {
  // End of pattern
  if pi >= pattern.length() {
    return si >= path.length()
  }
  let pc = pattern[pi]
  // ** matches any path segment(s)
  if pc == '*' && pi + 1 < pattern.length() && pattern[pi + 1] == '*' {
    // Skip **
    let next_pi = if pi + 2 < pattern.length() && pattern[pi + 2] == '/' {
      pi + 3 // Skip **/
    } else {
      pi + 2 // Skip **
    }
    // Try matching ** with 0 or more path segments
    for i = si; i <= path.length(); i = i + 1 {
      if glob_match_impl(pattern, next_pi, path, i) {
        return true
      }
    }
    return false
  }
  // * matches any sequence except /
  if pc == '*' {
    // Try matching * with 0 or more characters (except /)
    for i = si; i <= path.length(); i = i + 1 {
      if i > si && i - 1 < path.length() && path[i - 1] == '/' {
        // Can't match across /
        break
      }
      if glob_match_impl(pattern, pi + 1, path, i) {
        return true
      }
    }
    return false
  }
  // ? matches single character (except /)
  if pc == '?' {
    if si < path.length() && path[si] != '/' {
      return glob_match_impl(pattern, pi + 1, path, si + 1)
    }
    return false
  }
  // Character class [abc], [!abc], [a-z]
  if pc == '[' {
    if si >= path.length() {
      return false
    }
    let sc = path[si]
    let (matched, next_pi) = match_char_class(pattern, pi + 1, sc)
    if matched {
      return glob_match_impl(pattern, next_pi, path, si + 1)
    }
    return false
  }
  // Literal match
  if si < path.length() && path[si] == pc {
    return glob_match_impl(pattern, pi + 1, path, si + 1)
  }
  false
}

///|
/// Match a character class pattern and return (matched, next_pattern_index).
fn match_char_class(
  pattern : Array[Char],
  start : Int,
  c : Char,
) -> (Bool, Int) {
  let mut i = start
  let mut negated = false
  let mut matched = false
  // Check for negation
  if i < pattern.length() && (pattern[i] == '!' || pattern[i] == '^') {
    negated = true
    i = i + 1
  }
  // Scan until ]
  while i < pattern.length() && pattern[i] != ']' {
    // Check for range a-z
    if i + 2 < pattern.length() &&
      pattern[i + 1] == '-' &&
      pattern[i + 2] != ']' {
      let lo = pattern[i]
      let hi = pattern[i + 2]
      if c >= lo && c <= hi {
        matched = true
      }
      i = i + 3
    } else {
      if pattern[i] == c {
        matched = true
      }
      i = i + 1
    }
  }
  // Skip closing ]
  if i < pattern.length() && pattern[i] == ']' {
    i = i + 1
  }
  if negated {
    (not(matched), i)
  } else {
    (matched, i)
  }
}

///|
/// Check if path matches a pattern, handling directory-only patterns.
pub fn pattern_matches(
  pattern : IgnorePattern,
  path : String,
  is_dir : Bool,
) -> Bool {
  let p = pattern.pattern
  // For directory-only patterns, check if path is inside the directory
  if pattern.directory_only {
    // If path is the directory itself
    if is_dir {
      if pattern.anchored {
        return glob_match(path, p)
      }
      let basename = get_basename(path)
      if glob_match(basename, p) {
        return true
      }
      return glob_match_anywhere(path, p)
    }
    // If path is a file, check if it's inside an excluded directory
    // e.g., "node_modules/foo.js" should match pattern "node_modules"
    if pattern.anchored {
      return glob_match(path, p + "/**")
    }
    // Check if any path component matches the pattern
    return path_starts_with_pattern(path, p)
  }
  // Non-directory patterns
  if pattern.anchored {
    return glob_match(path, p)
  }
  // Unanchored patterns match anywhere
  let basename = get_basename(path)
  if glob_match(basename, p) {
    return true
  }
  // Also try matching against full path
  glob_match_anywhere(path, p)
}

///|
/// Check if a path starts with a pattern (for directory matching).
/// e.g., "node_modules/foo.js" starts with "node_modules"
fn path_starts_with_pattern(path : String, pattern : String) -> Bool {
  let path_chars = path.to_array()
  // Check at start and after each /
  for i = 0; i <= path_chars.length(); i = i + 1 {
    if i == 0 || (i > 0 && path_chars[i - 1] == '/') {
      let suffix = substring_from_glob(path, i)
      // Check if suffix starts with pattern followed by /
      if glob_match(suffix, pattern + "/**") ||
        glob_match(suffix, pattern + "/*") {
        return true
      }
    }
  }
  false
}

///|
/// Get basename of a path.
fn get_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    return path
  }
  if last_slash + 1 >= chars.length() {
    // Path ends with /, get second-to-last component
    let mut prev_slash = -1
    for i = 0; i < last_slash; i = i + 1 {
      if chars[i] == '/' {
        prev_slash = i
      }
    }
    substring_range(path, prev_slash + 1, last_slash)
  } else {
    substring_after(path, last_slash + 1)
  }
}

///|
fn substring_after(s : String, start : Int) -> String {
  let chars = s.to_array()
  if start >= chars.length() {
    return ""
  }
  let buf : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    buf.push(chars[i])
  }
  String::from_array(buf)
}

///|
fn substring_range(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  if start >= chars.length() || start >= end {
    return ""
  }
  let buf : Array[Char] = []
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.push(chars[i])
  }
  String::from_array(buf)
}
