// Tokenizer for TF-IDF text processing.
// Supports mixed Japanese/English text without external morphological analyzers.

///|
/// Check if a character is a CJK (Chinese/Japanese/Korean) character.
fn is_cjk_char(c : Char) -> Bool {
  let code = c.to_int()
  // CJK Unified Ideographs
  (code >= 0x4E00 && code <= 0x9FFF) ||
  // CJK Unified Ideographs Extension A
  (code >= 0x3400 && code <= 0x4DBF) ||
  // Hiragana
  (code >= 0x3040 && code <= 0x309F) ||
  // Katakana
  (code >= 0x30A0 && code <= 0x30FF) ||
  // Hangul Syllables
  (code >= 0xAC00 && code <= 0xD7AF) ||
  // CJK Compatibility Ideographs
  (code >= 0xF900 && code <= 0xFAFF)
}

///|
/// Check if a character is a letter or digit (for word tokenization).
fn is_word_char(c : Char) -> Bool {
  let code = c.to_int()
  // ASCII letters
  (code >= 0x41 && code <= 0x5A) || // A-Z
  (code >= 0x61 && code <= 0x7A) || // a-z
  // ASCII digits
  (code >= 0x30 && code <= 0x39) || // 0-9
  // Underscore and hyphen
  code == 0x5F || // _
  code == 0x2D || // -
  // Extended Latin
  (code >= 0xC0 && code <= 0xFF) ||
  // CJK characters (included for word boundary detection)
  is_cjk_char(c)
}

///|
/// Convert a character to lowercase (ASCII only).
fn to_lower(c : Char) -> Char {
  let code = c.to_int()
  if code >= 0x41 && code <= 0x5A {
    // A-Z -> a-z
    (code + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// Normalize text for TF-IDF processing.
/// Converts to lowercase and normalizes whitespace.
pub fn normalize_text(text : String) -> String {
  let chars = text.to_array()
  let result : Array[Char] = []
  let mut last_was_space = true // Start true to trim leading space
  for c in chars {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      if not(last_was_space) {
        result.push(' ')
        last_was_space = true
      }
    } else {
      result.push(to_lower(c))
      last_was_space = false
    }
  }
  // Trim trailing space
  if result.length() > 0 && result[result.length() - 1] == ' ' {
    let _ = result.pop()
  }
  String::from_array(result)
}

///|
/// Extract word tokens from text.
/// Returns tokens of 2 or more characters.
pub fn extract_word_tokens(text : String) -> Array[String] {
  let chars = text.to_array()
  let tokens : Array[String] = []
  let current_word : Array[Char] = []
  for c in chars {
    if is_word_char(c) && not(is_cjk_char(c)) {
      // Only include non-CJK word characters
      current_word.push(c)
    } else {
      // End of word
      if current_word.length() >= 2 {
        tokens.push(String::from_array(current_word))
      }
      current_word.clear()
    }
  }
  // Handle last word
  if current_word.length() >= 2 {
    tokens.push(String::from_array(current_word))
  }
  tokens
}

///|
/// Extract character bigrams from text for CJK processing.
/// Removes whitespace before generating bigrams.
pub fn extract_character_bigrams(text : String) -> Array[String] {
  // Remove all whitespace
  let chars = text.to_array()
  let compact : Array[Char] = []
  for c in chars {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      compact.push(c)
    }
  }
  if compact.length() < 2 {
    if compact.length() == 0 {
      return []
    }
    return [String::from_array(compact)]
  }
  let tokens : Array[String] = []
  for i = 0; i < compact.length() - 1; i = i + 1 {
    let bigram : Array[Char] = [compact[i], compact[i + 1]]
    tokens.push(String::from_array(bigram))
  }
  tokens
}

///|
/// Tokenize text for TF-IDF vectorization.
/// Combines word tokens and character bigrams for mixed language support.
pub fn tokenize_for_tfidf(text : String) -> Array[String] {
  let normalized = normalize_text(text)
  if normalized.length() == 0 {
    return []
  }
  let words = extract_word_tokens(normalized)
  let bigrams = extract_character_bigrams(normalized)
  if words.length() == 0 {
    return bigrams
  }
  // Combine words and bigrams
  let result : Array[String] = []
  for w in words {
    result.push(w)
  }
  for b in bigrams {
    result.push(b)
  }
  result
}
