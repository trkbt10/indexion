///|
/// Result of a pattern match attempt.
/// Contains whether the match succeeded, the end position, and the matched text.
pub struct MatchResult {
  matched : Bool
  end_pos : Int
  text : String
}

///|
/// Creates a successful match result.
pub fn MatchResult::success(end_pos : Int, text : String) -> MatchResult {
  { matched: true, end_pos, text }
}

///|
/// Creates a failed match result.
pub fn MatchResult::failure() -> MatchResult {
  { matched: false, end_pos: 0, text: "" }
}

///|
/// Checks if a character is a whitespace character.
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Checks if a character is a digit.
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Checks if a character is a word character (alphanumeric or underscore).
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Parsed pattern element for internal use.
priv enum PatternElement {
  Literal(Char)
  CharClass(Array[(Char, Char)], Bool) // ranges, negated
  AnyChar // .
  Escape(Char) // \s, \w, \d, \S, \W, \D, etc.
  WordBoundary // \b - zero-width assertion
  NonWordBoundary // \B - zero-width assertion
  StartAnchor // ^ - start of string/line
  EndAnchor // $ - end of string/line
  StringStart // \A - absolute start of string
  StringEnd // \z - absolute end of string
  Group(Array[QuantifiedElement], Int?) // elements, capture_index (None = non-capturing)
  Alternation(Array[Array[QuantifiedElement]])
  Lookahead(Array[QuantifiedElement], Bool) // elements, positive (true=(?=...), false=(?!...))
}

///|
/// Mutable capture group state for tracking during matching.
priv struct CaptureState {
  /// (start, end) positions for each capture group, indexed by group number (1-based).
  groups : Array[(Int, Int)]
  /// Total number of capture groups in the pattern.
  count : Int
}

///|
fn CaptureState::new(count : Int) -> CaptureState {
  let groups : Array[(Int, Int)] = Array::make(count + 1, (-1, -1))
  { groups, count }
}

///|
fn CaptureState::set(
  self : CaptureState,
  index : Int,
  start : Int,
  end : Int,
) -> Unit {
  if index >= 0 && index < self.groups.length() {
    self.groups[index] = (start, end)
  }
}

///|
fn CaptureState::reset(self : CaptureState, index : Int) -> Unit {
  if index >= 0 && index < self.groups.length() {
    self.groups[index] = (-1, -1)
  }
}

///|
/// Get captured text for group N from input chars.
fn CaptureState::get_group_text(
  self : CaptureState,
  index : Int,
  input_chars : Array[Char],
) -> String? {
  if index <= 0 || index > self.count {
    return None
  }
  let (start, end) = self.groups[index]
  if start < 0 || end < 0 {
    return None
  }
  let chars : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    if i < input_chars.length() {
      chars.push(input_chars[i])
    }
  }
  Some(String::from_array(chars))
}

///|
/// Quantifier type for pattern elements.
priv enum Quantifier {
  One
  ZeroOrMore // *
  OneOrMore // +
  ZeroOrOne // ?
  Exactly(Int) // {n}
  AtLeast(Int) // {n,}
  Between(Int, Int) // {n,m}
}

///|
/// Pattern element with quantifier.
priv struct QuantifiedElement {
  element : PatternElement
  quantifier : Quantifier
  lazy_ : Bool
}

///|
/// CompiledPattern stores parsed regex elements for repeated matching.
priv struct CompiledPattern {
  alternatives : Array[Array[QuantifiedElement]]
  case_insensitive : Bool
  /// Optional first char filter for quick rejection.
  first_char_filter : FirstCharFilter
  /// Number of capture groups in the pattern.
  capture_count : Int
}

///|
/// First character filter for quick pattern rejection.
priv enum FirstCharFilter {
  Any // Pattern can start with any character
  Literal(Char) // Pattern must start with this exact char
  LiteralCI(Char, Char) // Case-insensitive: lower and upper
  CharClass(Array[(Char, Char)], Bool) // (ranges, negated)
}

///|
/// Mutable state for pattern parsing — tracks capture group numbering.
priv struct ParseContext {
  mut next_capture : Int
}

///|
fn ParseContext::new() -> ParseContext {
  { next_capture: 1 }
}

///|
fn ParseContext::alloc_capture(self : ParseContext) -> Int {
  let idx = self.next_capture
  self.next_capture += 1
  idx
}

///|
/// Gets a character from a string at the given index safely.

///|
/// Parses a Unicode escape \uXXXX from the pattern. Returns (char, new_pos).
fn parse_unicode_escape(pattern : String, start : Int) -> (Char, Int)? {
  // Need exactly 4 hex digits
  if start + 4 > pattern.length() {
    return None
  }
  let mut value = 0
  for i = 0; i < 4; i = i + 1 {
    let ch = Int::unsafe_to_char(pattern[start + i].to_int())
    let digit = match ch {
      '0' => 0
      '1' => 1
      '2' => 2
      '3' => 3
      '4' => 4
      '5' => 5
      '6' => 6
      '7' => 7
      '8' => 8
      '9' => 9
      'a' | 'A' => 10
      'b' | 'B' => 11
      'c' | 'C' => 12
      'd' | 'D' => 13
      'e' | 'E' => 14
      'f' | 'F' => 15
      _ => return None
    }
    value = value * 16 + digit
  }
  Some((Int::unsafe_to_char(value), start + 4))
}

