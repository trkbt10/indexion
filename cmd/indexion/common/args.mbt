///|
/// Common CLI argument parsing utilities.
/// SoT for argument parsing functions used across CLI commands.

///|
/// Extract value after '=' in argument.
/// Example: get_arg_value("--foo=bar", 6) returns "bar"
pub fn get_arg_value(arg : String, prefix_len : Int) -> String {
  let chars = arg.to_array()
  if prefix_len >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = prefix_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Parse a double from string.
/// Handles negative numbers and decimal points.
pub fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0.0
  }
  let mut result = 0.0
  let mut decimal_place = 0
  let mut is_negative = false
  let mut i = 0
  if chars[0] == '-' {
    is_negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c == '.' {
      decimal_place = 1
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_double()
      if decimal_place > 0 {
        let mut divisor = 1.0
        for j = 0; j < decimal_place; j = j + 1 {
          divisor = divisor * 10.0
        }
        result = result + digit / divisor
        decimal_place = decimal_place + 1
      } else {
        result = result * 10.0 + digit
      }
    }
    i = i + 1
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Parse an integer from string.
pub fn parse_int(s : String) -> Int {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0
  }
  let mut result = 0
  let mut is_negative = false
  let mut i = 0
  if chars[0] == '-' {
    is_negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
    i = i + 1
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
/// Parse a comma-separated list, trimming surrounding spaces per entry.
pub fn parse_comma_list(s : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == ',' {
      let part = trim_ascii_spaces(String::from_array(current))
      if part.length() > 0 {
        result.push(part)
      }
      current.clear()
    } else {
      current.push(c)
    }
  }
  let last = trim_ascii_spaces(String::from_array(current))
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
fn trim_ascii_spaces(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end &&
        (
          chars[start] == ' ' ||
          chars[start] == '\t' ||
          chars[start] == '\n' ||
          chars[start] == '\r'
        ) {
    start = start + 1
  }
  while end > start &&
        (
          chars[end - 1] == ' ' ||
          chars[end - 1] == '\t' ||
          chars[end - 1] == '\n' ||
          chars[end - 1] == '\r'
        ) {
    end = end - 1
  }
  if start == 0 && end == chars.length() {
    return s
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

// === Path utilities (SoT for CLI commands) ===

///|
/// Extract directory name (last component) from path.
/// Example: "/foo/bar/baz" -> "baz", "pkg" -> "pkg"
pub fn extract_dirname(path : String) -> String {
  let clean = @pipeline.trim_trailing_slash(path)
  let chars = clean.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    clean
  } else {
    let result : Array[Char] = []
    for i = last_sep + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  }
}

///|
/// Convert absolute path to relative path from base directory.
/// Example: make_relative_path("/foo/bar/x.ts", "/foo/bar") -> "x.ts"
pub fn make_relative_path(path : String, base : String) -> String {
  let clean_base = @pipeline.trim_trailing_slash(base)
  let prefix = clean_base + "/"
  if path.has_prefix(prefix) {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = prefix.length(); i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
/// Extract dirname prefix from display_name (before ':').
/// Example: "pkg1:auth/client.ts" -> "pkg1"
pub fn get_dirname_prefix(display_name : String) -> String {
  let chars = display_name.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      let result : Array[Char] = []
      for j = 0; j < i; j = j + 1 {
        result.push(chars[j])
      }
      return String::from_array(result)
    }
  }
  "" // No prefix means single directory mode
}

///|
/// Get relative part from display_name (after ':').
/// Example: "pkg1:auth/client.ts" -> "auth/client.ts"
pub fn get_relative_part(display_name : String) -> String {
  let chars = display_name.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      let result : Array[Char] = []
      for j = i + 1; j < chars.length(); j = j + 1 {
        result.push(chars[j])
      }
      return String::from_array(result)
    }
  }
  display_name
}

///|
/// Split path by slash separator.
/// Example: "foo/bar/baz" -> ["foo", "bar", "baz"]
pub fn split_by_slash(path : String) -> Array[String] {
  let parts : Array[String] = []
  let chars = path.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '/' || c == '\\' {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
/// Extract unique display names for directories.
/// If all end with same name (e.g., "src"), use parent directory name.
/// Returns array of names in same order as input dirs.
pub fn extract_unique_dir_names(dirs : Array[String]) -> Array[String] {
  let base_names : Array[String] = []
  for dir in dirs {
    base_names.push(extract_dirname(dir))
  }
  // Check if all base names are the same
  let mut all_same = true
  if base_names.length() > 1 {
    let first = base_names[0]
    for i = 1; i < base_names.length(); i = i + 1 {
      if base_names[i] != first {
        all_same = false
        break
      }
    }
  } else {
    all_same = false
  }
  // If all same, use parent directory name
  if all_same {
    let names : Array[String] = []
    for dir in dirs {
      let clean = @pipeline.trim_trailing_slash(dir)
      let parts = split_by_slash(clean)
      if parts.length() >= 2 {
        names.push(parts[parts.length() - 2])
      } else if parts.length() == 1 {
        names.push(parts[0])
      } else {
        names.push(dir)
      }
    }
    names
  } else {
    base_names
  }
}
