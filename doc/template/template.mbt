// Template processing for README generation.
// Supports placeholder replacement with AUTO:NAME markers.

///|
/// Process a template string, replacing placeholders with values.
/// Placeholders are in the format: <!-- AUTO:NAME -->...<!-- /AUTO:NAME -->
/// The content between markers is replaced with the provided value.
///
/// Example:
/// ```
/// Template: <!-- AUTO:COMPONENTS -->old<!-- /AUTO:COMPONENTS -->
/// Placeholder: ("COMPONENTS", "new content")
/// Result: <!-- AUTO:COMPONENTS -->new content<!-- /AUTO:COMPONENTS -->
/// ```
pub fn process_template(
  template : String,
  placeholders : Map[String, String],
) -> String {
  let mut result = template
  for entry in placeholders {
    let name = entry.0
    let value = entry.1
    result = replace_placeholder(result, name, value)
  }
  result
}

///|
/// Replace a single placeholder in the template.
fn replace_placeholder(template : String, name : String, value : String) -> String {
  let start_marker = "<!-- AUTO:" + name + " -->"
  let end_marker = "<!-- /AUTO:" + name + " -->"
  let start_pos = find_string(template, start_marker)
  if start_pos < 0 {
    return template
  }
  let content_start = start_pos + string_length(start_marker)
  let end_pos = find_string_from(template, end_marker, content_start)
  if end_pos < 0 {
    return template
  }
  // Build the result: before + start_marker + newline + value + end_marker + after
  let before = substring(template, 0, start_pos)
  let after = substring_from(template, end_pos + string_length(end_marker))
  before + start_marker + "\n" + value + end_marker + after
}

///|
/// Find the position of a substring in a string.
/// Returns -1 if not found.
fn find_string(haystack : String, needle : String) -> Int {
  find_string_from(haystack, needle, 0)
}

///|
/// Find the position of a substring starting from a given position.
/// Returns -1 if not found.
fn find_string_from(haystack : String, needle : String, start : Int) -> Int {
  let h_chars = haystack.to_array()
  let n_chars = needle.to_array()
  let h_len = h_chars.length()
  let n_len = n_chars.length()
  if n_len == 0 {
    return start
  }
  if h_len < n_len {
    return -1
  }
  for i = start; i <= h_len - n_len; i = i + 1 {
    let mut match_ = true
    for j = 0; j < n_len; j = j + 1 {
      if h_chars[i + j] != n_chars[j] {
        match_ = false
        break
      }
    }
    if match_ {
      return i
    }
  }
  -1
}

///|
/// Get the length of a string.
fn string_length(s : String) -> Int {
  s.to_array().length()
}

///|
/// Get a substring from start to end (exclusive).
fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Get a substring from start to end of string.
fn substring_from(s : String, start : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Extract all placeholder names from a template.
/// Returns an array of placeholder names found.
pub fn extract_placeholders(template : String) -> Array[String] {
  let names : Array[String] = []
  let prefix = "<!-- AUTO:"
  let chars = template.to_array()
  let len = chars.length()
  let prefix_chars = prefix.to_array()
  let prefix_len = prefix_chars.length()
  let mut i = 0
  while i < len - prefix_len {
    // Check for prefix
    let mut match_ = true
    for j = 0; j < prefix_len; j = j + 1 {
      if chars[i + j] != prefix_chars[j] {
        match_ = false
        break
      }
    }
    if match_ {
      // Found prefix, extract name until " -->"
      let name_start = i + prefix_len
      let mut name_end = name_start
      // Find the closing " -->"
      while name_end < len - 3 {
        if chars[name_end] == ' ' &&
          chars[name_end + 1] == '-' &&
          chars[name_end + 2] == '-' &&
          chars[name_end + 3] == '>' {
          break
        }
        name_end = name_end + 1
      }
      if name_end > name_start {
        let name = substring(template, name_start, name_end)
        // Only add if it doesn't start with '/' (which is the closing marker)
        if not(starts_with_char(name, '/')) {
          // Check if already in array
          let mut found = false
          for existing in names {
            if existing == name {
              found = true
              break
            }
          }
          if not(found) {
            names.push(name)
          }
        }
      }
      i = name_end
    } else {
      i = i + 1
    }
  }
  names
}

///|
/// Check if string starts with a character.
fn starts_with_char(s : String, c : Char) -> Bool {
  let chars = s.to_array()
  chars.length() > 0 && chars[0] == c
}

///|
/// Validate that all placeholders in template have corresponding values.
/// Returns an array of missing placeholder names.
pub fn validate_placeholders(
  template : String,
  placeholders : Map[String, String],
) -> Array[String] {
  let names = extract_placeholders(template)
  let missing : Array[String] = []
  for name in names {
    if placeholders.get(name) is None {
      missing.push(name)
    }
  }
  missing
}
