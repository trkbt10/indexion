///|
/// Lexer transforms input text into tokens based on token definitions.
pub struct Lexer {
  tokens : Array[CompiledToken]
}

///|
/// Compiled token matcher used by the lexer hot path.
struct CompiledToken {
  token_def : @types.TokenDef
  compiled_pattern : @regexp.CompiledPattern?
}

///|
/// Creates a new Lexer with the given token definitions.
/// Token definitions are tried in order, so more specific patterns should come first.
pub fn Lexer::new(tokens : Array[@types.TokenDef]) -> Lexer {
  let compiled_tokens : Array[CompiledToken] = []
  for token_def in tokens {
    let case_insensitive = has_case_insensitive_flag(token_def.flags)
    let compiled_pattern = @regexp.compile_pattern(
      token_def.pattern,
      case_insensitive~,
    )
    compiled_tokens.push({ token_def, compiled_pattern })
  }
  { tokens: compiled_tokens }
}

///|
/// Tokenizes the input string and returns an array of tokens.
/// Skipped tokens (like whitespace) are not included in the result.
pub fn Lexer::tokenize(self : Lexer, input : String) -> Array[@types.Tok] {
  let result : Array[@types.Tok] = []
  let input_chars = @regexp.build_input_chars(input)
  let mut pos = 0
  while pos < input.length() {
    let match_result = self.try_match(input, input_chars, pos)
    match match_result {
      Some((token_def, end_pos, text, group1)) => {
        if !token_def.skip {
          match text {
            Some(token_text) => {
              // Capture group takes priority for value extraction
              let value = match group1 {
                Some(captured) => Some(captured)
                None => extract_value(token_text, token_def)
              }
              result.push(
                @types.Tok::new(token_def.name, token_text, pos, value~),
              )
            }
            None => ()
          }
        }
        pos = end_pos
      }
      None =>
        // No token matched, skip one character
        pos = pos + 1
    }
  }
  result
}

///|
/// Tries to match a token at the given position.
/// Returns the matched token definition, end position, matched text, and first capture group.
fn Lexer::try_match(
  self : Lexer,
  input : String,
  input_chars : Array[Char],
  pos : Int,
) -> (@types.TokenDef, Int, String?, String?)? {
  for entry in self.tokens {
    let token_def = entry.token_def
    let compiled = match entry.compiled_pattern {
      Some(c) => c
      None => continue
    }
    // Create capture state if pattern has capture groups
    let captures = if compiled.get_capture_count() > 0 {
      Some(@regexp.CaptureState::new(compiled.get_capture_count()))
    } else {
      None
    }
    let end_pos = @regexp.match_compiled_end_pos_with_chars(
      compiled,
      input_chars,
      pos,
      captures~,
    )
    match end_pos {
      Some(end_pos_value) =>
        if end_pos_value > pos {
          if token_def.skip {
            return Some((token_def, end_pos_value, None, None))
          } else {
            let text = input[pos:end_pos_value].to_string()
            // Extract first capture group text
            let group1 = match captures {
              Some(cap) => cap.get_group_text(1, input_chars)
              None => None
            }
            return Some((token_def, end_pos_value, Some(text), group1))
          }
        }
      None => ()
    }
  }
  None
}

///|
/// Returns true when regex flags include case-insensitive matching.
fn has_case_insensitive_flag(flags : String?) -> Bool {
  match flags {
    Some(value) => value.contains("i")
    None => false
  }
}

///|
/// Extracts the value from a token text using token definition settings.
/// Handles: skip_value and quoted strings.
/// Capture groups are handled separately in tokenize().
fn extract_value(text : String, token_def : @types.TokenDef) -> String? {
  // skip_value: return empty string (for marker tokens like ///|)
  if token_def.is_skip_value() {
    return Some("")
  }
  // Handle quoted strings
  extract_quoted_value(text)
}

///|
/// Extracts the value from a token text.
/// For quoted strings, strips the surrounding quotes.
fn extract_quoted_value(text : String) -> String? {
  if text.length() >= 2 {
    let first = text[0].to_int().unsafe_to_char()
    let last = text[text.length() - 1].to_int().unsafe_to_char()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return Some(text[1:text.length() - 1].to_string())
    }
  }
  None
}

///|
/// Creates a lexer builder for fluent API usage.
pub fn lexer() -> LexerBuilder {
  LexerBuilder::new()
}

///|
/// Builder for constructing a Lexer with token definitions.
pub struct LexerBuilder {
  tokens : Array[@types.TokenDef]
}

///|
/// Creates a new LexerBuilder.
pub fn LexerBuilder::new() -> LexerBuilder {
  { tokens: [] }
}

///|
/// Adds a token definition to the builder.
pub fn LexerBuilder::token(
  self : LexerBuilder,
  name : String,
  pattern : String,
  skip? : Bool = false,
  flags? : String? = None,
) -> LexerBuilder {
  self.tokens.push(@types.TokenDef::new(name, pattern, skip~, flags~))
  self
}

///|
/// Adds a skip token (like whitespace) to the builder.
pub fn LexerBuilder::skip(
  self : LexerBuilder,
  name : String,
  pattern : String,
) -> LexerBuilder {
  self.token(name, pattern, skip=true)
}

///|
/// Builds the lexer from the accumulated token definitions.
pub fn LexerBuilder::build(self : LexerBuilder) -> Lexer {
  Lexer::new(self.tokens)
}
