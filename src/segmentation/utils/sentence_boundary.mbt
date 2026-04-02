// Sentence boundary detection utilities.
// Supports both Japanese and English punctuation with Japanese quote protection.

///|
/// Check if a character is a sentence terminator.
/// Includes Japanese and English punctuation.
pub fn is_sentence_terminator(c : Char) -> Bool {
  // Japanese terminators
  c == '。' ||
  c == '！' ||
  c == '？' ||
  c == '．' ||
  // English terminators
  c == '.' ||
  c == '!' ||
  c == '?'
}

///|
/// Check if a character is trailing punctuation that follows a terminator.
/// These characters should not cause a split after a terminator.
pub fn is_trailing_punctuation(c : Char) -> Bool {
  // Terminators (can repeat)
  is_sentence_terminator(c) ||
  // Japanese closing brackets
  c == '」' ||
  c == '』' ||
  c == '）' ||
  c == '】' ||
  c == '〉' ||
  c == '》' ||
  // English closing brackets and quotes
  c == '"' ||
  c == '\'' ||
  c == ')' ||
  c == ']' ||
  // Whitespace
  c == '\n' ||
  c == ' '
}

///|
/// Check if a character is an extended terminator (includes closing brackets).
pub fn is_extended_terminator(c : Char) -> Bool {
  is_sentence_terminator(c) ||
  // Japanese closing brackets
  c == '」' ||
  c == '』' ||
  c == '）' ||
  c == '】' ||
  c == '〉' ||
  c == '》' ||
  // English closing brackets and quotes
  c == '"' ||
  c == '\'' ||
  c == ')' ||
  c == ']'
}

///|
/// Get the matching closing quote for an opening quote.
/// Returns None if not an opening quote.
fn get_closing_quote(c : Char) -> Char? {
  match c {
    '「' => Some('」')
    '『' => Some('』')
    _ => None
  }
}

///|
/// Get the matching opening quote for a closing quote.
/// Returns None if not a closing quote.
fn get_opening_quote(c : Char) -> Char? {
  match c {
    '」' => Some('「')
    '』' => Some('『')
    _ => None
  }
}

///|
/// Update the quote stack state for one character.
/// Opening quote => push to stack.
/// Matching closing quote => pop from stack.
pub fn update_quote_stack(
  stack : Array[QuoteStackEntry],
  c : Char,
  index : Int,
) -> Unit {
  // Check if this is an opening quote
  match get_closing_quote(c) {
    Some(_) => {
      stack.push(QuoteStackEntry::new(c, index))
      return
    }
    None => ()
  }
  // Check if this is a closing quote
  match get_opening_quote(c) {
    Some(matching_open) =>
      // Check if top of stack matches
      if stack.length() > 0 {
        let last = stack[stack.length() - 1]
        if last.get_open() == matching_open {
          let _ = stack.pop()
        }
      }
    None => ()
  }
}

///|
/// Build quote stack state up to end_pos (exclusive).
pub fn build_quote_stack_until(
  text : String,
  end_pos : Int,
) -> Array[QuoteStackEntry] {
  let stack : Array[QuoteStackEntry] = []
  let chars = text.to_array()
  let limit = if end_pos < chars.length() { end_pos } else { chars.length() }
  for i = 0; i < limit; i = i + 1 {
    update_quote_stack(stack, chars[i], i)
  }
  stack
}

///|
/// Check if currently inside a protected quote (under max length).
pub fn is_inside_protected_quote(
  stack : Array[QuoteStackEntry],
  index : Int,
  max_length : Int,
) -> Bool {
  if stack.length() == 0 {
    return false
  }
  let current = stack[stack.length() - 1]
  index - current.get_start() < max_length
}

///|
/// Find sentence boundary positions in text.
/// Returns array of end positions (exclusive) for each sentence.
pub fn find_sentence_boundaries(
  text : String,
  options : FindBoundariesOptions,
) -> Array[Int] {
  let chars = text.to_array()
  let boundaries : Array[Int] = []
  let quote_stack : Array[QuoteStackEntry] = []
  let mut i = 0

  while i < chars.length() {
    let c = chars[i]

    // Update quote state if respecting Japanese quotes
    if options.get_respect_japanese_quotes() {
      update_quote_stack(quote_stack, c, i)
    }

    // Check if inside protected quote
    let is_protected = options.get_respect_japanese_quotes() &&
      is_inside_protected_quote(
        quote_stack,
        i,
        options.get_quote_safe_max_length(),
      )

    // Determine if this is a terminator
    let is_term = if options.get_include_closing_brackets() {
      is_extended_terminator(c)
    } else {
      is_sentence_terminator(c)
    }

    if is_term && !(is_protected) {
      // Consume all trailing punctuation
      let mut end_pos = i + 1
      while end_pos < chars.length() && is_trailing_punctuation(chars[end_pos]) {
        end_pos = end_pos + 1
      }
      boundaries.push(end_pos)
      i = end_pos
    } else {
      i = i + 1
    }
  }

  boundaries
}

///|
/// Find sentence boundaries with default options.
pub fn find_sentence_boundaries_default(text : String) -> Array[Int] {
  find_sentence_boundaries(text, FindBoundariesOptions::new())
}

///|
/// Find the next sentence boundary from a given position.
/// Returns end position of the next sentence, or text.length() if none found.
pub fn find_next_boundary(
  text : String,
  from_pos : Int,
  options : FindBoundariesOptions,
) -> Int {
  let chars = text.to_array()

  // Build quote stack up to from_pos
  let quote_stack = if options.get_respect_japanese_quotes() {
    build_quote_stack_until(text, from_pos)
  } else {
    []
  }

  let mut i = from_pos
  while i < chars.length() {
    let c = chars[i]

    // Update quote state if respecting Japanese quotes
    if options.get_respect_japanese_quotes() {
      update_quote_stack(quote_stack, c, i)
    }

    // Check if inside protected quote
    let is_protected = options.get_respect_japanese_quotes() &&
      is_inside_protected_quote(
        quote_stack,
        i,
        options.get_quote_safe_max_length(),
      )

    // Determine if this is a terminator
    let is_term = if options.get_include_closing_brackets() {
      is_extended_terminator(c)
    } else {
      is_sentence_terminator(c)
    }

    if is_term && !(is_protected) {
      // Consume all trailing punctuation
      let mut end_pos = i + 1
      while end_pos < chars.length() && is_trailing_punctuation(chars[end_pos]) {
        end_pos = end_pos + 1
      }
      return end_pos
    }
    i = i + 1
  }

  chars.length()
}

///|
/// Find the next sentence boundary with default options.
pub fn find_next_boundary_default(text : String, from_pos : Int) -> Int {
  find_next_boundary(text, from_pos, FindBoundariesOptions::new())
}

///|
/// Check if a position is at a sentence boundary.
/// Returns true if the position is immediately after trailing punctuation.
pub fn is_at_boundary(text : String, pos : Int) -> Bool {
  if pos <= 0 || pos > text.length() {
    return false
  }
  let chars = text.to_array()
  let prev_char = chars[pos - 1]
  is_trailing_punctuation(prev_char)
}
