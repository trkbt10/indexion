// get_arg_value: use @common (SoT)

///|
fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_start = if start < 0 { 0 } else { start }
  let capped_end = if end > chars.length() { chars.length() } else { end }
  if actual_start >= capped_end {
    return ""
  }
  let buf = StringBuilder::new(size_hint=capped_end - actual_start)
  for i = actual_start; i < capped_end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn trim_string(s : String) -> String {
  s.trim().to_string()
}

///|
fn lower_string(s : String) -> String {
  s.to_lower()
}

// parse_int: use @common (SoT)
// split_lines: use @common (SoT)

///|
fn join_lines(lines : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(line)
  }
  buf.to_string()
}

///|
fn is_blank_line(line : String) -> Bool {
  line.trim().length() == 0
}

///|
fn normalize_spaces(text : String) -> String {
  let chars = text.to_array()
  let buf = StringBuilder::new()
  let mut last_space = false
  for ch in chars {
    let is_space = ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
    if is_space {
      if not(last_space) {
        buf.write_char(' ')
      }
      last_space = true
    } else {
      buf.write_char(ch)
      last_space = false
    }
  }
  trim_string(buf.to_string())
}

///|
fn preview_text(text : String, max_len? : Int = 120) -> String {
  let normalized = normalize_spaces(text)
  if normalized.length() <= max_len {
    normalized
  } else {
    substring(normalized, 0, max_len) + "..."
  }
}

///|
fn make_hash(parts : Array[String]) -> String {
  @cas_hash.compute_hash(parts.join("\u0000")).to_string()
}

///|
fn last_index_of(s : String, ch : Char) -> Int {
  let chars = s.to_array()
  let mut idx = -1
  for i, current in chars {
    if current == ch {
      idx = i
    }
  }
  idx
}

///|
fn contains_string(values : Array[String], target : String) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn sort_strings(values : Array[String]) -> Array[String] {
  let sorted = values.copy()
  sorted.sort()
  sorted
}

///|
fn status_priority(status : String) -> Int {
  match status {
    "missing_doc" => 0
    "stale_doc" => 1
    "review_both" => 2
    _ => 3
  }
}
