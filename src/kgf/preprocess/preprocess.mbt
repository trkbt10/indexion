///|
/// Applies preprocessing steps to the input string.
/// Supports:
/// - `fst:name` to apply a named FST
/// - `base64ToHex` to convert base64 to hex
pub fn apply_preprocess(
  input : String,
  preprocess : Array[String]?,
  preprocess_fst : Array[@types.PreprocessFstSpec]?,
) -> String raise Error {
  guard preprocess is Some(steps) else { return input }
  if steps.is_empty() {
    return input
  }
  // Compile FSTs
  let fsts : Map[String, CompiledFst] = {}
  match preprocess_fst {
    Some(specs) =>
      for spec in specs {
        fsts.set(spec.name, compile_fst(spec))
      }
    None => ()
  }
  // Apply each step
  let mut result = input
  for step in steps {
    result = apply_one(result, step, fsts)
  }
  result
}

///|
/// Applies a single preprocessing step.
fn apply_one(
  input : String,
  step : String,
  fsts : Map[String, CompiledFst],
) -> String raise Error {
  if step.has_prefix("fst:") {
    let fst_name = step[4:].to_string()
    match fsts.get(fst_name) {
      Some(fst) => run_fst(fst, input)
      None => raise Failure::Failure("Unknown preprocess FST: \{fst_name}")
    }
  } else if step.has_prefix("blankLineIfContainsCodepoint:") {
    let codepoint = parse_hex_codepoint(
      step["blankLineIfContainsCodepoint:".length():].to_string(),
    )
    blank_line_if_contains_codepoint(input, codepoint)
  } else if step.has_prefix("blankLineIfContains:") {
    let needle = step["blankLineIfContains:".length():].to_string()
    blank_line_if_contains(input, needle)
  } else if step.has_prefix("blankLineIfTrimHasPrefix:") {
    let prefix = step["blankLineIfTrimHasPrefix:".length():].to_string()
    blank_line_if_trim_has_prefix(input, prefix)
  } else if step.has_prefix("blankLineIfRegex:") {
    let pattern = step["blankLineIfRegex:".length():].to_string()
    blank_line_if_regex(input, pattern)
  } else if step == "base64ToHex" {
    base64_to_hex(input)
  } else {
    raise Failure::Failure("Unknown preprocess step: \{step}")
  }
}

///|
fn blank_matching_lines(
  input : String,
  predicate : (String, String) -> Bool,
) -> String {
  let buf = StringBuilder::new()
  let line = StringBuilder::new()
  let flush = fn(text : String, has_newline : Bool) {
    let trimmed = text.trim().to_string()
    if predicate(text, trimmed) {
      if has_newline {
        buf.write_string("\n")
      }
    } else {
      buf.write_string(text)
      if has_newline {
        buf.write_string("\n")
      }
    }
  }
  for ch in input {
    if ch == '\n' {
      flush(line.to_string(), true)
      line.reset()
    } else if ch == '\r' {
      continue
    } else {
      line.write_char(ch)
    }
  }
  let trailing = line.to_string()
  if trailing.length() > 0 {
    flush(trailing, false)
  }
  buf.to_string()
}

///|
fn blank_line_if_contains(input : String, needle : String) -> String {
  blank_matching_lines(input, fn(raw, _trimmed) { raw.contains(needle) })
}

///|
fn blank_line_if_trim_has_prefix(input : String, prefix : String) -> String {
  blank_matching_lines(input, fn(_raw, trimmed) { trimmed.has_prefix(prefix) })
}

///|
fn blank_line_if_regex(input : String, pattern : String) -> String {
  blank_matching_lines(input, fn(_raw, trimmed) {
    @kgf_lexer.matches_at(pattern, trimmed, 0)
  })
}

///|
fn blank_line_if_contains_codepoint(input : String, codepoint : Int) -> String {
  blank_matching_lines(input, fn(raw, _trimmed) {
    let ch = Int::unsafe_to_char(codepoint)
    raw.contains(ch.to_string())
  })
}