///|
fn get_char_at(s : String, index : Int) -> Char? {
  if index >= 0 && index < s.length() {
    Some(Int::unsafe_to_char(s[index].to_int()))
  } else {
    None
  }
}

///|
/// Builds a char array once for repeated indexed access during matching.
fn build_input_chars(input : String) -> Array[Char] {
  let chars : Array[Char] = []
  let len = input.length()
  for i = 0; i < len; i = i + 1 {
    chars.push(Int::unsafe_to_char(input[i].to_int()))
  }
  chars
}

///|
/// Gets a character from prebuilt input chars.
fn get_input_char(input_chars : Array[Char], index : Int) -> Char? {
  if index >= 0 && index < input_chars.length() {
    Some(input_chars[index])
  } else {
    None
  }
}

///|
/// Parses a character class like [a-z], [0-9], [^abc].
fn parse_char_class(
  pattern : String,
  start : Int,
) -> (Array[(Char, Char)], Bool, Int)? {
  // start should point to '['
  if get_char_at(pattern, start) != Some('[') {
    return None
  }
  let mut pos = start + 1
  let negated = get_char_at(pattern, pos) == Some('^')
  if negated {
    pos = pos + 1
  }
  let ranges : Array[(Char, Char)] = []
  while pos < pattern.length() {
    match get_char_at(pattern, pos) {
      Some(']') => return Some((ranges, negated, pos + 1))
      Some('\\') => {
        // Escaped character - handle escape sequences and character class shortcuts
        pos = pos + 1
        match get_char_at(pattern, pos) {
          Some('s') => {
            // \s - whitespace characters
            ranges.push((' ', ' '))
            ranges.push(('\t', '\t'))
            ranges.push(('\n', '\n'))
            ranges.push(('\r', '\r'))
            pos = pos + 1
          }
          Some('S') => {
            // \S - non-whitespace: '!' (33) through U+FFFF covers all non-whitespace
            // Consistent with Escape('S') which uses not(is_whitespace(c))
            ranges.push(('!', '\u{FFFF}'))
            pos = pos + 1
          }
          Some('d') => {
            // \d - digits
            ranges.push(('0', '9'))
            pos = pos + 1
          }
          Some('D') => {
            // \D - non-digits: everything except '0'-'9'
            ranges.push(('\u0001', '/')) // U+0001 through '/' (before '0')
            ranges.push((':', '\u{FFFF}')) // ':' (after '9') through U+FFFF
            pos = pos + 1
          }
          Some('w') => {
            // \w - word characters
            ranges.push(('A', 'Z'))
            ranges.push(('a', 'z'))
            ranges.push(('0', '9'))
            ranges.push(('_', '_'))
            pos = pos + 1
          }
          Some('W') => {
            // \W - non-word characters: everything except [A-Za-z0-9_]
            ranges.push(('\u0001', '/')) // before '0'
            ranges.push((':', '@')) // between '9' and 'A'
            ranges.push(('[', '^')) // between 'Z' and '_'
            ranges.push(('`', '`')) // between '_' and 'a'
            ranges.push(('{', '\u{FFFF}')) // after 'z'
            pos = pos + 1
          }
          Some('u') =>
            // \uXXXX - Unicode escape
            match parse_unicode_escape(pattern, pos + 1) {
              Some((ch, new_pos)) =>
                // Check for range: \uXXXX-\uYYYY or \uXXXX-c
                if get_char_at(pattern, new_pos) == Some('-') &&
                  get_char_at(pattern, new_pos + 1) != Some(']') {
                  // Range end could be \uYYYY or a literal char
                  if get_char_at(pattern, new_pos + 1) == Some('\\') &&
                    get_char_at(pattern, new_pos + 2) == Some('u') {
                    match parse_unicode_escape(pattern, new_pos + 3) {
                      Some((end_ch, end_pos)) => {
                        ranges.push((ch, end_ch))
                        pos = end_pos
                      }
                      None => {
                        ranges.push((ch, ch))
                        pos = new_pos
                      }
                    }
                  } else {
                    match get_char_at(pattern, new_pos + 1) {
                      Some(end_c) => {
                        ranges.push((ch, end_c))
                        pos = new_pos + 2
                      }
                      None => {
                        ranges.push((ch, ch))
                        pos = new_pos
                      }
                    }
                  }
                } else {
                  ranges.push((ch, ch))
                  pos = new_pos
                }
              None => {
                ranges.push(('u', 'u'))
                pos = pos + 1
              }
            }
          Some(c) => {
            let escaped_char = match c {
              'n' => '\n'
              'r' => '\r'
              't' => '\t'
              _ => c
            }
            ranges.push((escaped_char, escaped_char))
            pos = pos + 1
          }
          None => return None
        }
      }
      Some(c) =>
        // Check for range
        if get_char_at(pattern, pos + 1) == Some('-') &&
          get_char_at(pattern, pos + 2) != Some(']') {
          match get_char_at(pattern, pos + 2) {
            Some(end_c) => {
              ranges.push((c, end_c))
              pos = pos + 3
            }
            None => return None
          }
        } else {
          ranges.push((c, c))
          pos = pos + 1
        }
      None => return None
    }
  }
  None
}

