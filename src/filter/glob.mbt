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
      let suffix = @parser.substr_from(path, i)
      if glob_match(suffix, pattern) || glob_match(suffix, pattern + "/**") {
        return true
      }
    }
  }
  false
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
      let suffix = @parser.substr_from(path, i)
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
    @parser.substr(path, prev_slash + 1, last_slash)
  } else {
    @parser.substr_from(path, last_slash + 1)
  }
}

///|
/// Check if a path contains glob pattern characters.
pub fn has_glob_pattern(path : String) -> Bool {
  let chars = path.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '*' || c == '?' || c == '[' {
      return true
    }
  }
  false
}

///|
/// Expand a glob pattern into matching file paths.
/// Returns array of matching paths.
pub fn expand_glob(pattern : String) -> Array[String] {
  let results : Array[String] = []
  if not(has_glob_pattern(pattern)) {
    // No glob characters, return as-is if exists
    results.push(pattern)
    return results
  }
  // Find the base directory (longest prefix without glob)
  let (base_dir, glob_part) = split_glob_pattern(pattern)
  // Walk from base directory and match
  expand_glob_impl(base_dir, glob_part, pattern, results)
  results
}

///|
/// Split pattern into base directory and glob part.
fn split_glob_pattern(pattern : String) -> (String, String) {
  let chars = pattern.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == '*' || c == '?' || c == '[' {
      break
    }
    if c == '/' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    (".", pattern)
  } else if last_slash == 0 {
    ("/", @parser.substr_from(pattern, 1))
  } else {
    (
      @parser.substr(pattern, 0, last_slash),
      @parser.substr_from(pattern, last_slash + 1),
    )
  }
}

///|
/// Recursively expand glob pattern.
fn expand_glob_impl(
  dir : String,
  remaining : String,
  full_pattern : String,
  results : Array[String],
) -> Unit {
  try {
    if not(@fs.is_dir(dir)) {
      return
    }
    let entries = @fs.read_dir(dir)
    for entry in entries {
      // Skip hidden files/dirs unless pattern starts with .
      if entry.has_prefix(".") && not(remaining.has_prefix(".")) {
        continue
      }
      let full_path = if dir == "." { entry } else { dir + "/" + entry }
      // Check if full path matches the original pattern
      if glob_match(full_path, full_pattern) {
        results.push(full_path)
      }
      // Recurse into directories if pattern has **
      if @fs.is_dir(full_path) && remaining.has_prefix("**") {
        expand_glob_impl(full_path, remaining, full_pattern, results)
      } else if @fs.is_dir(full_path) {
        // Recurse if pattern continues beyond this segment
        let next_remaining = skip_first_segment(remaining)
        if next_remaining.length() > 0 {
          expand_glob_impl(full_path, next_remaining, full_pattern, results)
        }
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Skip first path segment in pattern.
fn skip_first_segment(pattern : String) -> String {
  let chars = pattern.to_array()
  let mut i = 0
  // Skip ** or first segment
  if chars.length() >= 2 && chars[0] == '*' && chars[1] == '*' {
    i = 2
    if i < chars.length() && chars[i] == '/' {
      i += 1
    }
  } else {
    while i < chars.length() && chars[i] != '/' {
      i += 1
    }
    if i < chars.length() && chars[i] == '/' {
      i += 1
    }
  }
  @parser.substr_from(pattern, i)
}
