// Sentence splitting functionality.
// Splits text into sentences based on punctuation marks.
// Supports quote protection for Japanese and English quotes.

///|
/// Default maximum length protected from punctuation splitting inside quotes.
/// If quoted content exceeds this length, punctuation-based boundaries are allowed.
pub let default_quote_safe_max_length : Int = 240

///|
/// Options for sentence splitting.
pub struct SplitOptions {
  /// When true, punctuation inside quotes is not treated as a boundary
  /// unless quote length exceeds quote_safe_max_length.
  /// Default: true
  quote_protection : Bool
  /// Maximum protected quote length.
  /// Default: 240
  quote_safe_max_length : Int
  /// When true, closing brackets are also considered sentence terminators.
  /// Default: false
  include_closing_brackets : Bool
} derive(Eq, Debug)

///|
/// Create default SplitOptions.
pub fn SplitOptions::default() -> SplitOptions {
  {
    quote_protection: true,
    quote_safe_max_length: default_quote_safe_max_length,
    include_closing_brackets: false,
  }
}

///|
/// Entry on the quote stack for tracking nested quotes.
priv struct QuoteStackEntry {
  /// The opening quote character.
  open : Char
  /// The position where the quote started.
  start : Int
}

///|
/// Check if a character is a newline.
fn is_newline(c : Char) -> Bool {
  c == '\n' || c == '\r'
}

///|
/// Check if a character is whitespace.
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '　'
}

///|
/// Check if a character is an opening quote (Japanese only for reliable protection).
/// Note: English ASCII quotes (" and ') are ambiguous (same char for open/close),
/// so we only protect Japanese quotes for reliable behavior.
fn is_opening_quote(c : Char) -> Bool {
  c == '「' || c == '『'
}

///|
/// Check if a character is a closing quote (Japanese only for reliable protection).
fn is_closing_quote(c : Char) -> Bool {
  c == '」' || c == '』'
}

///|
/// Get the matching opening quote for a closing quote.
fn get_opening_quote(close : Char) -> Char {
  match close {
    '」' => '「'
    '』' => '『'
    _ => close // Should not happen
  }
}

///|
/// Update the quote stack based on the current character.
/// Opening quote => push to stack.
/// Matching closing quote => pop from stack.
fn update_quote_stack(
  stack : Array[QuoteStackEntry],
  c : Char,
  index : Int,
) -> Unit {
  if is_opening_quote(c) {
    stack.push({ open: c, start: index })
    return
  }
  if is_closing_quote(c) {
    let matching_open = get_opening_quote(c)
    if stack.length() > 0 {
      let last = stack[stack.length() - 1]
      if last.open == matching_open {
        let _ = stack.pop()
      }
    }
  }
}

///|
/// Check if currently inside a protected quote (under max length).
fn is_inside_protected_quote(
  stack : Array[QuoteStackEntry],
  index : Int,
  max_length : Int,
) -> Bool {
  if stack.length() == 0 {
    return false
  }
  let current = stack[stack.length() - 1]
  index - current.start < max_length
}

///|
/// Split text into sentences with default options (quote protection enabled).
///
/// Handles:
/// - English sentence endings: `.` `!` `?`
/// - Japanese sentence endings: `。` `！` `？` `．`
/// - Newlines as sentence breaks
/// - Consecutive punctuation marks
/// - Quote protection: punctuation inside quotes does not split sentences
pub fn split_sentences(text : String) -> Array[Sentence] {
  split_sentences_with_options(text, SplitOptions::default())
}