///|
fn parse_hex_codepoint(text : String) -> Int raise Error {
  if text.length() == 0 {
    raise Failure::Failure("Expected hexadecimal codepoint")
  }
  let mut result = 0
  for ch in text {
    let digit = if ch >= '0' && ch <= '9' {
      ch.to_int() - '0'.to_int()
    } else if ch >= 'a' && ch <= 'f' {
      ch.to_int() - 'a'.to_int() + 10
    } else if ch >= 'A' && ch <= 'F' {
      ch.to_int() - 'A'.to_int() + 10
    } else {
      raise Failure::Failure("Invalid hexadecimal codepoint: \{text}")
    }
    result = result * 16 + digit
  }
  result
}

// starts_with: use String::has_prefix (builtin)
// substr_from: use String::substring (builtin)

///|
/// Converts a base64 string to hexadecimal.
fn base64_to_hex(input : String) -> String {
  // Clean input: remove non-base64 characters
  let cleaned = StringBuilder::new()
  for ch in input {
    if is_base64_char(ch) {
      cleaned.write_char(ch)
    }
  }
  let clean_str = cleaned.to_string()
  // Pad to multiple of 4
  let pad_len = clean_str.length() % 4
  let padded = if pad_len == 0 {
    clean_str
  } else {
    let sb = StringBuilder::new()
    sb.write_string(clean_str)
    for _ in 0..<(4 - pad_len) {
      sb.write_char('=')
    }
    sb.to_string()
  }
  // Decode base64 to bytes
  let bytes = decode_base64(padded)
  // Convert to hex
  let hex = StringBuilder::new()
  for b in bytes {
    hex.write_string(byte_to_hex(b))
  }
  hex.to_string()
}

///|
/// Checks if a character is a valid base64 character.
fn is_base64_char(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '+' ||
  ch == '/' ||
  ch == '=' ||
  ch == '-' ||
  ch == '_'
}

///|
/// Decodes a base64 string to bytes.
fn decode_base64(input : String) -> Array[Int] {
  let result : Array[Int] = []
  let arr = input.to_array()
  let len = arr.length()
  let mut i = 0
  while i + 4 <= len {
    let c0 = arr[i]
    let c1 = arr[i + 1]
    let c2 = arr[i + 2]
    let c3 = arr[i + 3]
    let s0 = base64_value(c0)
    let s1 = base64_value(c1)
    let s2 = base64_value(c2)
    let s3 = base64_value(c3)
    // Decode quartet
    let b0 = ((s0 << 2) | (s1 >> 4)) & 0xff
    result.push(b0)
    if c2 != '=' {
      let b1 = (((s1 & 0x0f) << 4) | (s2 >> 2)) & 0xff
      result.push(b1)
    }
    if c3 != '=' {
      let b2 = (((s2 & 0x03) << 6) | s3) & 0xff
      result.push(b2)
    }
    i += 4
  }
  result
}

///|
/// Gets the numeric value of a base64 character.
fn base64_value(ch : Char) -> Int {
  let code = ch.to_int()
  if code >= 0x41 && code <= 0x5a {
    // A-Z
    return code - 0x41
  }
  if code >= 0x61 && code <= 0x7a {
    // a-z
    return code - 0x61 + 26
  }
  if code >= 0x30 && code <= 0x39 {
    // 0-9
    return code - 0x30 + 52
  }
  if ch == '+' || ch == '-' {
    return 62
  }
  if ch == '/' || ch == '_' {
    return 63
  }
  0
}

///|
/// Converts a byte to uppercase hexadecimal string.
fn byte_to_hex(b : Int) -> String {
  let hex_chars = "0123456789ABCDEF"
  let hex_arr = hex_chars.to_array()
  let high = hex_arr[(b >> 4) & 0x0f]
  let low = hex_arr[b & 0x0f]
  let sb = StringBuilder::new()
  sb.write_char(high)
  sb.write_char(low)
  sb.to_string()
}
