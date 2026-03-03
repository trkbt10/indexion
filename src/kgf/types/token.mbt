///|
/// TokenDef represents a token definition in the KGF grammar.
/// Contains the token name, regex pattern, skip flag, and optional flags.
pub struct TokenDef {
  name : String
  pattern : String
  skip : Bool
  flags : String?
}

///|
/// Creates a new TokenDef with the specified parameters.
pub fn TokenDef::new(
  name : String,
  pattern : String,
  skip? : Bool = false,
  flags? : String? = None,
) -> TokenDef {
  { name, pattern, skip, flags }
}

///|
/// Returns the name of the token.
pub fn TokenDef::get_name(self : TokenDef) -> String {
  self.name
}

///|
/// Returns the pattern of the token.
pub fn TokenDef::get_pattern(self : TokenDef) -> String {
  self.pattern
}

///|
/// Returns whether this token should be skipped.
pub fn TokenDef::is_skip(self : TokenDef) -> Bool {
  self.skip
}

///|
/// Returns the flags of the token if any.
pub fn TokenDef::get_flags(self : TokenDef) -> String? {
  self.flags
}

///|
/// Tok represents a lexed token with position information.
pub struct Tok {
  kind : String
  text : String
  value : String?
  pos : Int
}

///|
/// Creates a new Tok with the specified parameters.
pub fn Tok::new(
  kind : String,
  text : String,
  pos : Int,
  value? : String? = None,
) -> Tok {
  { kind, text, value, pos }
}

///|
/// Returns the kind of the token.
pub fn Tok::get_kind(self : Tok) -> String {
  self.kind
}

///|
/// Returns the text of the token.
pub fn Tok::get_text(self : Tok) -> String {
  self.text
}

///|
/// Returns the value of the token (first capture group when present).
/// Defaults to text if not set.
pub fn Tok::get_value(self : Tok) -> String {
  match self.value {
    Some(v) => v
    None => self.text
  }
}

///|
/// Returns the position of the token in the source.
pub fn Tok::get_pos(self : Tok) -> Int {
  self.pos
}