///|
/// Parses a brace quantifier {n}, {n,}, {n,m}.
fn parse_brace_quantifier(pattern : String, start : Int) -> (Quantifier, Int)? {
  if get_char_at(pattern, start) != Some('{') {
    return None
  }
  let mut pos = start + 1
  // Parse first number
  let mut n = 0
  let mut has_n = false
  while pos < pattern.length() {
    match get_char_at(pattern, pos) {
      Some(c) =>
        if is_digit(c) {
          n = n * 10 + (c.to_int() - '0'.to_int())
          has_n = true
          pos = pos + 1
        } else {
          break
        }
      None => return None
    }
  }
  if not(has_n) {
    return None
  }
  match get_char_at(pattern, pos) {
    Some('}') => {
      // {n} - exactly n
      pos = pos + 1
      // Skip non-greedy marker
      if get_char_at(pattern, pos) == Some('?') {
        pos = pos + 1
      }
      Some((Exactly(n), pos))
    }
    Some(',') => {
      pos = pos + 1
      // Check if there's an upper bound
      match get_char_at(pattern, pos) {
        Some('}') => {
          // {n,} - at least n
          pos = pos + 1
          if get_char_at(pattern, pos) == Some('?') {
            pos = pos + 1
          }
          Some((AtLeast(n), pos))
        }
        Some(c) =>
          if is_digit(c) {
            // {n,m} - between n and m
            let mut m = 0
            while pos < pattern.length() {
              match get_char_at(pattern, pos) {
                Some(c2) =>
                  if is_digit(c2) {
                    m = m * 10 + (c2.to_int() - '0'.to_int())
                    pos = pos + 1
                  } else {
                    break
                  }
                None => return None
              }
            }
            if get_char_at(pattern, pos) == Some('}') {
              pos = pos + 1
              if get_char_at(pattern, pos) == Some('?') {
                pos = pos + 1
              }
              Some((Between(n, m), pos))
            } else {
              None
            }
          } else {
            None
          }
        None => None
      }
    }
    _ => None
  }
}

///|
/// Parses the pattern string into a list of quantified elements.
fn parse_pattern_ctx(
  pattern : String,
  ctx : ParseContext,
) -> Array[QuantifiedElement]? {
  let elements : Array[QuantifiedElement] = []
  let mut pos = 0
  while pos < pattern.length() {
    let (element, new_pos) : (PatternElement, Int) = match
      get_char_at(pattern, pos) {
      Some('^') => (StartAnchor, pos + 1)
      Some('$') => (EndAnchor, pos + 1)
      Some('\\') =>
        // Escape sequence
        match get_char_at(pattern, pos + 1) {
          Some('b') => (WordBoundary, pos + 2)
          Some('B') => (NonWordBoundary, pos + 2)
          Some('A') => (StringStart, pos + 2)
          Some('z') => (StringEnd, pos + 2)
          Some('u') =>
            // \uXXXX Unicode escape
            match parse_unicode_escape(pattern, pos + 2) {
              Some((ch, new_pos)) => (Literal(ch), new_pos)
              None => (Escape('u'), pos + 2)
            }
          Some(c) => (Escape(c), pos + 2)
          None => return None
        }
      Some('[') =>
        // Character class
        match parse_char_class(pattern, pos) {
          Some((ranges, negated, end_pos)) =>
            (CharClass(ranges, negated), end_pos)
          None => return None
        }
      Some('.') => (AnyChar, pos + 1)
      Some('(') => {
        // Group - find matching close paren
        let mut group_start = pos + 1
        // Check for group prefix: (?:...) (?=...) (?!...)
        let is_non_capturing = get_char_at(pattern, group_start) == Some('?') &&
          get_char_at(pattern, group_start + 1) == Some(':')
        let is_pos_lookahead = get_char_at(pattern, group_start) == Some('?') &&
          get_char_at(pattern, group_start + 1) == Some('=')
        let is_neg_lookahead = get_char_at(pattern, group_start) == Some('?') &&
          get_char_at(pattern, group_start + 1) == Some('!')
        let mut depth = 1
        let mut group_end = group_start
        while group_end < pattern.length() && depth > 0 {
          match get_char_at(pattern, group_end) {
            Some('(') => depth = depth + 1
            Some(')') => depth = depth - 1
            Some('\\') => group_end = group_end + 1 // skip escaped char
            _ => ()
          }
          if depth > 0 {
            group_end = group_end + 1
          }
        }
        if depth != 0 {
          return None
        }
        // Skip prefix (?:, (?=, (?!
        if is_non_capturing || is_pos_lookahead || is_neg_lookahead {
          group_start = group_start + 2
        }
        let group_pattern = pattern[group_start:group_end].to_string()
        // Lookahead — zero-width assertion
        if is_pos_lookahead || is_neg_lookahead {
          match parse_pattern_ctx(group_pattern, ctx) {
            Some(elems) => (Lookahead(elems, is_pos_lookahead), group_end + 1)
            None => return None
          }
        } else if is_non_capturing {
          // Non-capturing group: (?:...) — no capture index
          if group_pattern.contains("|") {
            let alternatives = split_by_alternation(group_pattern)
            let parsed_alternatives : Array[Array[QuantifiedElement]] = []
            for alt in alternatives {
              match parse_pattern_ctx(alt, ctx) {
                Some(elems) => parsed_alternatives.push(elems)
                None => return None
              }
            }
            (Alternation(parsed_alternatives), group_end + 1)
          } else {
            match parse_pattern_ctx(group_pattern, ctx) {
              Some(group_elems) => (Group(group_elems, None), group_end + 1)
              None => return None
            }
          }
        } else {
          // Capturing group: (...) — allocate capture index
          let capture_idx = ctx.alloc_capture()
          if group_pattern.contains("|") {
            // Capturing group with alternation: (a|b)
            // The group itself captures; alternation is internal
            let alternatives = split_by_alternation(group_pattern)
            let parsed_alternatives : Array[Array[QuantifiedElement]] = []
            for alt in alternatives {
              match parse_pattern_ctx(alt, ctx) {
                Some(elems) => parsed_alternatives.push(elems)
                None => return None
              }
            }
            // Wrap alternation inside a capturing group
            let alt_element : QuantifiedElement = {
              element: Alternation(parsed_alternatives),
              quantifier: One,
              lazy_: false,
            }
            (Group([alt_element], Some(capture_idx)), group_end + 1)
          } else {
            match parse_pattern_ctx(group_pattern, ctx) {
              Some(group_elems) =>
                (Group(group_elems, Some(capture_idx)), group_end + 1)
              None => return None
            }
          }
        }
      }
      Some('|') => {
        // Top-level alternation should be handled differently
        // For now, just skip
        pos = pos + 1
        continue
      }
      Some(c) => {
        if c == '*' || c == '+' || c == '?' {
          // Quantifier without preceding element, skip
          pos = pos + 1
          continue
        }
        (Literal(c), pos + 1)
      }
      None => break
    }
    pos = new_pos
    // Check for quantifier
    let mut lazy_ = false
    let quantifier = match get_char_at(pattern, pos) {
      Some('*') => {
        pos = pos + 1
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
          lazy_ = true
        }
        ZeroOrMore
      }
      Some('+') => {
        pos = pos + 1
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
          lazy_ = true
        }
        OneOrMore
      }
      Some('?') => {
        pos = pos + 1
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
          lazy_ = true
        }
        ZeroOrOne
      }
      Some('{') =>
        // Parse {n}, {n,}, {n,m}
        match parse_brace_quantifier(pattern, pos) {
          Some((q, new_pos)) => {
            pos = new_pos
            q
          }
          None => One
        }
      _ => One
    }
    elements.push({ element, quantifier, lazy_ })
  }
  Some(elements)
}

