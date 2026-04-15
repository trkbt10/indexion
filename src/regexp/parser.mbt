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
            // Consistent with Escape('S') which uses !(is_whitespace(c))
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
  if !has_n {
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
        // Lookahead -- zero-width assertion
        if is_pos_lookahead || is_neg_lookahead {
          match parse_pattern_ctx(group_pattern, ctx) {
            Some(elems) => (Lookahead(elems, is_pos_lookahead), group_end + 1)
            None => return None
          }
        } else if is_non_capturing {
          // Non-capturing group: (?:...) -- no capture index
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
          // Capturing group: (...) -- allocate capture index
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
/// Finds the first consuming element in an element sequence,
/// skipping zero-width assertions (anchors, boundaries, lookaheads).
fn find_first_consuming_element(
  elements : Array[QuantifiedElement],
) -> QuantifiedElement? {
  for qe in elements {
    match qe.element {
      WordBoundary
      | NonWordBoundary
      | StartAnchor
      | EndAnchor
      | StringStart
      | StringEnd
      | Lookahead(_) => continue
      _ => return Some(qe)
    }
  }
  None
}

///|
/// Extracts first char ranges from a single alternative's first consuming element.
/// Returns None if the element can match any character (not filterable).
fn extract_first_char_ranges(
  elements : Array[QuantifiedElement],
  case_insensitive : Bool,
) -> Array[(Char, Char)]? {
  let first = match find_first_consuming_element(elements) {
    Some(qe) => qe
    None => return None
  }
  // Only optimize if quantifier requires at least one match
  match first.quantifier {
    One | OneOrMore | Exactly(_) | AtLeast(_) | Between(_, _) => ()
    _ => return None
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
        if lower == upper {
          Some([(lower, lower)])
        } else {
          Some([(lower, lower), (upper, upper)])
        }
      } else {
        Some([(c, c)])
      }
    CharClass(ranges, negated) =>
      if negated {
        None // Negated classes are hard to merge
      } else {
        Some(ranges)
      }
    Escape(escape_char) =>
      match escape_char {
        'n' => Some([('\n', '\n')])
        'r' => Some([('\r', '\r')])
        't' => Some([('\t', '\t')])
        'd' => Some([('0', '9')])
        'w' => Some([('A', 'Z'), ('a', 'z'), ('0', '9'), ('_', '_')])
        's' => Some([(' ', ' '), ('\t', '\t'), ('\n', '\n'), ('\r', '\r')])
        'S' | 'D' | 'W' => None // Negated classes span too many ranges
        _ => Some([(escape_char, escape_char)])
      }
    // Alternation at the top of a single-alternative pattern
    // e.g., (?:pub|fn|let) compiles to Alternation([...]) as first element
    Alternation(inner_alts) => {
      let merged : Array[(Char, Char)] = []
      for alt in inner_alts {
        match extract_first_char_ranges(alt, case_insensitive) {
          Some(ranges) =>
            for r in ranges {
              merged.push(r)
            }
          None => return None
        }
      }
      Some(merged)
    }
    _ => None
  }
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
  // Collect first char ranges from all alternatives
  let all_ranges : Array[(Char, Char)] = []
  for alt in alts {
    match extract_first_char_ranges(alt, case_insensitive) {
      Some(ranges) =>
        for r in ranges {
          all_ranges.push(r)
        }
      None => return Any
    }
  }
  if all_ranges.length() == 0 {
    return Any
  }
  // Optimize: single literal char
  if all_ranges.length() == 1 {
    let (lo, hi) = all_ranges[0]
    if lo == hi {
      return Literal(lo)
    }
  }
  // Optimize: case-insensitive single char (two ranges: lower, upper)
  if all_ranges.length() == 2 {
    let (lo1, hi1) = all_ranges[0]
    let (lo2, hi2) = all_ranges[1]
    if lo1 == hi1 && lo2 == hi2 {
      return LiteralCI(lo1, lo2)
    }
  }
  CharClass(all_ranges, false)
}
