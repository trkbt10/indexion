///|
/// CompiledCharClass represents a compiled character class for matching.
struct CompiledCharClass {
  name : String
  chars : Array[Char]
  ranges : Array[(Char, Char)]
}

///|
/// CompiledFst represents a compiled FST ready for execution.
pub struct CompiledFst {
  name : String
  initial : String
  classes : Array[CompiledCharClass]
  states : Map[String, Array[@types.FstTransition]]
}

///|
/// Compiles a PreprocessFstSpec into a CompiledFst.
pub fn compile_fst(spec : @types.PreprocessFstSpec) -> CompiledFst {
  let classes : Array[CompiledCharClass] = []
  for entry in spec.classes {
    let class_name = entry.0
    let pattern = entry.1
    classes.push(compile_char_class(class_name, pattern))
  }
  {
    name: spec.name,
    initial: spec.initial,
    classes,
    states: spec.states,
  }
}

///|
/// Compiles a character class pattern into a CompiledCharClass.
/// Supports patterns like: [A-Za-z0-9+/=]
fn compile_char_class(name : String, pattern : String) -> CompiledCharClass {
  let chars : Array[Char] = []
  let ranges : Array[(Char, Char)] = []
  let arr = pattern.to_array()
  let len = arr.length()
  // Check if pattern is a character class [...]
  if len >= 2 && arr[0] == '[' && arr[len - 1] == ']' {
    // Parse character class contents
    let mut i = 1
    while i < len - 1 {
      let c = arr[i]
      // Check for escape sequences
      if c == '\\' && i + 1 < len - 1 {
        // Handle common escapes
        let next = arr[i + 1]
        match next {
          's' => {
            // whitespace
            chars.push(' ')
            chars.push('\t')
            chars.push('\n')
            chars.push('\r')
            i += 2
            continue
          }
          'n' => {
            chars.push('\n')
            i += 2
            continue
          }
          'r' => {
            chars.push('\r')
            i += 2
            continue
          }
          't' => {
            chars.push('\t')
            i += 2
            continue
          }
          _ => {
            chars.push(next)
            i += 2
            continue
          }
        }
      }
      // Check for range (e.g., A-Z)
      if i + 2 < len - 1 && arr[i + 1] == '-' {
        let range_end = arr[i + 2]
        ranges.push((c, range_end))
        i += 3
      } else {
        chars.push(c)
        i += 1
      }
    }
  } else if len == 1 {
    // Single character
    chars.push(arr[0])
  } else {
    // Treat as literal chars
    for c in arr {
      chars.push(c)
    }
  }
  { name, chars, ranges }
}

///|
/// Checks if a character matches a compiled character class.
fn char_matches_class(ch : Char, class : CompiledCharClass) -> Bool {
  // Check direct chars
  for c in class.chars {
    if ch == c {
      return true
    }
  }
  // Check ranges
  for range in class.ranges {
    if ch >= range.0 && ch <= range.1 {
      return true
    }
  }
  false
}

///|
/// Classifies a character according to the FST's character classes.
/// Returns the name of the matching class, or None if no match.
fn classify_char(fst : CompiledFst, ch : Char) -> String? {
  for class in fst.classes {
    if char_matches_class(ch, class) {
      return Some(class.name)
    }
  }
  None
}

///|
/// Finds a matching transition for the given input class.
fn match_transition(
  transitions : Array[@types.FstTransition],
  input_class : String
) -> @types.FstTransition? {
  // Try direct match first
  for t in transitions {
    if t.on == input_class {
      return Some(t)
    }
  }
  // Try wildcard
  for t in transitions {
    if t.on == "*" {
      return Some(t)
    }
  }
  None
}

///|
/// Converts a base64 character to its sextet value.
fn sextet(ch : Char) -> Int? {
  let code = ch.to_int()
  if code >= 0x41 && code <= 0x5a {
    // A-Z
    return Some(code - 0x41)
  }
  if code >= 0x61 && code <= 0x7a {
    // a-z
    return Some(code - 0x61 + 26)
  }
  if code >= 0x30 && code <= 0x39 {
    // 0-9
    return Some(code - 0x30 + 52)
  }
  if ch == '+' || ch == '-' {
    return Some(62)
  }
  if ch == '/' || ch == '_' {
    return Some(63)
  }
  None
}

///|
/// Decodes a quartet of base64 sextets into bytes.
fn decode_quartet(sextets : Array[Int], pad : Int) -> Array[Int] {
  if sextets.length() != 4 {
    return []
  }
  let s0 = sextets[0]
  let s1 = sextets[1]
  let s2 = sextets[2]
  let s3 = sextets[3]
  let b0 = ((s0 << 2) | (s1 >> 4)).land(0xff)
  let b1 = (((s1.land(0x0f)) << 4) | (s2 >> 2)).land(0xff)
  let b2 = (((s2.land(0x03)) << 6) | s3).land(0xff)
  if pad == 2 {
    [b0]
  } else if pad == 1 {
    [b0, b1]
  } else {
    [b0, b1, b2]
  }
}