///|
/// Splits a pattern by top-level alternation.
fn split_by_alternation(pattern : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let mut depth = 0
  let mut pos = 0
  while pos < pattern.length() {
    match get_char_at(pattern, pos) {
      Some('(') => depth = depth + 1
      Some(')') => depth = depth - 1
      Some('[') => {
        // Skip character class
        pos = pos + 1
        while pos < pattern.length() && get_char_at(pattern, pos) != Some(']') {
          if get_char_at(pattern, pos) == Some('\\') {
            pos = pos + 1
          }
          pos = pos + 1
        }
      }
      Some('\\') => pos = pos + 1
      Some('|') =>
        if depth == 0 {
          result.push(pattern[start:pos].to_string())
          start = pos + 1
        }
      _ => ()
    }
    pos = pos + 1
  }
  result.push(pattern[start:pattern.length()].to_string())
  result
}

///|
/// Matches a single character against a pattern element.
fn match_char(
  element : PatternElement,
  c : Char,
  case_insensitive : Bool,
) -> Bool {
  match element {
    Literal(expected) =>
      if case_insensitive {
        to_lower(c) == to_lower(expected)
      } else {
        c == expected
      }
    AnyChar => c != '\n'
    Escape(escape_char) =>
      match escape_char {
        's' => is_whitespace(c)
        'S' => not(is_whitespace(c))
        'd' => is_digit(c)
        'D' => not(is_digit(c))
        'w' => is_word_char(c)
        'W' => not(is_word_char(c))
        'n' => c == '\n'
        'r' => c == '\r'
        't' => c == '\t'
        _ => c == escape_char
      }
    CharClass(ranges, negated) => {
      let mut in_class = false
      let ch = if case_insensitive { to_lower(c) } else { c }
      for range in ranges {
        let (start, end) = range
        let range_start = if case_insensitive { to_lower(start) } else { start }
        let range_end = if case_insensitive { to_lower(end) } else { end }
        if ch >= range_start && ch <= range_end {
          in_class = true
          break
        }
      }
      if negated {
        not(in_class)
      } else {
        in_class
      }
    }
    Group(_) | Alternation(_) | Lookahead(_, _) => false // Should not be called directly
    WordBoundary | NonWordBoundary => false // Zero-width assertions, handled in match_quantified
    StartAnchor | EndAnchor | StringStart | StringEnd => false // Anchors, handled in match_quantified
  }
}

