///|
/// Lexer transforms input text into tokens based on token definitions.
pub struct Lexer {
  tokens : Array[@types.TokenDef]
}

///|
/// Creates a new Lexer with the given token definitions.
/// Token definitions are tried in order, so more specific patterns should come first.
pub fn Lexer::new(tokens : Array[@types.TokenDef]) -> Lexer {
  { tokens, }
}

///|
/// Tokenizes the input string and returns an array of tokens.
/// Skipped tokens (like whitespace) are not included in the result.
pub fn Lexer::tokenize(self : Lexer, input : String) -> Array[@types.Tok] {
  let result : Array[@types.Tok] = []
  let mut pos = 0
  while pos < input.length() {
    let match_result = self.try_match(input, pos)
    match match_result {
      Some((token_def, end_pos, text)) => {
        if not(token_def.skip) {
          let value = extract_value(text)
          result.push(@types.Tok::new(token_def.name, text, pos, value~))
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
  pos : Int,
) -> (@types.TokenDef, Int, String)? {
  for token_def in self.tokens {
    let case_insensitive = match token_def.flags {
      Some(flags) => flags.contains("i")
      None => false
    }
    let match_result = match_pattern(
      token_def.pattern,
      input,
      pos,
      case_insensitive~,
    )
    if match_result.matched && match_result.text.length() > 0 {
      return Some((token_def, match_result.end_pos, match_result.text))
    }
  }
  None
}

///|
/// Extracts the value from a token text.
/// For quoted strings, strips the surrounding quotes.
fn extract_value(text : String) -> String? {
  if text.length() >= 2 {
    let first = Char::from_int(text[0].to_int())
    let last = Char::from_int(text[text.length() - 1].to_int())
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
