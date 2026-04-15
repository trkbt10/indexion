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
        'S' => !is_whitespace(c)
        'd' => is_digit(c)
        'D' => !is_digit(c)
        'w' => is_word_char(c)
        'W' => !is_word_char(c)
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
        !in_class
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
      if !is_at_word_boundary_with_chars(input_chars, pos) {
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
/// Checks if a PatternElement can be matched with match_char (single char, no recursion).
fn is_simple_element(e : PatternElement) -> Bool {
  match e {
    Literal(_) | CharClass(_, _) | AnyChar | Escape(_) => true
    _ => false
  }
}

///|
/// Returns the fixed character width of a simple-element sequence,
/// or None if any element is non-simple or has a non-One quantifier.
fn sequence_fixed_width(elements : Array[QuantifiedElement]) -> Int? {
  let mut width = 0
  for qe in elements {
    guard qe.quantifier is One else { return None }
    guard is_simple_element(qe.element) else { return None }
    width = width + 1
  }
  Some(width)
}

///|
/// Matches a fixed-width sequence of simple elements without recursion.
fn try_match_simple_sequence(
  elements : Array[QuantifiedElement],
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Int? {
  let input_len = input_chars.length()
  let mut current = pos
  for qe in elements {
    if current >= input_len {
      return None
    }
    if match_char(qe.element, input_chars[current], case_insensitive) {
      current = current + 1
    } else {
      return None
    }
  }
  Some(current)
}

///|
/// Fast path for repeated alternation: (A|B|C)* or (A|B|C)+
/// where each alternative is a fixed-width sequence of simple elements.
///
/// Instead of calling match_elements_backtrack recursively for each
/// repetition step, this matches directly in a flat loop.
///
/// Returns None if any alternative is not amenable (caller falls
/// through to the generic backtracking path).
fn try_collect_repeat_positions_fast(
  alternatives : Array[Array[QuantifiedElement]],
  quantifier : Quantifier,
  lazy_ : Bool,
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Array[Int]? {
  // Verify all alternatives are fixed-width simple sequences
  let alt_widths : Array[Int] = []
  for alt in alternatives {
    match sequence_fixed_width(alt) {
      Some(w) => {
        if w == 0 {
          return None // Zero-width would loop forever
        }
        alt_widths.push(w)
      }
      None => return None
    }
  }
  // All simple -- run a greedy loop inline
  let max_repeats = match quantifier {
    Between(_, m) => m
    Exactly(n) => n
    _ => 2147483647
  }
  let all_positions : Array[Int] = [pos]
  let mut current = pos
  let mut count = 0
  while count < max_repeats {
    let mut matched = false
    for i, alt in alternatives {
      let width = alt_widths[i]
      if current + width > input_chars.length() {
        continue
      }
      match
        try_match_simple_sequence(alt, input_chars, current, case_insensitive) {
        Some(end_pos) => {
          current = end_pos
          count = count + 1
          all_positions.push(current)
          matched = true
          break
        }
        None => continue
      }
    }
    if !matched {
      break
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
  if !lazy_ {
    valid.rev_in_place()
  }
  Some(valid)
}

///|
/// Collects all valid end positions for a repeated match_once function.
/// Returns positions ordered for backtracking (greedy: max->min, lazy: min->max).
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
  if !lazy_ {
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
  // Fast path: group contains a single Alternation with quantifier One,
  // and all alternatives are fixed-width simple sequences.
  if elements.length() == 1 {
    let qe = elements[0]
    match (qe.element, qe.quantifier) {
      (Alternation(alternatives), One) =>
        match
          try_collect_repeat_positions_fast(
            alternatives, quantifier, lazy_, input_chars, pos, case_insensitive,
          ) {
          Some(positions) => return positions
          None => ()
        }
      _ => ()
    }
  }
  // Fast path: all elements form a fixed-width simple sequence.
  match sequence_fixed_width(elements) {
    Some(width) =>
      if width > 0 {
        match
          try_collect_repeat_positions_fast(
            [elements],
            quantifier,
            lazy_,
            input_chars,
            pos,
            case_insensitive,
          ) {
          Some(positions) => return positions
          None => ()
        }
      }
    None => ()
  }
  // Generic path: recursive backtracking.
  fn match_once(start_pos : Int) -> Int? {
    match_elements_backtrack(
      elements, 0, input_chars, start_pos, case_insensitive,
    )
  }

  collect_repeat_positions(match_once, quantifier, lazy_, pos)
}

///|
/// Matches a group of elements (legacy -- returns first greedy match).
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
fn enumerate_group_end_positions(
  elements : Array[QuantifiedElement],
  input_chars : Array[Char],
  pos : Int,
  case_insensitive : Bool,
) -> Array[Int] {
  let positions : Array[Int] = []
  let seen : Map[Int, Bool] = {}
  for target = pos; target <= input_chars.length(); target = target + 1 {
    if seen.contains(target) {
      continue
    }
    match
      match_elements_backtrack(elements, 0, input_chars, pos, case_insensitive) {
      Some(end) => {
        if !seen.contains(end) {
          seen.set(end, true)
          positions.push(end)
        }
        break
      }
      None => break
    }
  }
  if elements.length() == 1 {
    // Optimization: single-element group -- enumerate like a simple element
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
  // Fast path: all alternatives are fixed-width simple sequences.
  match
    try_collect_repeat_positions_fast(
      alternatives, quantifier, lazy_, input_chars, pos, case_insensitive,
    ) {
    Some(positions) => return positions
    None => ()
  }
  // Generic path: recursive backtracking.
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
/// Matches alternation (a|b|c pattern) -- legacy, returns first greedy match.
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
/// match lengths (greedy: max->min, lazy: min->max) and recurses on the rest.
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
        // Fast path for lazy quantifier: if the next element is a Literal,
        // scan ahead for it instead of trying every position.
        let next_literal = if idx + 1 < elements.length() {
          match elements[idx + 1].element {
            Literal(c) => Some(c)
            Escape(escape_char) =>
              match escape_char {
                'n' => Some('\n')
                'r' => Some('\r')
                't' => Some('\t')
                // Character classes (\s, \d, \w, \S, \D, \W) are NOT single literals
                's' | 'S' | 'd' | 'D' | 'w' | 'W' => None
                _ => Some(escape_char) // Escaped punctuation: \*, \., \/ etc.
              }
            _ => None
          }
        } else {
          None
        }
        match next_literal {
          Some(target_char) => {
            // Skip ahead: only try positions where target_char occurs
            let ci = case_insensitive
            let target_lower = if ci {
              to_lower(target_char)
            } else {
              target_char
            }
            let input_len = input_chars.length()
            let mut count = lo
            while count <= hi {
              let try_pos = pos + count
              if try_pos >= input_len {
                break
              }
              let ch = input_chars[try_pos]
              let matches_target = if ci {
                to_lower(ch) == target_lower
              } else {
                ch == target_char
              }
              if matches_target {
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
                  None => ()
                }
              }
              count += 1
            }
          }
          None =>
            // Generic lazy: try from min to max
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
        }
      } else {
        // Fast path for greedy quantifier: if the next element is a Literal,
        // scan backward for it instead of trying every position.
        let next_literal_greedy = if idx + 1 < elements.length() {
          match elements[idx + 1].element {
            Literal(c) => Some(c)
            Escape(escape_char) =>
              match escape_char {
                'n' => Some('\n')
                'r' => Some('\r')
                't' => Some('\t')
                // Character classes (\s, \d, \w, \S, \D, \W) are NOT single literals
                's' | 'S' | 'd' | 'D' | 'w' | 'W' => None
                _ => Some(escape_char) // Escaped punctuation: \*, \., \/ etc.
              }
            _ => None
          }
        } else {
          None
        }
        match next_literal_greedy {
          Some(target_char) => {
            // Only try positions where target_char occurs
            let ci = case_insensitive
            let target_lower = if ci {
              to_lower(target_char)
            } else {
              target_char
            }
            let input_len = input_chars.length()
            let mut count = hi
            while count >= lo {
              let try_pos = pos + count
              if try_pos >= input_len {
                count -= 1
                continue
              }
              let ch = input_chars[try_pos]
              let matches_target = if ci {
                to_lower(ch) == target_lower
              } else {
                ch == target_char
              }
              if matches_target {
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
                  None => ()
                }
              }
              count -= 1
            }
          }
          None =>
            // Generic greedy: try from max to min
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
        !in_class
      } else {
        in_class
      }
    }
  }
}

///|
/// Matches a compiled pattern against the input at the given position.
pub fn match_compiled_end_pos_with_chars(
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
  if !check_first_char_filter(compiled.first_char_filter, first_char) {
    return None
  }
  // Quick rejection for patterns requiring word boundary at start
  if compiled.requires_word_boundary_start &&
    !is_at_word_boundary_with_chars(input_chars, pos) {
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