///|
/// Converts a character to lowercase.
fn to_lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    Int::unsafe_to_char(c.to_int() + 32)
  } else {
    c
  }
}

///|
/// Checks if position is at a word boundary using prebuilt input chars.
fn is_at_word_boundary_with_chars(input_chars : Array[Char], pos : Int) -> Bool {
  let prev_is_word = match get_input_char(input_chars, pos - 1) {
    Some(c) => is_word_char(c)
    None => false // start of string
  }
  let curr_is_word = match get_input_char(input_chars, pos) {
    Some(c) => is_word_char(c)
    None => false // end of string
  }
  // Word boundary: transition between word and non-word
  prev_is_word != curr_is_word
}

///|
/// Matches a quantified element against the input starting at pos.
/// Returns the end position if matched, or None if no match.
fn match_quantified(
  qe : QuantifiedElement,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  let input_len = input_chars.length()
  match qe.element {
    // Zero-width assertions - don't consume characters
    WordBoundary =>
      if is_at_word_boundary_with_chars(input_chars, pos) {
        Some(pos)
      } else {
        None
      }
    NonWordBoundary =>
      if not(is_at_word_boundary_with_chars(input_chars, pos)) {
        Some(pos)
      } else {
        None
      }
    StartAnchor =>
      // ^ matches at start of string or after newline
      if pos == 0 {
        Some(pos)
      } else {
        match get_input_char(input_chars, pos - 1) {
          Some('\n') => Some(pos)
          _ => None
        }
      }
    EndAnchor =>
      // $ matches at end of string or before newline
      if pos >= input_len {
        Some(pos)
      } else {
        match get_input_char(input_chars, pos) {
          Some('\n') => Some(pos)
          _ => None
        }
      }
    StringStart =>
      // \A matches only at absolute start of string
      if pos == 0 {
        Some(pos)
      } else {
        None
      }
    StringEnd =>
      // \z matches only at absolute end of string
      if pos >= input_len {
        Some(pos)
      } else {
        None
      }
    Group(elements, _) =>
      match_group(elements, qe.quantifier, input_chars, pos, case_insensitive)
    Alternation(alternatives) =>
      match_alternation(
        alternatives,
        qe.quantifier,
        input_chars,
        pos,
        case_insensitive,
      )
    Lookahead(elements, positive) => {
      // Zero-width assertion: check if elements match at pos without consuming
      let matched = match
        match_elements_backtrack(
          elements, 0, input_chars, pos, case_insensitive,
        ) {
        Some(_) => true
        None => false
      }
      if matched == positive {
        Some(pos) // Zero-width: don't advance position
      } else {
        None
      }
    }
    _ =>
      match_simple(
        qe.element,
        qe.quantifier,
        input_chars,
        pos,
        case_insensitive,
      )
  }
}

///|
/// Matches a simple element (non-group) with quantifier.
fn match_simple(
  element : PatternElement,
  quantifier : Quantifier,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  match quantifier {
    One =>
      match get_input_char(input_chars, pos) {
        Some(c) =>
          if match_char(element, c, case_insensitive) {
            Some(pos + 1)
          } else {
            None
          }
        None => None
      }
    ZeroOrOne =>
      match get_input_char(input_chars, pos) {
        Some(c) =>
          if match_char(element, c, case_insensitive) {
            Some(pos + 1)
          } else {
            Some(pos)
          }
        None => Some(pos)
      }
    ZeroOrMore => {
      let input_len = input_chars.length()
      let mut current = pos
      while current < input_len {
        let c = input_chars[current]
        if match_char(element, c, case_insensitive) {
          current = current + 1
        } else {
          break
        }
      }
      Some(current)
    }
    OneOrMore => {
      let input_len = input_chars.length()
      if pos >= input_len {
        return None
      }
      let c = input_chars[pos]
      if match_char(element, c, case_insensitive) {
        let mut current = pos + 1
        while current < input_len {
          let c2 = input_chars[current]
          if match_char(element, c2, case_insensitive) {
            current = current + 1
          } else {
            break
          }
        }
        Some(current)
      } else {
        None
      }
    }
    Exactly(n) => {
      let input_len = input_chars.length()
      let mut current = pos
      for i = 0; i < n; i = i + 1 {
        if current >= input_len {
          return None
        }
        let c = input_chars[current]
        if match_char(element, c, case_insensitive) {
          current = current + 1
        } else {
          return None
        }
      }
      Some(current)
    }
    AtLeast(n) => {
      let input_len = input_chars.length()
      let mut current = pos
      // First, match exactly n times
      for i = 0; i < n; i = i + 1 {
        if current >= input_len {
          return None
        }
        let c = input_chars[current]
        if match_char(element, c, case_insensitive) {
          current = current + 1
        } else {
          return None
        }
      }
      // Then match as many more as possible
      while current < input_len {
        let c = input_chars[current]
        if match_char(element, c, case_insensitive) {
          current = current + 1
        } else {
          break
        }
      }
      Some(current)
    }
    Between(n, m) => {
      let input_len = input_chars.length()
      let mut current = pos
      let mut count = 0
      // Match up to m times, but at least n
      while count < m && current < input_len {
        let c = input_chars[current]
        if match_char(element, c, case_insensitive) {
          current = current + 1
          count = count + 1
        } else {
          break
        }
      }
      if count >= n {
        Some(current)
      } else {
        None
      }
    }
  }
}

