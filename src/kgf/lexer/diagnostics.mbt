///|
/// LexDiagnostic describes a span of source text that did not match any lexer
/// token rule.
pub struct LexDiagnostic {
  pos : Int
  length : Int
  text : String
} derive(Eq, Debug)

///|
/// Creates a lexical diagnostic for an unmatched source span.
pub fn LexDiagnostic::new(
  pos : Int,
  length : Int,
  text : String,
) -> LexDiagnostic {
  { pos, length, text }
}

///|
pub fn LexDiagnostic::get_pos(self : LexDiagnostic) -> Int {
  self.pos
}

///|
pub fn LexDiagnostic::get_length(self : LexDiagnostic) -> Int {
  self.length
}

///|
pub fn LexDiagnostic::get_text(self : LexDiagnostic) -> String {
  self.text
}

///|
/// Tokenizes input and returns lexer diagnostics.
///
/// Phase A only wires the public API. Unmatched-span collection is implemented
/// in a later phase, so diagnostics are currently empty.
pub fn Lexer::tokenize_with_diagnostics(
  self : Lexer,
  input : String,
) -> (Array[@types.Tok], Array[LexDiagnostic]) {
  (self.tokenize(input), [])
}
