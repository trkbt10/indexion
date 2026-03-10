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
  let lines = @parser.split_lines(content)
  for line in lines {
    let trimmed = @parser.trim_str(line)
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
    s = @parser.substr_from(s, 1)
  }
  // Check for directory-only suffix
  if s.has_suffix("/") {
    directory_only = true
    s = @parser.substr(s, 0, s.to_array().length() - 1)
  }
  // Check if pattern is anchored (starts with / or contains /)
  if s.has_prefix("/") {
    anchored = true
    s = @parser.substr_from(s, 1)
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
/// Load ignore patterns from a specific file in a directory.
fn load_ignore_from_file(
  dir : String,
  filename : String,
) -> Array[IgnorePattern] {
  let path = dir + "/" + filename
  try {
    let content = @fs.read_file_to_string(path)
    parse_ignore_file(content, path)
  } catch {
    _ => []
  }
}

///|
/// Load gitignore from a directory.
pub fn load_gitignore(dir : String) -> Array[IgnorePattern] {
  load_ignore_from_file(dir, GITIGNORE_FILENAME)
}

///|
/// Load indexionignore from a directory.
pub fn load_indexionignore(dir : String) -> Array[IgnorePattern] {
  load_ignore_from_file(dir, INDEXIONIGNORE_FILENAME)
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
