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
/// Runs iterative PEG parse and keeps diagnostic tracking state.
fn run_parse_diag_iter_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter : @hashset.HashSet[String]?,
) -> (FastEvalResult, Map[String, Json], Int, Array[String]) {
  let ctx = IterEvalContext::new(
    peg,
    tokens,
    on_rule_match,
    emit_filter~,
    diagnostics_enabled=true,
  )
  match peg.get_fast_rule_body_id(start_rule) {
    None =>
      (
        { ok: false, end_pos: 0, labels: empty_labels() },
        Map::new(),
        ctx.furthest_pos,
        ctx.furthest_expected,
      )
    Some(body_node_id) => {
      ctx.work.push(Eval(body_node_id, 0))
      eval_iter_loop(ctx)
      let result = ctx.results
        .pop()
        .unwrap_or({ ok: false, end_pos: 0, labels: empty_labels() })
      if result.ok && should_emit_rule_iter(ctx, start_rule) {
        let labels_map = materialize(result.labels, ctx.tokens)
        labels_map.set(@types.META_START_TOK, (0).to_json())
        labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
        (ctx.on_rule_match)(start_rule, labels_map, 0, result.end_pos)
      }
      let final_labels = materialize(result.labels, ctx.tokens)
      (result, final_labels, ctx.furthest_pos, ctx.furthest_expected)
    }
  }
}

///|
/// Runs a PEG parse and returns parse diagnostics.
pub fn run_parse_with_diagnostics(
  peg : PEG,
  spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
) -> (EvalResult?, ParseDiagnostic) {
  let active_rules : @hashset.HashSet[String] = @hashset.new()
  for name, _ in spec.get_rules() {
    active_rules.add(name)
  }
  let events : Array[(String, Map[String, Json])] = []
  let callback = fn(
    rule_name : String,
    labels : Map[String, Json],
    _start_pos : Int,
    _end_pos : Int,
  ) {
    events.push((rule_name, labels))
  }
  let (fast_result, final_labels, furthest_pos, expected_kinds) = run_parse_diag_iter_internal(
    peg,
    tokens,
    start_rule,
    callback,
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