///|
/// UTF-8 aggregate classification result.
priv enum Utf8Agg {
  A // ASCII printable (no control, no whitespace, no multibyte)
  W // Has whitespace
  C // Has control characters
  U // Has multibyte UTF-8 (Unicode)
  X // Invalid UTF-8
}

///|
/// Checks if a byte is whitespace.
fn is_ws_byte(b : Int) -> Bool {
  b == 0x09 || b == 0x0a || b == 0x0d || b == 0x20
}

///|
/// Checks if a byte is a control character.
fn is_ctrl_byte(b : Int) -> Bool {
  (b >= 0x00 && b < 0x20) || b == 0x7f
}

///|
/// Classifies a byte array as UTF-8 text.
fn classify_utf8(bytes : Array[Int]) -> Utf8Agg {
  let mut saw_multibyte = false
  let mut saw_ws = false
  let mut saw_ctrl = false
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i]
    if b0 <= 0x7f {
      if is_ws_byte(b0) {
        saw_ws = true
      } else if is_ctrl_byte(b0) {
        saw_ctrl = true
      }
      i += 1
      continue
    }
    // Reject continuation at lead position
    if b0.land(0xc0) == 0x80 {
      return X
    }
    // 2-byte sequence (0xC2-0xDF)
    if b0 >= 0xc2 && b0 <= 0xdf {
      if i + 1 >= len {
        return X
      }
      let b1 = bytes[i + 1]
      if b1.land(0xc0) != 0x80 {
        return X
      }
      saw_multibyte = true
      i += 2
      continue
    }
    // 3-byte sequence (0xE0-0xEF)
    if b0 >= 0xe0 && b0 <= 0xef {
      if i + 2 >= len {
        return X
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      let b1_ok = b1.land(0xc0) == 0x80 &&
        (b0 != 0xe0 || b1 >= 0xa0) &&
        (b0 != 0xed || b1 <= 0x9f)
      let b2_ok = b2.land(0xc0) == 0x80
      if not(b1_ok) || not(b2_ok) {
        return X
      }
      saw_multibyte = true
      i += 3
      continue
    }
    // 4-byte sequence (0xF0-0xF4)
    if b0 >= 0xf0 && b0 <= 0xf4 {
      if i + 3 >= len {
        return X
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      let b3 = bytes[i + 3]
      let b1_ok = b1.land(0xc0) == 0x80 &&
        (b0 != 0xf0 || b1 >= 0x90) &&
        (b0 != 0xf4 || b1 <= 0x8f)
      let b2_ok = b2.land(0xc0) == 0x80
      let b3_ok = b3.land(0xc0) == 0x80
      if not(b1_ok) || not(b2_ok) || not(b3_ok) {
        return X
      }
      saw_multibyte = true
      i += 4
      continue
    }
    return X
  }
  if saw_multibyte {
    U
  } else if saw_ws {
    W
  } else if saw_ctrl {
    C
  } else {
    A
  }
}

///|
/// Converts Utf8Agg to string label.
fn utf8_agg_to_string(agg : Utf8Agg) -> String {
  match agg {
    A => "A"
    W => "W"
    C => "C"
    U => "U"
    X => "X"
  }
}

///|
/// Runs a compiled FST over the input string and returns the transformed output.
pub fn run_fst(fst : CompiledFst, input : String) -> String raise Error {
  let emit = StringBuilder::new()
  let mut state = fst.initial
  let buf_chars : Array[Char] = []
  let buf_sextets : Array[Int] = []
  fn flush(pad : Int) -> Unit {
    if buf_chars.length() != 4 || buf_sextets.length() != 4 {
      // Invalid leftover
      for ch in buf_chars {
        if ch == '=' {
          emit.write_char('=')
        } else {
          emit.write_char('X')
        }
      }
      buf_chars.clear()
      buf_sextets.clear()
      return
    }
    let bytes = decode_quartet(buf_sextets, pad)
    let cls = classify_utf8(bytes)
    let cls_str = utf8_agg_to_string(cls)
    for ch in buf_chars {
      if ch == '=' {
        emit.write_char('=')
      } else {
        emit.write_string(cls_str)
      }
    }
    buf_chars.clear()
    buf_sextets.clear()
  }

  fn apply_action(action : @types.FstAction, ch : Char) -> Unit {
    match action {
      EmitInput => emit.write_char(ch)
      Emit(value) => emit.write_string(value)
      Buf => {
        let s = sextet(ch)
        buf_chars.push(ch)
        buf_sextets.push(s.unwrap_or(0))
      }
      Flush(pad) => flush(pad)
    }
  }

  for ch in input {
    let cls = classify_char(fst, ch)
    guard cls is Some(input_class) else {
      raise Failure::Failure(
        "preprocess_fst(\{fst.name}): no class matched input char '\{ch}'",
      )
    }
    let transitions = fst.states.get(state).unwrap_or([])
    let tr = match_transition(transitions, input_class)
    guard tr is Some(transition) else {
      raise Failure::Failure(
        "preprocess_fst(\{fst.name}): no transition for state=\{state} on=\{input_class}",
      )
    }
    for action in transition.actions {
      apply_action(action, ch)
    }
    state = transition.to
  }
  // Flush any remaining buffer
  if buf_chars.length() > 0 {
    flush(0)
  }
  emit.to_string()
}
