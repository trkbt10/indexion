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
  let path_chars = path.to_array()
  for i = 0; i <= path_chars.length(); i = i + 1 {
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
  if pi >= pattern.length() {
    return si >= path.length()
  }
  let pc = pattern[pi]
  if pc == '*' && pi + 1 < pattern.length() && pattern[pi + 1] == '*' {
    let next_pi = if pi + 2 < pattern.length() && pattern[pi + 2] == '/' {
      pi + 3
    } else {
      pi + 2
    }
    for i = si; i <= path.length(); i = i + 1 {
      if glob_match_impl(pattern, next_pi, path, i) {
        return true
      }
    }
    return false
  }
  if pc == '*' {
    for i = si; i <= path.length(); i = i + 1 {
      if i > si && i - 1 < path.length() && path[i - 1] == '/' {
        break
      }
      if glob_match_impl(pattern, pi + 1, path, i) {
        return true
      }
    }
    return false
  }
  if pc == '?' {
    if si < path.length() && path[si] != '/' {
      return glob_match_impl(pattern, pi + 1, path, si + 1)
    }
    return false
  }
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
  if si < path.length() && path[si] == pc {
    return glob_match_impl(pattern, pi + 1, path, si + 1)
  }
  false
}

///|
fn match_char_class(
  pattern : Array[Char],
  start : Int,
  c : Char,
) -> (Bool, Int) {
  let mut i = start
  let mut negated = false
  let mut matched = false
  if i < pattern.length() && (pattern[i] == '!' || pattern[i] == '^') {
    negated = true
    i = i + 1
  }
  while i < pattern.length() && pattern[i] != ']' {
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
pub fn expand_glob(pattern : String) -> Array[String] {
  let results : Array[String] = []
  if not(has_glob_pattern(pattern)) {
    results.push(pattern)
    return results
  }
  let (base_dir, glob_part) = split_glob_pattern(pattern)
  expand_glob_impl(base_dir, glob_part, pattern, results)
  results
}

///|
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
      if entry.has_prefix(".") && not(remaining.has_prefix(".")) {
        continue
      }
      let full_path = if dir == "." { entry } else { dir + "/" + entry }
      if glob_match(full_path, full_pattern) {
        results.push(full_path)
      }
      if @fs.is_dir(full_path) && remaining.has_prefix("**") {
        expand_glob_impl(full_path, remaining, full_pattern, results)
      } else if @fs.is_dir(full_path) {
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
fn skip_first_segment(pattern : String) -> String {
  let chars = pattern.to_array()
  let mut i = 0
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