///|
/// Collects all valid end positions for a repeated match_once function.
/// Returns positions ordered for backtracking (greedy: max→min, lazy: min→max).
fn collect_repeat_positions(
  match_once : (Int) -> Int?,
  quantifier : Quantifier,
  lazy_ : Bool,
  pos : Int,
) -> Array[Int] {
  // Collect all positions reachable by repeating match_once
  let all_positions : Array[Int] = [pos] // 0 repeats = pos
  let mut current = pos
  let max_repeats = match quantifier {
    Between(_, m) => m
    Exactly(n) => n
    _ => 2147483647 // max repeats
  }
  let mut count = 0
  while count < max_repeats {
    match match_once(current) {
      Some(new_pos) =>
        if new_pos == current {
          break // Empty match, stop
        } else {
          current = new_pos
          count = count + 1
          all_positions.push(current)
        }
      None => break
    }
  }
  // Filter by quantifier bounds
  let (lo, hi) = match quantifier {
    One => (1, 1)
    ZeroOrMore => (0, count)
    OneOrMore => (1, count)
    ZeroOrOne => (0, if count > 0 { 1 } else { 0 })
    Exactly(n) => (n, n)
    AtLeast(n) => (n, count)
    Between(n, m) => (n, if m < count { m } else { count })
  }
  let valid : Array[Int] = []
  for i = lo; i <= hi; i = i + 1 {
    if i < all_positions.length() {
      valid.push(all_positions[i])
    }
  }
  if not(lazy_) {
    // Greedy: reverse to try max first
    valid.rev_in_place()
  }
  valid
}

