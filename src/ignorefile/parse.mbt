///|
/// Parse content in gitignore syntax into patterns.
/// This syntax is shared by .gitignore, .indexionignore, and similar files.
pub fn parse(content : String, source : String) -> Array[IgnorePattern] {
  let patterns : Array[IgnorePattern] = []
  let lines = @parser.split_lines(content)
  for line in lines {
    let trimmed = @parser.trim_str(line)
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      continue
    }
    patterns.push(parse_line(trimmed, source))
  }
  patterns
}

///|
fn parse_line(line : String, source : String) -> IgnorePattern {
  let mut s = line
  let mut negated = false
  let mut directory_only = false
  let mut anchored = false
  if s.has_prefix("!") {
    negated = true
    s = @parser.substr_from(s, 1)
  }
  if s.has_suffix("/") {
    directory_only = true
    s = @parser.substr(s, 0, s.to_array().length() - 1)
  }
  if s.has_prefix("/") {
    anchored = true
    s = @parser.substr_from(s, 1)
  } else if contains_slash(s) {
    anchored = true
  }
  IgnorePattern::new(s, negated~, directory_only~, anchored~, source~)
}

///|
fn contains_slash(s : String) -> Bool {
  for c in s {
    if c == '/' {
      return true
    }
  }
  false
}