///|
/// Split text into sentences with custom options.
///
/// Handles:
/// - English sentence endings: `.` `!` `?`
/// - Japanese sentence endings: `。` `！` `？` `．`
/// - Newlines as sentence breaks
/// - Consecutive punctuation marks
/// - Quote protection (configurable): punctuation inside quotes does not split sentences
pub fn split_sentences_with_options(
  text : String,
  options : SplitOptions,
) -> Array[Sentence] {
  let sentences : Array[Sentence] = []

  if text.length() == 0 {
    return sentences
  }

  let chars = text.to_array()
  let len = chars.length()
  let mut current_start = 0
  let mut i = 0
  let quote_stack : Array[QuoteStackEntry] = []

  // Skip leading whitespace
  while i < len && is_whitespace(chars[i]) {
    i = i + 1
    current_start = i
  }

  while i < len {
    let c = chars[i]

    // Update quote state first so closing quote can be a valid boundary
    if options.quote_protection {
      update_quote_stack(quote_stack, c, i)
    }

    // Check if we're inside a protected quote
    let is_protected = options.quote_protection &&
      is_inside_protected_quote(quote_stack, i, options.quote_safe_max_length)

    // Check for sentence ending
    let is_end = if options.include_closing_brackets {
      @utils.is_extended_terminator(c)
    } else {
      @utils.is_sentence_terminator(c)
    }
    let is_nl = is_newline(c)

    if (is_end || is_nl) && !is_protected {
      // Include the punctuation in the sentence
      let mut end_pos = if is_end { i + 1 } else { i }

      // Consume all trailing punctuation
      while end_pos < len && @utils.is_trailing_punctuation(chars[end_pos]) {
        end_pos = end_pos + 1
      }

      // Extract sentence if we have content
      if i > current_start || (is_end && i >= current_start) {
        // Check if we have non-whitespace content
        let check_end = if is_end { i + 1 } else { i }
        let mut has_content = false
        for j = current_start; j < check_end; j = j + 1 {
          if !is_whitespace(chars[j]) {
            has_content = true
            break
          }
        }

        if has_content {
          let sentence_text = extract_substring(
            chars,
            current_start,
            if is_end {
              i + 1
            } else {
              i
            },
          )
          let trimmed = trim_string(sentence_text)
          if trimmed.length() > 0 {
            sentences.push(
              Sentence::new(
                trimmed,
                current_start,
                if is_end {
                  i + 1
                } else {
                  i
                },
              ),
            )
          }
        }
      }

      i = end_pos
      // Skip any remaining whitespace
      while i < len && is_whitespace(chars[i]) {
        i = i + 1
      }
      current_start = i
    } else {
      i = i + 1
    }
  }

  // Handle remaining text (sentence without ending punctuation)
  if current_start < len {
    let mut has_content = false
    for j = current_start; j < len; j = j + 1 {
      if !is_whitespace(chars[j]) {
        has_content = true
        break
      }
    }

    if has_content {
      let sentence_text = extract_substring(chars, current_start, len)
      let trimmed = trim_string(sentence_text)
      if trimmed.length() > 0 {
        sentences.push(Sentence::new(trimmed, current_start, len))
      }
    }
  }

  sentences
}

///|
/// Extract a substring from a character array.
fn extract_substring(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Trim whitespace from both ends of a string.
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()

  if len == 0 {
    return ""
  }

  // Find start (first non-whitespace)
  let mut start = 0
  while start < len && is_whitespace(chars[start]) {
    start = start + 1
  }

  // Find end (last non-whitespace)
  let mut end = len
  while end > start && is_whitespace(chars[end - 1]) {
    end = end - 1
  }

  if start >= end {
    return ""
  }

  extract_substring(chars, start, end)
}

///|
/// Split text into sentences and return only the text content.
pub fn split_sentences_text(text : String) -> Array[String] {
  split_sentences(text).map(fn(s) { s.text })
}

///|
/// Split text into sentences with custom options and return only the text content.
pub fn split_sentences_text_with_options(
  text : String,
  options : SplitOptions,
) -> Array[String] {
  split_sentences_with_options(text, options).map(fn(s) { s.text })
}

///|
/// Count the number of sentences in text.
pub fn count_sentences(text : String) -> Int {
  split_sentences(text).length()
}

///|
/// Count the number of sentences in text with custom options.
pub fn count_sentences_with_options(
  text : String,
  options : SplitOptions,
) -> Int {
  split_sentences_with_options(text, options).length()
}