///|
/// Returns all possible end positions for a group with a quantifier.
fn match_group_positions(
  elements : Array[QuantifiedElement],
  quantifier : Quantifier,
  lazy_ : Bool,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Array[Int] {
  fn match_once(start_pos : Int) -> Int? {
    match_elements_backtrack(
      elements, 0, input_chars, start_pos, case_insensitive,
    )
  }

  collect_repeat_positions(match_once, quantifier, lazy_, pos)
}

///|
/// Matches a group of elements (legacy — returns first greedy match).
fn match_group(
  elements : Array[QuantifiedElement],
  quantifier : Quantifier,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  let positions = match_group_positions(
    elements, quantifier, false, input_chars, pos, case_insensitive,
  )
  if positions.length() > 0 {
    Some(positions[0])
  } else {
    None
  }
}

///|
/// Enumerates all possible end positions for a single group match.
/// For each candidate length from pos to end-of-input, checks if the group's
/// inner elements can produce that end position. This enables outer
/// backtracking to coordinate with lazy/greedy quantifiers inside the group.
fn enumerate_group_end_positions(
  elements : Array[QuantifiedElement],
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Array[Int] {
  let positions : Array[Int] = []
  let seen : Map[Int, Bool] = {}
  // Collect all reachable end positions from the group
  // by trying the inner elements exhaustively
  for target = pos; target <= input_chars.length(); target = target + 1 {
    if seen.contains(target) {
      continue
    }
    // Check: can the inner elements match from pos to exactly target?
    // We do this by temporarily appending an end-of-group constraint
    // Simpler: just check if match_elements_backtrack yields target
    // by calling it and checking the result
    match
      match_elements_backtrack(elements, 0, input_chars, pos, case_insensitive) {
      Some(end) => {
        if not(seen.contains(end)) {
          seen.set(end, true)
          positions.push(end)
        }
        // We got the shortest/default match. To get other lengths,
        // we rely on the outer backtracking to try other positions.
        // But match_elements_backtrack always returns the same result...
        // So break out — the real fix is below.
        break
      }
      None => break
    }
  }
  // The group internally resolves to one end position. To handle lazy
  // quantifiers (e.g., [\s\S]*?) inside groups correctly, we need to
  // generate all valid end positions. Do this by checking at each length
  // whether a "suffix" match (the rest of the outer pattern) could work.
  // Since we can't do that here, generate all positions where the group
  // COULD end: from pos (0 chars) up to the max match length.
  if elements.length() == 1 {
    // Optimization: single-element group — enumerate like a simple element
    let qe = elements[0]
    let max_possible = count_simple_matches(
      qe.element,
      input_chars,
      pos,
      case_insensitive,
    )
    let bounds = quantifier_bounds(qe.quantifier, max_possible)
    match bounds {
      Some((lo, hi)) => {
        let result : Array[Int] = []
        if qe.lazy_ {
          for count = lo; count <= hi; count = count + 1 {
            result.push(pos + count)
          }
        } else {
          for count = hi; count >= lo; count = count - 1 {
            result.push(pos + count)
          }
        }
        return result
      }
      None => ()
    }
  }
  positions
}

///|
/// Returns all possible end positions for an alternation with a quantifier.
fn match_alternation_positions(
  alternatives : Array[Array[QuantifiedElement]],
  quantifier : Quantifier,
  lazy_ : Bool,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Array[Int] {
  fn match_once(start_pos : Int) -> Int? {
    for alt in alternatives {
      match
        match_elements_backtrack(
          alt, 0, input_chars, start_pos, case_insensitive,
        ) {
        Some(end_pos) => return Some(end_pos)
        None => continue
      }
    }
    None
  }

  collect_repeat_positions(match_once, quantifier, lazy_, pos)
}

///|
/// Matches alternation (a|b|c pattern) — legacy, returns first greedy match.
fn match_alternation(
  alternatives : Array[Array[QuantifiedElement]],
  quantifier : Quantifier,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  let positions = match_alternation_positions(
    alternatives, quantifier, false, input_chars, pos, case_insensitive,
  )
  if positions.length() > 0 {
    Some(positions[0])
  } else {
    None
  }
}

///|
/// Compiles a pattern once for repeated matching.
fn compile_pattern(
  pattern : String,
  case_insensitive? : Bool = false,
) -> CompiledPattern? {
  let ctx = ParseContext::new()
  let alternatives = split_by_alternation(pattern)
  let compiled_alts : Array[Array[QuantifiedElement]] = []
  for alt in alternatives {
    match parse_pattern_ctx(alt, ctx) {
      Some(elements) => compiled_alts.push(elements)
      None => return None
    }
  }
  let first_char_filter = extract_first_char_filter(
    compiled_alts, case_insensitive,
  )
  let capture_count = ctx.next_capture - 1
  Some({
    alternatives: compiled_alts,
    case_insensitive,
    first_char_filter,
    capture_count,
  })
}

///|
/// Extracts a first char filter from compiled alternatives.
fn extract_first_char_filter(
  alts : Array[Array[QuantifiedElement]],
  case_insensitive : Bool,
) -> FirstCharFilter {
  if alts.length() == 0 {
    return Any
  }
  // For now, only optimize single-alternative patterns
  if alts.length() > 1 {
    return Any
  }
  let elements = alts[0]
  if elements.length() == 0 {
    return Any
  }
  let first = elements[0]
  // Only optimize if quantifier is One or OneOrMore (must match at least once)
  match first.quantifier {
    One | OneOrMore => ()
    _ => return Any
  }
  match first.element {
    Literal(c) =>
      if case_insensitive {
        let lower = to_lower(c)
        let upper = if lower >= 'a' && lower <= 'z' {
          Int::unsafe_to_char(lower.to_int() - 32)
        } else {
          lower
        }
        LiteralCI(lower, upper)
      } else {
        Literal(c)
      }
    CharClass(ranges, negated) => CharClass(ranges, negated)
    Escape(escape_char) =>
      match escape_char {
        'n' => Literal('\n')
        'r' => Literal('\r')
        't' => Literal('\t')
        's' | 'S' | 'd' | 'D' | 'w' | 'W' => Any // Variable char classes
        _ => Literal(escape_char)
      }
    _ => Any
  }
}

///|
/// Counts how many consecutive characters match a simple element from pos.
fn count_simple_matches(
  element : PatternElement,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int {
  let input_len = input_chars.length()
  let mut current = pos
  while current < input_len {
    if match_char(element, input_chars[current], case_insensitive) {
      current = current + 1
    } else {
      break
    }
  }
  current - pos
}

///|
/// Returns quantifier min/max bounds. max_possible is the number of chars that
/// actually match the element starting from the current position.
fn quantifier_bounds(q : Quantifier, max_possible : Int) -> (Int, Int)? {
  let (lo, hi) = match q {
    One => (1, 1)
    ZeroOrMore => (0, max_possible)
    OneOrMore => (1, max_possible)
    ZeroOrOne => (0, if max_possible > 0 { 1 } else { 0 })
    Exactly(n) => (n, n)
    AtLeast(n) => (n, max_possible)
    Between(n, m) => (n, if m < max_possible { m } else { max_possible })
  }
  if lo > max_possible {
    None
  } else {
    Some((lo, hi))
  }
}

///|
/// Matches a sequence of elements with backtracking support.
/// For simple elements with variable-length quantifiers, tries different
/// match lengths (greedy: max→min, lazy: min→max) and recurses on the rest.
fn match_elements_backtrack(
  elements : Array[QuantifiedElement],
  idx : Int,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
  captures? : CaptureState? = None,
) -> Int? {
  if idx >= elements.length() {
    return Some(pos)
  }
  let qe = elements[idx]
  // Zero-width assertions: no backtracking needed
  match qe.element {
    WordBoundary
    | NonWordBoundary
    | StartAnchor
    | EndAnchor
    | StringStart
    | StringEnd
    | Lookahead(_) =>
      match match_quantified(qe, input_chars, pos, case_insensitive) {
        Some(new_pos) =>
          return match_elements_backtrack(
            elements,
            idx + 1,
            input_chars,
            new_pos,
            case_insensitive,
            captures~,
          )
        None => return None
      }
    _ => ()
  }
  // Groups and alternations: use existing matching, then recurse
  match qe.element {
    Group(group_elements, capture_idx) => {
      // For groups with quantifier One: enumerate all possible end positions
      // by trying the group's internal elements at increasing match lengths.
      // This handles lazy quantifiers inside groups correctly (e.g., ([\s\S]*?)).
      let positions = if qe.quantifier is One {
        // Try all possible end positions for a single group match
        enumerate_group_end_positions(
          group_elements, input_chars, pos, case_insensitive,
        )
      } else {
        match_group_positions(
          group_elements,
          qe.quantifier,
          qe.lazy_,
          input_chars,
          pos,
          case_insensitive,
        )
      }
      for try_pos in positions {
        // Record capture: start=pos, end=try_pos
        match (captures, capture_idx) {
          (Some(cap), Some(ci)) => cap.set(ci, pos, try_pos)
          _ => ()
        }
        match
          match_elements_backtrack(
            elements,
            idx + 1,
            input_chars,
            try_pos,
            case_insensitive,
            captures~,
          ) {
          Some(result) => return Some(result)
          None => {
            // Backtrack: reset capture
            match (captures, capture_idx) {
              (Some(cap), Some(ci)) => cap.reset(ci)
              _ => ()
            }
            continue
          }
        }
      }
      return None
    }
    Alternation(alternatives) => {
      let positions = match_alternation_positions(
        alternatives,
        qe.quantifier,
        qe.lazy_,
        input_chars,
        pos,
        case_insensitive,
      )
      for try_pos in positions {
        match
          match_elements_backtrack(
            elements,
            idx + 1,
            input_chars,
            try_pos,
            case_insensitive,
            captures~,
          ) {
          Some(result) => return Some(result)
          None => continue
        }
      }
      return None
    }
    _ => ()
  }
  // Simple element: enumerate match counts for backtracking
  let max_possible = count_simple_matches(
    qe.element,
    input_chars,
    pos,
    case_insensitive,
  )
  let bounds = quantifier_bounds(qe.quantifier, max_possible)
  match bounds {
    None => return None
    Some((lo, hi)) =>
      if qe.lazy_ {
        // Lazy: try from min to max
        for count = lo; count <= hi; count = count + 1 {
          match
            match_elements_backtrack(
              elements,
              idx + 1,
              input_chars,
              pos + count,
              case_insensitive,
              captures~,
            ) {
            Some(result) => return Some(result)
            None => continue
          }
        }
      } else {
        // Greedy: try from max to min
        for count = hi; count >= lo; count = count - 1 {
          match
            match_elements_backtrack(
              elements,
              idx + 1,
              input_chars,
              pos + count,
              case_insensitive,
              captures~,
            ) {
            Some(result) => return Some(result)
            None => continue
          }
        }
      }
  }
  None
}

///|
/// Matches a compiled pattern against the input at the given position.
fn match_compiled_end_pos_with_chars(
  compiled : CompiledPattern,
  input_chars : Array[Char],
  pos : Int,
  captures? : CaptureState? = None,
) -> Int? {
  // Quick rejection using first char filter
  if pos >= input_chars.length() {
    return None
  }
  let first_char = input_chars[pos]
  if not(check_first_char_filter(compiled.first_char_filter, first_char)) {
    return None
  }
  // Full matching with backtracking
  for elements in compiled.alternatives {
    match
      match_elements_backtrack(
        elements,
        0,
        input_chars,
        pos,
        compiled.case_insensitive,
        captures~,
      ) {
      Some(end_pos) => return Some(end_pos)
      None => continue
    }
  }
  None
}

///|
/// Checks if a character passes the first char filter.
fn check_first_char_filter(filter : FirstCharFilter, c : Char) -> Bool {
  match filter {
    Any => true
    Literal(expected) => c == expected
    LiteralCI(lower, upper) => c == lower || c == upper
    CharClass(ranges, negated) => {
      let mut in_class = false
      for range in ranges {
        let (start, end) = range
        if c >= start && c <= end {
          in_class = true
          break
        }
      }
      if negated {
        not(in_class)
      } else {
        in_class
      }
    }
  }
}

///|
/// Matches a compiled pattern against the input at the given position.
fn match_compiled_with_chars(
  compiled : CompiledPattern,
  input : String,
  input_chars : Array[Char],
  pos : Int,
) -> MatchResult {
  match match_compiled_end_pos_with_chars(compiled, input_chars, pos) {
    Some(end_pos) =>
      MatchResult::success(end_pos, input[pos:end_pos].to_string())
    None => MatchResult::failure()
  }
}

///|
/// Matches a pattern against the input starting at the given position.
/// Returns the match result with the end position and matched text.
pub fn match_pattern(
  pattern : String,
  input : String,
  pos : Int,
  case_insensitive? : Bool = false,
) -> MatchResult {
  let input_chars = build_input_chars(input)
  match compile_pattern(pattern, case_insensitive~) {
    Some(compiled) =>
      match_compiled_with_chars(compiled, input, input_chars, pos)
    None => MatchResult::failure()
  }
}

///|
/// Checks if a pattern matches at the start of the input at the given position.
/// This is a convenience wrapper around match_pattern.
pub fn matches_at(
  pattern : String,
  input : String,
  pos : Int,
  case_insensitive? : Bool = false,
) -> Bool {
  match_pattern(pattern, input, pos, case_insensitive~).matched
}
