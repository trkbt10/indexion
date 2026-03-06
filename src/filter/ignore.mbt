///|
/// Standard ignore file name (git standard).
pub const GITIGNORE_FILENAME : String = ".gitignore"

///|
/// Project-specific ignore file name.
pub const INDEXIONIGNORE_FILENAME : String = ".indexionignore"

///|
/// Parse an ignore file content (gitignore syntax).
pub fn parse_ignore_file(
  content : String,
  source : String,
) -> Array[IgnorePattern] {
  let patterns : Array[IgnorePattern] = []
  let lines = split_lines(content)
  for line in lines {
    let trimmed = trim_string(line)
    // Skip empty lines and comments
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      continue
    }
    let pattern = parse_ignore_line(trimmed, source)
    patterns.push(pattern)
  }
  patterns
}

///|
/// Parse a single ignore pattern line.
fn parse_ignore_line(line : String, source : String) -> IgnorePattern {
  let mut s = line
  let mut negated = false
  let mut directory_only = false
  let mut anchored = false
  // Check for negation prefix
  if s.has_prefix("!") {
    negated = true
    s = substring_after_ignore(s, 1)
  }
  // Check for directory-only suffix
  if s.has_suffix("/") {
    directory_only = true
    s = substring_until(s, s.to_array().length() - 1)
  }
  // Check if pattern is anchored (starts with / or contains /)
  if s.has_prefix("/") {
    anchored = true
    s = substring_after_ignore(s, 1)
  } else if contains_slash(s) {
    anchored = true
  }
  IgnorePattern::new(s, negated~, directory_only~, anchored~, source~)
}

///|
/// Check if string contains a slash (but not just at the end).
fn contains_slash(s : String) -> Bool {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      return true
    }
  }
  false
}

///|
/// Load gitignore from a directory.
pub fn load_gitignore(dir : String) -> Array[IgnorePattern] {
  let path = dir + "/" + GITIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(path)
    parse_ignore_file(content, path)
  } catch {
    _ => []
  }
}

///|
/// Load indexionignore from a directory.
pub fn load_indexionignore(dir : String) -> Array[IgnorePattern] {
  let path = dir + "/" + INDEXIONIGNORE_FILENAME
  try {
    let content = @fs.read_file_to_string(path)
    parse_ignore_file(content, path)
  } catch {
    _ => []
  }
}

///|
/// Load all ignore patterns for a project directory.
pub fn load_project_ignores(root_dir : String) -> FilterConfig {
  let config = FilterConfig::new()
  // Load .gitignore
  let gitignore = load_gitignore(root_dir)
  for pattern in gitignore {
    config.gitignore_patterns.push(pattern)
  }
  // Load .indexionignore (higher priority)
  let indexionignore = load_indexionignore(root_dir)
  for pattern in indexionignore {
    config.indexionignore_patterns.push(pattern)
  }
  config
}

// Helper functions

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current.copy()))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  if start >= end {
    return ""
  }
  let buf : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    buf.push(chars[i])
  }
  String::from_array(buf)
}

///|
fn substring_after_ignore(s : String, start : Int) -> String {
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
fn substring_until(s : String, end : Int) -> String {
  let chars = s.to_array()
  if end <= 0 {
    return ""
  }
  let buf : Array[Char] = []
  for i = 0; i < end && i < chars.length(); i = i + 1 {
    buf.push(chars[i])
  }
  String::from_array(buf)
}
