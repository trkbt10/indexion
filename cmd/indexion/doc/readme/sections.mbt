///|
/// Section extraction from Markdown README files.

///|
/// Extract specified sections from Markdown content.
/// Returns content of matching sections joined together.
pub fn extract_sections(content : String, section_names : Array[String]) -> String {
  if section_names.is_empty() {
    return content
  }
  let normalized_names = normalize_section_names(section_names)
  let lines = split_content_lines(content)
  let result = StringBuilder::new()
  let mut current_section = ""
  let mut in_matching_section = false
  let mut first_output = true
  for line in lines {
    if is_heading_line(line) {
      let heading_text = extract_heading_text(line)
      current_section = normalize_section_name(heading_text)
      in_matching_section = contains_section_name(normalized_names, current_section)
      if in_matching_section {
        if not(first_output) {
          result.write_string("\n")
        }
        first_output = false
      }
    }
    if in_matching_section {
      result.write_string(line)
      result.write_char('\n')
    }
  }
  result.to_string()
}

///|
/// Extract overview/summary section (content before first ## heading).
pub fn extract_overview(content : String) -> String {
  let lines = split_content_lines(content)
  let result = StringBuilder::new()
  let mut found_first_heading = false
  let mut skipped_title = false
  for line in lines {
    // Skip the # title line
    if not(skipped_title) && line.has_prefix("# ") {
      skipped_title = true
      continue
    }
    // Stop at first ## heading
    if line.has_prefix("## ") {
      found_first_heading = true
      break
    }
    if skipped_title {
      result.write_string(line)
      result.write_char('\n')
    }
  }
  let _ = found_first_heading
  trim_section_content(result.to_string())
}

///|
fn normalize_section_names(names : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for name in names {
    result.push(normalize_section_name(name))
  }
  result
}

///|
fn normalize_section_name(name : String) -> String {
  // Lowercase and remove non-alphanumeric characters
  let chars = name.to_array()
  let result : Array[Char] = []
  for ch in chars {
    if is_alpha_char(ch) || is_digit_char(ch) {
      result.push(to_lower_char(ch))
    }
  }
  String::from_array(result)
}

///|
fn is_heading_line(line : String) -> Bool {
  line.has_prefix("## ") || line.has_prefix("### ")
}

///|
fn extract_heading_text(line : String) -> String {
  let chars = line.to_array()
  let mut start = 0
  // Skip # characters and spaces
  while start < chars.length() && (chars[start] == '#' || chars[start] == ' ') {
    start = start + 1
  }
  if start >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn contains_section_name(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

///|
fn split_content_lines(content : String) -> Array[String] {
  let lines : Array[String] = []
  let current : Array[Char] = []
  for ch in content.to_array() {
    if ch == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else {
      current.push(ch)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn trim_section_content(content : String) -> String {
  let chars = content.to_array()
  let mut start = 0
  let mut end = chars.length()
  // Trim leading whitespace/newlines
  while start < end && is_whitespace_char(chars[start]) {
    start = start + 1
  }
  // Trim trailing whitespace/newlines
  while end > start && is_whitespace_char(chars[end - 1]) {
    end = end - 1
  }
  if start >= end {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn is_alpha_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

///|
fn is_digit_char(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn to_lower_char(ch : Char) -> Char {
  if ch >= 'A' && ch <= 'Z' {
    Char::from_int(ch.to_int() + 32)
  } else {
    ch
  }
}

///|
fn is_whitespace_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}
