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
/// Checks if a character is an alphabetic character.
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// Checks if a character is a hex digit.
fn is_hex_digit(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// Parsed pattern element for internal use.
priv enum PatternElement {
  Literal(Char)
  CharClass(Array[(Char, Char)], Bool) // ranges, negated
  AnyChar // .
  Escape(Char) // \s, \w, \d, \S, \W, \D, etc.
  Group(Array[PatternElement])
  Alternation(Array[Array[PatternElement]])
}

///|
/// Quantifier type for pattern elements.
priv enum Quantifier {
  One
  ZeroOrMore // *
  OneOrMore // +
  ZeroOrOne // ?
}

///|
/// Pattern element with quantifier.
priv struct QuantifiedElement {
  element : PatternElement
  quantifier : Quantifier
}

///|
/// Gets a character from a string at the given index safely.
fn get_char_at(s : String, index : Int) -> Char? {
  if index >= 0 && index < s.length() {
    Some(Char::from_int(s[index].to_int()))
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
        // Escaped character
        pos = pos + 1
        match get_char_at(pattern, pos) {
          Some(c) => {
            ranges.push((c, c))
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
/// Parses the pattern string into a list of quantified elements.
fn parse_pattern(pattern : String) -> Array[QuantifiedElement]? {
  let elements : Array[QuantifiedElement] = []
  let mut pos = 0
  while pos < pattern.length() {
    let (element, new_pos) : (PatternElement, Int) = match
      get_char_at(pattern, pos) {
      Some('\\') =>
        // Escape sequence
        match get_char_at(pattern, pos + 1) {
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
        let group_start = pos + 1
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
        let group_pattern = pattern.substring(start=group_start, end=group_end)
        // Check for alternation in group
        if group_pattern.contains("|") {
          let alternatives = split_by_alternation(group_pattern)
          let parsed_alternatives : Array[Array[PatternElement]] = []
          for alt in alternatives {
            match parse_pattern(alt) {
              Some(elems) => {
                let simple_elems : Array[PatternElement] = []
                for e in elems {
                  // For simplicity, ignore quantifiers inside alternation for now
                  simple_elems.push(e.element)
                }
                parsed_alternatives.push(simple_elems)
              }
              None => return None
            }
          }
          (Alternation(parsed_alternatives), group_end + 1)
        } else {
          match parse_pattern(group_pattern) {
            Some(group_elems) => {
              let simple_elems : Array[PatternElement] = []
              for e in group_elems {
                simple_elems.push(e.element)
              }
              (Group(simple_elems), group_end + 1)
            }
            None => return None
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
    let quantifier = match get_char_at(pattern, pos) {
      Some('*') => {
        pos = pos + 1
        // Check for non-greedy
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
        }
        ZeroOrMore
      }
      Some('+') => {
        pos = pos + 1
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
        }
        OneOrMore
      }
      Some('?') => {
        pos = pos + 1
        if get_char_at(pattern, pos) == Some('?') {
          pos = pos + 1
        }
        ZeroOrOne
      }
      _ => One
    }
    elements.push({ element, quantifier })
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
          result.push(pattern.substring(start~, end=pos))
          start = pos + 1
        }
      _ => ()
    }
    pos = pos + 1
  }
  result.push(pattern.substring(start~, end=pattern.length()))
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
      for range in ranges {
        let (start, end) = range
        let ch = if case_insensitive { to_lower(c) } else { c }
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
    Group(_) | Alternation(_) => false // Should not be called directly
  }
}

///|
/// Converts a character to lowercase.
fn to_lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    Char::from_int(c.to_int() + 32)
  } else {
    c
  }
}

///|
/// Matches a quantified element against the input starting at pos.
/// Returns the end position if matched, or None if no match.
fn match_quantified(
  qe : QuantifiedElement,
  input : String,
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  match qe.element {
    Group(elements) =>
      match_group(elements, qe.quantifier, input, pos, case_insensitive)
    Alternation(alternatives) =>
      match_alternation(
        alternatives,
        qe.quantifier,
        input,
        pos,
        case_insensitive,
      )
    _ => match_simple(qe.element, qe.quantifier, input, pos, case_insensitive)
  }
}

///|
/// Matches a simple element (non-group) with quantifier.
fn match_simple(
  element : PatternElement,
  quantifier : Quantifier,
  input : String,
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  match quantifier {
    One =>
      match get_char_at(input, pos) {
        Some(c) =>
          if match_char(element, c, case_insensitive) {
            Some(pos + 1)
          } else {
            None
          }
        None => None
      }
    ZeroOrOne =>
      match get_char_at(input, pos) {
        Some(c) =>
          if match_char(element, c, case_insensitive) {
            Some(pos + 1)
          } else {
            Some(pos)
          }
        None => Some(pos)
      }
    ZeroOrMore => {
      let mut current = pos
      while true {
        match get_char_at(input, current) {
          Some(c) =>
            if match_char(element, c, case_insensitive) {
              current = current + 1
            } else {
              break
            }
          None => break
        }
      }
      Some(current)
    }
    OneOrMore =>
      match get_char_at(input, pos) {
        Some(c) =>
          if match_char(element, c, case_insensitive) {
            let mut current = pos + 1
            while true {
              match get_char_at(input, current) {
                Some(c2) =>
                  if match_char(element, c2, case_insensitive) {
                    current = current + 1
                  } else {
                    break
                  }
                None => break
              }
            }
            Some(current)
          } else {
            None
          }
        None => None
      }
  }
}

///|
/// Matches a group of elements.
fn match_group(
  elements : Array[PatternElement],
  quantifier : Quantifier,
  input : String,
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  fn match_group_once(start_pos : Int) -> Int? {
    let mut current = start_pos
    for elem in elements {
      match
        match_quantified(
          { element: elem, quantifier: One },
          input,
          current,
          case_insensitive,
        ) {
        Some(new_pos) => current = new_pos
        None => return None
      }
    }
    Some(current)
  }

  match quantifier {
    One => match_group_once(pos)
    ZeroOrOne =>
      match match_group_once(pos) {
        Some(end_pos) => Some(end_pos)
        None => Some(pos)
      }
    ZeroOrMore => {
      let mut current = pos
      while true {
        match match_group_once(current) {
          Some(new_pos) =>
            if new_pos == current {
              break
            } else {
              current = new_pos
            }
          None => break
        }
      }
      Some(current)
    }
    OneOrMore =>
      match match_group_once(pos) {
        Some(first_end) => {
          let mut current = first_end
          while true {
            match match_group_once(current) {
              Some(new_pos) =>
                if new_pos == current {
                  break
                } else {
                  current = new_pos
                }
              None => break
            }
          }
          Some(current)
        }
        None => None
      }
  }
}

///|
/// Matches alternation (a|b|c pattern).
fn match_alternation(
  alternatives : Array[Array[PatternElement]],
  quantifier : Quantifier,
  input : String,
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  fn match_alt_once(start_pos : Int) -> Int? {
    for alt in alternatives {
      let mut current = start_pos
      let mut matched = true
      for elem in alt {
        match
          match_quantified(
            { element: elem, quantifier: One },
            input,
            current,
            case_insensitive,
          ) {
          Some(new_pos) => current = new_pos
          None => {
            matched = false
            break
          }
        }
      }
      if matched {
        return Some(current)
      }
    }
    None
  }

  match quantifier {
    One => match_alt_once(pos)
    ZeroOrOne =>
      match match_alt_once(pos) {
        Some(end_pos) => Some(end_pos)
        None => Some(pos)
      }
    ZeroOrMore => {
      let mut current = pos
      while true {
        match match_alt_once(current) {
          Some(new_pos) =>
            if new_pos == current {
              break
            } else {
              current = new_pos
            }
          None => break
        }
      }
      Some(current)
    }
    OneOrMore =>
      match match_alt_once(pos) {
        Some(first_end) => {
          let mut current = first_end
          while true {
            match match_alt_once(current) {
              Some(new_pos) =>
                if new_pos == current {
                  break
                } else {
                  current = new_pos
                }
              None => break
            }
          }
          Some(current)
        }
        None => None
      }
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
  // Handle top-level alternation only if there are actual top-level alternations
  let alternatives = split_by_alternation(pattern)
  if alternatives.length() > 1 {
    for alt in alternatives {
      let result = match_pattern(alt, input, pos, case_insensitive~)
      if result.matched {
        return result
      }
    }
    return MatchResult::failure()
  }
  match parse_pattern(pattern) {
    None => MatchResult::failure()
    Some(elements) => {
      let mut current = pos
      for qe in elements {
        match match_quantified(qe, input, current, case_insensitive) {
          Some(new_pos) => current = new_pos
          None => return MatchResult::failure()
        }
      }
      MatchResult::success(current, input.substring(start=pos, end=current))
    }
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
