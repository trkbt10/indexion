///|
/// ParseDiagnostic describes where PEG parsing stopped and what was expected.
pub struct ParseDiagnostic {
  furthest_pos : Int
  actual_token : @types.Tok?
  expected_kinds : Array[String]
  fully_consumed : Bool
}

///|
/// Creates a parse diagnostic.
pub fn ParseDiagnostic::new(
  furthest_pos : Int,
  actual_token : @types.Tok?,
  expected_kinds : Array[String],
  fully_consumed : Bool,
) -> ParseDiagnostic {
  { furthest_pos, actual_token, expected_kinds, fully_consumed }
}

///|
pub fn ParseDiagnostic::get_furthest_pos(self : ParseDiagnostic) -> Int {
  self.furthest_pos
}

///|
pub fn ParseDiagnostic::get_actual_token(self : ParseDiagnostic) -> @types.Tok? {
  self.actual_token
}

///|
pub fn ParseDiagnostic::get_expected_kinds(
  self : ParseDiagnostic,
) -> Array[String] {
  self.expected_kinds
}

///|
pub fn ParseDiagnostic::is_fully_consumed(self : ParseDiagnostic) -> Bool {
  self.fully_consumed
}

///|
fn token_at(tokens : Array[@types.Tok], pos : Int) -> @types.Tok? {
  if pos >= 0 && pos < tokens.length() {
    Some(tokens[pos])
  } else {
    None
  }
}

///|
/// Runs a PEG parse and returns parse diagnostics.
///
/// Phase A only wires the public API. Furthest-position and expected-token
/// tracking are implemented in a later phase.
pub fn run_parse_with_diagnostics(
  peg : PEG,
  spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
) -> (EvalResult?, ParseDiagnostic) {
  let result = run_parse(peg, spec, start_rule, tokens)
  let furthest_pos = match result {
    Some(r) => r.get_pos()
    None => 0
  }
  let fully_consumed = match result {
    Some(r) => r.is_ok() && r.get_pos() == tokens.length()
    None => false
  }
  (
    result,
    ParseDiagnostic::new(
      furthest_pos,
      token_at(tokens, furthest_pos),
      [],
      fully_consumed,
    ),
  )
}
