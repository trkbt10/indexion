///|
/// Lexer transforms input text into tokens based on token definitions.
pub struct Lexer {
  tokens : Array[CompiledToken]
}

///|
/// Compiled token matcher used by the lexer hot path.
struct CompiledToken {
  token_def : @types.TokenDef
  compiled_pattern : CompiledPattern?
}

///|
/// Creates a new Lexer with the given token definitions.
/// Token definitions are tried in order, so more specific patterns should come first.
pub fn Lexer::new(tokens : Array[@types.TokenDef]) -> Lexer {
  let compiled_tokens : Array[CompiledToken] = []
  for token_def in tokens {
    let case_insensitive = has_case_insensitive_flag(token_def.flags)
    let compiled_pattern = compile_pattern(token_def.pattern, case_insensitive~)
    compiled_tokens.push({ token_def, compiled_pattern })
  }
  { tokens: compiled_tokens }
}

///|
/// Tokenizes the input string and returns an array of tokens.
/// Skipped tokens (like whitespace) are not included in the result.
pub fn Lexer::tokenize(self : Lexer, input : String) -> Array[@types.Tok] {
  let result : Array[@types.Tok] = []
  let input_chars = build_input_chars(input)
  let mut pos = 0
  while pos < input.length() {
    let match_result = self.try_match(input, input_chars, pos)
    match match_result {
      Some((token_def, end_pos, text)) => {
        if not(token_def.skip) {
          match text {
            Some(token_text) => {
              let value = extract_value(token_text)
              result.push(
                @types.Tok::new(token_def.name, token_text, pos, value~),
              )
            }
            // Non-skip tokens always produce text; keep behavior robust on mismatch.
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
/// Returns the matched token definition, end position, and matched text.
fn Lexer::try_match(
  self : Lexer,
  input : String,
  input_chars : Array[Char],
  pos : Int,
) -> (@types.TokenDef, Int, String?)? {
  for entry in self.tokens {
    let token_def = entry.token_def
    let end_pos = match entry.compiled_pattern {
      Some(compiled) =>
        match_compiled_end_pos_with_chars(compiled, input_chars, pos)
      // If compile failed at lexer construction time, this token can never match.
      None => continue
    }
    match end_pos {
      Some(end_pos_value) =>
        if end_pos_value > pos {
          if token_def.skip {
            return Some((token_def, end_pos_value, None))
          } else {
            let text = input.substring(start=pos, end=end_pos_value)
            return Some((token_def, end_pos_value, Some(text)))
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
/// Extracts the value from a token text.
/// For quoted strings, strips the surrounding quotes.
fn extract_value(text : String) -> String? {
  if text.length() >= 2 {
    let first = text[0].to_int().unsafe_to_char()
    let last = text[text.length() - 1].to_int().unsafe_to_char()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return Some(text.substring(start=1, end=text.length() - 1))
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
