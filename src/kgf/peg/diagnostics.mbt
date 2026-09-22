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
  { furthest_pos, actual_token, expected_kinds, fully_consumed, }
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
/// One-line description of where parsing stopped, for user-facing output:
/// "expected A, B, found C" when the parser recorded expectations, otherwise
/// "unexpected C" (or "end of input" when the stop is past the last token).
pub fn ParseDiagnostic::describe(self : ParseDiagnostic) -> String {
  let actual = match self.actual_token {
    Some(tok) => tok.get_kind()
    None => "end of input"
  }
  if self.expected_kinds.length() > 0 {
    "expected " + self.expected_kinds.join(", ") + ", found " + actual
  } else {
    "unexpected " + actual
  }
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
/// Runs iterative PEG parse and keeps diagnostic tracking state.
///
/// Shares the evaluator's single delivery point (`run_iter_to_completion`),
/// so a diagnostic run sees exactly the events a plain run would: those of
/// the final derivation, in post-order, once each.
fn run_parse_diag_iter_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  emit_filter : @hashset.HashSet[String]?,
) -> (
  FastEvalResult,
  Map[String, Json],
  Array[(String, Map[String, Json])],
  Int,
  Array[String],
) {
  let ctx = IterEvalContext::new(
    peg,
    tokens,
    emit_filter~,
    diagnostics_enabled=true,
  )
  match peg.get_fast_rule_body_id(start_rule) {
    None =>
      (fail_result(0), Map([]), [], ctx.furthest_pos, ctx.furthest_expected)
    Some(body_node_id) => {
      let (result, final_labels, events) = run_iter_to_completion(
        ctx, start_rule, body_node_id,
      )
      (result, final_labels, events, ctx.furthest_pos, ctx.furthest_expected)
    }
  }
}

///|
/// Runs a PEG parse and returns parse diagnostics.
///
/// The returned `EvalResult` carries the events of the final derivation,
/// delivered once at the end — the same guarantee `run_parse_filtered`
/// provides. When the parse stops short of the input's end, the events of
/// the prefix that was consumed are still delivered; the diagnostic then
/// reports where it stopped.
pub fn run_parse_with_diagnostics(
  peg : PEG,
  spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
) -> (EvalResult?, ParseDiagnostic) {
  let active_rules : @hashset.HashSet[String] = HashSet([])
  for name, _ in spec.get_rules() {
    active_rules.add(name)
  }
  let (fast_result, final_labels, events, furthest_pos, expected_kinds) = run_parse_diag_iter_internal(
    peg,
    tokens,
    start_rule,
    Some(active_rules),
  )
  let result = if fast_result.ok {
    Some(EvalResult::success(fast_result.end_pos, labels=final_labels, events~))
  } else {
    None
  }
  let fully_consumed = fast_result.ok && fast_result.end_pos == tokens.length()
  let diagnostic_pos = if fast_result.ok {
    fast_result.end_pos
  } else {
    furthest_pos
  }
  let diagnostic_expected = if fast_result.ok { [] } else { expected_kinds }
  (
    result,
    ParseDiagnostic::new(
      diagnostic_pos,
      token_at(tokens, diagnostic_pos),
      diagnostic_expected,
      fully_consumed,
    ),
  )
}
