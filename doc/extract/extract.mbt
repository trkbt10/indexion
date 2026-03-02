// Comment extraction for JSDoc-style documentation.
// Parses @file, @description, and @example tags from source files.

///|
/// Parse a JSDoc comment block and extract documentation tags.
/// Supports @file, @description, and @example tags.
///
/// Example input:
/// ```
/// /**
///  * @file MyComponent - A useful component
///  * @description This component does something important.
///  * Multiple lines are supported.
///  * @example
///  * ```tsx
///  * <MyComponent />
///  * ```
///  */
/// ```
pub fn parse_doc_comment(content : String) -> @types.ComponentDoc {
  // Find the first JSDoc comment block /** ... */
  let jsdoc_content = extract_jsdoc_block(content)
  match jsdoc_content {
    None => @types.ComponentDoc::new("")
    Some(comment) => {
      let file_tag = extract_tag(comment, "file")
      let description = extract_multiline_tag(comment, "description")
      let example = extract_example_tag(comment)
      @types.ComponentDoc::make("", file_tag, description, example)
    }
  }
}

///|
/// Parse a JSDoc comment and extract a ComponentDoc with a given name.
pub fn parse_doc_comment_with_name(
  content : String,
  name : String,
) -> @types.ComponentDoc {
  let doc = parse_doc_comment(content)
  @types.ComponentDoc::make(
    name,
    doc.get_file_tag(),
    doc.get_description(),
    doc.get_example(),
  )
}

///|
/// Extract the first JSDoc comment block from content.
/// Returns the content between /** and */ (inclusive of markers).
fn extract_jsdoc_block(content : String) -> String? {
  let chars = content.to_array()
  let len = chars.length()
  let mut i = 0
  // Find /**
  while i < len - 2 {
    if chars[i] == '/' && chars[i + 1] == '*' && chars[i + 2] == '*' {
      // Found start, now find */
      let start = i
      i = i + 3
      while i < len - 1 {
        if chars[i] == '*' && chars[i + 1] == '/' {
          // Extract the content
          let result : Array[Char] = []
          for j = start; j <= i + 1; j = j + 1 {
            result.push(chars[j])
          }
          return Some(String::from_array(result))
        }
        i = i + 1
      }
      return None // No closing */
    }
    i = i + 1
  }
  None
}

///|
/// Extract a single-line tag value (e.g., @file).
fn extract_tag(comment : String, tag_name : String) -> String? {
  let lines = split_lines(comment)
  let tag_prefix = "@" + tag_name
  for line in lines {
    let trimmed = trim_comment_line(line)
    if starts_with(trimmed, tag_prefix) {
      let value = substring_after(trimmed, tag_prefix)
      let result = trim_whitespace(value)
      if result.length() > 0 {
        return Some(result)
      }
    }
  }
  None
}

///|
/// Extract a multi-line tag value (e.g., @description).
/// Collects lines until the next @tag or end of comment.
fn extract_multiline_tag(comment : String, tag_name : String) -> String? {
  let lines = split_lines(comment)
  let tag_prefix = "@" + tag_name
  let mut found = false
  let result_lines : Array[String] = []
  for line in lines {
    let trimmed = trim_comment_line(line)
    if found {
      // Check if we hit another tag
      if starts_with(trimmed, "@") && not(starts_with(trimmed, tag_prefix)) {
        break
      }
      // Skip the tag line itself if it's empty after tag
      if starts_with(trimmed, tag_prefix) {
        let after_tag = trim_whitespace(substring_after(trimmed, tag_prefix))
        if after_tag.length() > 0 {
          result_lines.push(after_tag)
        }
      } else if trimmed.length() > 0 {
        result_lines.push(trimmed)
      }
    } else if starts_with(trimmed, tag_prefix) {
      found = true
      let after_tag = trim_whitespace(substring_after(trimmed, tag_prefix))
      if after_tag.length() > 0 {
        result_lines.push(after_tag)
      }
    }
  }
  if result_lines.length() == 0 {
    return None
  }
  Some(join_strings(result_lines, " "))
}

///|
/// Extract example tag content, preserving code blocks.
fn extract_example_tag(comment : String) -> String? {
  let lines = split_lines(comment)
  let mut found = false
  let mut in_code_block = false
  let result_lines : Array[String] = []
  for line in lines {
    let trimmed = trim_comment_line(line)
    if found {
      // Check if we hit another tag (but not inside code block)
      if not(in_code_block) &&
        starts_with(trimmed, "@") &&
        not(starts_with(trimmed, "@example")) {
        break
      }
      // Track code blocks
      if starts_with(trimmed, "```") {
        in_code_block = not(in_code_block)
      }
      result_lines.push(trimmed)
    } else if starts_with(trimmed, "@example") {
      found = true
      let after_tag = trim_whitespace(substring_after(trimmed, "@example"))
      if after_tag.length() > 0 {
        result_lines.push(after_tag)
      }
    }
  }
  if result_lines.length() == 0 {
    return None
  }
  Some(join_strings(result_lines, "\n"))
}

///|
/// Split a string into lines.
fn split_lines(s : String) -> Array[String] {
  let chars = s.to_array()
  let lines : Array[String] = []
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current))
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
/// Trim comment line markers (* at start of line).
fn trim_comment_line(line : String) -> String {
  let chars = line.to_array()
  let len = chars.length()
  let mut start = 0
  // Skip leading whitespace
  while start < len && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  // Skip /** or */
  if start < len - 2 &&
    chars[start] == '/' &&
    chars[start + 1] == '*' &&
    chars[start + 2] == '*' {
    start = start + 3
  } else if start < len - 1 && chars[start] == '*' && chars[start + 1] == '/' {
    return ""
  } else if start < len && chars[start] == '*' {
    start = start + 1
  }
  // Skip one space after *
  if start < len && chars[start] == ' ' {
    start = start + 1
  }
  // Build result
  let result : Array[Char] = []
  for i = start; i < len; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Check if string starts with prefix.
fn starts_with(s : String, prefix : String) -> Bool {
  let s_chars = s.to_array()
  let p_chars = prefix.to_array()
  if s_chars.length() < p_chars.length() {
    return false
  }
  for i = 0; i < p_chars.length(); i = i + 1 {
    if s_chars[i] != p_chars[i] {
      return false
    }
  }
  true
}

///|
/// Get substring after prefix.
fn substring_after(s : String, prefix : String) -> String {
  let chars = s.to_array()
  let p_len = prefix.to_array().length()
  if chars.length() <= p_len {
    return ""
  }
  let result : Array[Char] = []
  for i = p_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Trim leading and trailing whitespace.
fn trim_whitespace(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  if len == 0 {
    return ""
  }
  let mut start = 0
  while start < len && is_whitespace(chars[start]) {
    start = start + 1
  }
  let mut end = len - 1
  while end >= start && is_whitespace(chars[end]) {
    end = end - 1
  }
  if start > end {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i <= end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Check if character is whitespace.
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Join strings with separator.
fn join_strings(strings : Array[String], sep : String) -> String {
  if strings.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  let sep_chars = sep.to_array()
  for i, s in strings {
    if i > 0 {
      for c in sep_chars {
        result.push(c)
      }
    }
    for c in s.to_array() {
      result.push(c)
    }
  }
  String::from_array(result)
}
