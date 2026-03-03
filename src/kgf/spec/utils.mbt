///|
/// Splits text into lines, handling both \n and \r\n line endings.
pub fn split_lines(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let mut prev_cr = false
  for c in text {
    if c == '\n' {
      result.push(buf.to_string())
      buf.reset()
      prev_cr = false
    } else if c == '\r' {
      if prev_cr {
        // Double CR, treat as newline
        result.push(buf.to_string())
        buf.reset()
      }
      prev_cr = true
    } else {
      if prev_cr {
        // CR not followed by LF
        result.push(buf.to_string())
        buf.reset()
        prev_cr = false
      }
      buf.write_char(c)
    }
  }
  // Don't forget the last line if not ending with newline
  let last = buf.to_string()
  if last.length() > 0 || prev_cr {
    result.push(last)
  }
  result
}

///|
/// Checks if a character is whitespace.
pub fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Checks if a character is a digit.
pub fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Checks if a character is an identifier start character.
pub fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Checks if a character is an identifier character.
pub fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || is_digit(c)
}

///|
/// Finds the index of a substring in a string.
/// Returns -1 if not found.
pub fn find_substring(text : String, needle : String) -> Int {
  let n_len = needle.length()
  if n_len == 0 {
    return 0
  }
  if n_len > text.length() {
    return -1
  }
  let text_arr = text.to_array()
  let needle_arr = needle.to_array()
  for i in 0..<(text.length() - n_len + 1) {
    let mut found = true
    for j in 0..<n_len {
      if text_arr[i + j] != needle_arr[j] {
        found = false
        break
      }
    }
    if found {
      return i
    }
  }
  -1
}

///|
/// Finds the index of a character in a string starting from a position.
/// Returns -1 if not found.
pub fn find_char(text : String, start : Int, c : Char) -> Int {
  let arr = text.to_array()
  for i in start..<arr.length() {
    if arr[i] == c {
      return i
    }
  }
  -1
}

///|
/// Checks if a string starts with a given prefix.
pub fn starts_with(text : String, prefix : String) -> Bool {
  if prefix.length() > text.length() {
    return false
  }
  let text_arr = text.to_array()
  let prefix_arr = prefix.to_array()
  for i in 0..<prefix.length() {
    if text_arr[i] != prefix_arr[i] {
      return false
    }
  }
  true
}

///|
/// Checks if a string starts with a given prefix at a specific position.
pub fn starts_with_at(text : String, pos : Int, prefix : String) -> Bool {
  if pos + prefix.length() > text.length() {
    return false
  }
  let text_arr = text.to_array()
  let prefix_arr = prefix.to_array()
  for i in 0..<prefix.length() {
    if text_arr[pos + i] != prefix_arr[i] {
      return false
    }
  }
  true
}

///|
/// Trims whitespace from both ends of a string.
pub fn trim_str(text : String) -> String {
  let len = text.length()
  if len == 0 {
    return text
  }
  let arr = text.to_array()
  let mut start = 0
  while start < len && is_whitespace(arr[start]) {
    start += 1
  }
  let mut end_pos = len
  while end_pos > start && is_whitespace(arr[end_pos - 1]) {
    end_pos -= 1
  }
  if start == 0 && end_pos == len {
    text
  } else {
    substr(text, start, end_pos)
  }
}

///|
/// Splits a comma/whitespace list into string array.
pub fn parse_list(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for c in s {
    if c == ',' || is_whitespace(c) {
      let part = trim_str(buf.to_string())
      if part.length() > 0 {
        result.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let part = trim_str(buf.to_string())
  if part.length() > 0 {
    result.push(part)
  }
  result
}

///|
/// Gets a substring from start to end position.
pub fn substr(text : String, start : Int, end : Int) -> String {
  let arr = text.to_array()
  let actual_end = if end > arr.length() { arr.length() } else { end }
  let actual_start = if start < 0 { 0 } else { start }
  if actual_start >= actual_end {
    return ""
  }
  let result = StringBuilder::new()
  for i = actual_start; i < actual_end; i = i + 1 {
    result.write_char(arr[i])
  }
  result.to_string()
}

///|
/// Gets a substring from start to the end of the string.
pub fn substr_from(text : String, start : Int) -> String {
  if start >= text.length() {
    return ""
  }
  let arr = text.to_array()
  let result = StringBuilder::new()
  for i = start; i < arr.length(); i = i + 1 {
    result.write_char(arr[i])
  }
  result.to_string()
}

///|
/// Gets a character at a position, returning Char.
pub fn char_at(text : String, pos : Int) -> Char {
  let arr = text.to_array()
  arr[pos]
}
