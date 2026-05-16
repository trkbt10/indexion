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
pub fn Lexer::tokenize_with_diagnostics(
  self : Lexer,
  input : String,
) -> (Array[@types.Tok], Array[LexDiagnostic]) {
  let result : Array[@types.Tok] = []
  let diagnostics : Array[LexDiagnostic] = []
  let input_chars = @regexp.build_input_chars(input)
  let mut pos = 0
  let mut unmatched_start = -1
  let mut unmatched_end = -1
  while pos < input.length() {
    let match_result = self.try_match(input, input_chars, pos)
    match match_result {
      Some((token_def, end_pos, text, group1)) => {
        if unmatched_start >= 0 {
          diagnostics.push(
            LexDiagnostic::new(
              unmatched_start,
              unmatched_end - unmatched_start,
              input[unmatched_start:unmatched_end].to_owned(),
            ),
          )
          unmatched_start = -1
          unmatched_end = -1
        }
        if !token_def.skip {
          match text {
            Some(token_text) => {
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
      None => {
        if unmatched_start < 0 {
          unmatched_start = pos
        }
        pos = pos + 1
        unmatched_end = pos
      }
    }
  }
  if unmatched_start >= 0 {
    diagnostics.push(
      LexDiagnostic::new(
        unmatched_start,
        unmatched_end - unmatched_start,
        input[unmatched_start:unmatched_end].to_owned(),
      ),
    )
  }
  (result, diagnostics)
}
