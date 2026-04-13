///|
/// EvalResult represents the result of a PEG evaluation.
pub struct EvalResult {
  ok : Bool
  pos : Int
  labels : Map[String, Json]
  events : Array[(String, Map[String, Json])]
}

///|
/// Creates a new successful EvalResult.
pub fn EvalResult::success(
  pos : Int,
  labels? : Map[String, Json] = Map::new(),
  events? : Array[(String, Map[String, Json])] = [],
) -> EvalResult {
  { ok: true, pos, labels, events }
}

///|
/// Creates a new failed EvalResult.
pub fn EvalResult::failure(pos : Int) -> EvalResult {
  { ok: false, pos, labels: Map::new(), events: [] }
}

///|
/// Returns true if the evaluation succeeded.
pub fn EvalResult::is_ok(self : EvalResult) -> Bool {
  self.ok
}

///|
/// Returns the position after evaluation.
pub fn EvalResult::get_pos(self : EvalResult) -> Int {
  self.pos
}

///|
/// Returns the captured labels.
pub fn EvalResult::get_labels(self : EvalResult) -> Map[String, Json] {
  self.labels
}

///|
/// Returns the emitted events.
pub fn EvalResult::get_events(
  self : EvalResult,
) -> Array[(String, Map[String, Json])] {
  self.events
}

///|
/// Gets a label value by name.
pub fn EvalResult::get_label(self : EvalResult, name : String) -> Json? {
  self.labels.get(name)
}

///|
/// Token threshold for switching to iterative evaluator.
/// Below this: use fast recursive. Above: use iterative (safe for deep nesting).
let token_threshold : Int = 0

///|
/// Runs a PEG parse and emits all matched rule events.
/// Uses recursive evaluator for small files (fast), iterative for large files (safe).
pub fn run_parse(
  peg : PEG,
  spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
) -> EvalResult? {
  let active_rules : @hashset.HashSet[String] = @hashset.new()
  for name, _ in spec.get_rules() {
    active_rules.add(name)
  }
  run_parse_filtered(peg, spec, start_rule, tokens, active_rules)
}

///|
/// Runs a PEG parse while emitting only a subset of rule events.
/// Uses recursive evaluator for small files (fast), iterative for large files (safe).
pub fn run_parse_filtered(
  peg : PEG,
  spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
  active_rules : @hashset.HashSet[String],
) -> EvalResult? {
  if tokens.length() < token_threshold {
    // Fast path: use recursive evaluator
    run_parse_filtered_rec(peg, spec, start_rule, tokens, active_rules)
  } else {
    // Safe path: use iterative evaluator for large files
    run_parse_filtered_iter(peg, spec, start_rule, tokens, active_rules)
  }
}
