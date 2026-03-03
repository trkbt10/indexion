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
/// Memo key for memoization.
struct MemoKey {
  node_str : String
  pos : Int
} derive(Eq, Hash, Show)

///|
/// EvalContext holds the evaluation state.
struct EvalContext {
  peg : PEG
  tokens : Array[@types.Tok]
  memo : Map[MemoKey, EvalResult]
}

///|
/// Creates a new evaluation context.
pub fn EvalContext::new(peg : PEG, tokens : Array[@types.Tok]) -> EvalContext {
  { peg, tokens, memo: Map::new() }
}

///|
/// Converts a node to a string for memoization key.
fn node_to_string(node : Node) -> String {
  node.to_string()
}

///|
/// Creates a memo key from a node and position.
fn make_memo_key(node : Node, pos : Int) -> MemoKey {
  { node_str: node_to_string(node), pos }
}

///|
/// Merges two label maps, with the second taking precedence.
fn merge_labels(
  base : Map[String, Json],
  overlay : Map[String, Json],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map::new()
  for key, value in base {
    result.set(key, value)
  }
  for key, value in overlay {
    result.set(key, value)
  }
  result
}

///|
/// Appends events from one array to another.
fn append_events(
  base : Array[(String, Map[String, Json])],
  more : Array[(String, Map[String, Json])],
) -> Array[(String, Map[String, Json])] {
  let result : Array[(String, Map[String, Json])] = []
  for item in base {
    result.push(item)
  }
  for item in more {
    result.push(item)
  }
  result
}

///|
/// Evaluates a node at a given position.
fn eval_node(
  ctx : EvalContext,
  node : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  let key = make_memo_key(node, pos)
  // Check memo
  match ctx.memo.get(key) {
    Some(cached) => return cached
    None => ()
  }
  let result = eval_node_impl(ctx, node, pos, call_rule)
  ctx.memo.set(key, result)
  result
}

///|
/// Implementation of node evaluation.
fn eval_node_impl(
  ctx : EvalContext,
  node : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  match node {
    Empty => EvalResult::success(pos)
    Sym(name) => eval_sym(ctx, name, pos, call_rule)
    Seq(elems) => eval_seq(ctx, elems, pos, call_rule)
    Choice(alts) => eval_choice(ctx, alts, pos, call_rule)
    Star(child) => eval_star(ctx, child, pos, call_rule)
    Plus(child) => eval_plus(ctx, child, pos, call_rule)
    Optional(child) => eval_optional(ctx, child, pos, call_rule)
    Label(name, child) => eval_label(ctx, name, child, pos, call_rule)
  }
}

///|
/// Evaluates a symbol (token or rule reference).
fn eval_sym(
  ctx : EvalContext,
  name : String,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  if ctx.peg.is_token(name) {
    // Token match
    if pos < ctx.tokens.length() && ctx.tokens[pos].kind == name {
      let tok = ctx.tokens[pos]
      let labels : Map[String, Json] = Map::new()
      labels.set("_last", tok.get_value().to_json())
      labels.set("_last_pos", tok.pos.to_double().to_json())
      labels.set("_last_len", tok.text.length().to_double().to_json())
      EvalResult::success(pos + 1, labels~)
    } else {
      EvalResult::failure(pos)
    }
  } else {
    // Rule reference
    call_rule(name, pos)
  }
}

///|
/// Evaluates a sequence of nodes.
fn eval_seq(
  ctx : EvalContext,
  elems : Array[Node],
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  let mut current_pos = pos
  let mut labels : Map[String, Json] = Map::new()
  let mut events : Array[(String, Map[String, Json])] = []
  for elem in elems {
    let r = eval_node(ctx, elem, current_pos, call_rule)
    if not(r.ok) {
      return EvalResult::failure(pos)
    }
    current_pos = r.pos
    labels = merge_labels(labels, r.labels)
    events = append_events(events, r.events)
  }
  EvalResult::success(current_pos, labels~, events~)
}

///|
/// Evaluates a choice (first successful alternative).
fn eval_choice(
  ctx : EvalContext,
  alts : Array[Node],
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  for alt in alts {
    let r = eval_node(ctx, alt, pos, call_rule)
    if r.ok {
      return r
    }
  }
  EvalResult::failure(pos)
}

///|
/// Evaluates a star (zero or more repetitions).
fn eval_star(
  ctx : EvalContext,
  child : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  let mut current_pos = pos
  let mut labels : Map[String, Json] = Map::new()
  let mut events : Array[(String, Map[String, Json])] = []
  while true {
    let r = eval_node(ctx, child, current_pos, call_rule)
    if not(r.ok) {
      break
    }
    current_pos = r.pos
    labels = merge_labels(labels, r.labels)
    events = append_events(events, r.events)
  }
  EvalResult::success(current_pos, labels~, events~)
}

///|
/// Evaluates a plus (one or more repetitions).
fn eval_plus(
  ctx : EvalContext,
  child : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  // First iteration must succeed
  let first = eval_node(ctx, child, pos, call_rule)
  if not(first.ok) {
    return EvalResult::failure(pos)
  }
  let mut current_pos = first.pos
  let mut labels = first.labels
  let mut events = first.events
  // Additional iterations (like star)
  while true {
    let r = eval_node(ctx, child, current_pos, call_rule)
    if not(r.ok) {
      break
    }
    current_pos = r.pos
    labels = merge_labels(labels, r.labels)
    events = append_events(events, r.events)
  }
  EvalResult::success(current_pos, labels~, events~)
}

///|
/// Evaluates an optional (zero or one).
fn eval_optional(
  ctx : EvalContext,
  child : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  let r = eval_node(ctx, child, pos, call_rule)
  if r.ok {
    r
  } else {
    EvalResult::success(pos)
  }
}

///|
/// Evaluates a labeled expression.
fn eval_label(
  ctx : EvalContext,
  name : String,
  child : Node,
  pos : Int,
  call_rule : (String, Int) -> EvalResult,
) -> EvalResult {
  let r = eval_node(ctx, child, pos, call_rule)
  if not(r.ok) {
    return EvalResult::failure(pos)
  }
  let labels = r.labels
  // Copy _last to the label name
  match labels.get("_last") {
    Some(v) => labels.set(name, v)
    None => labels.set(name, Json::null())
  }
  // Copy _last_pos to name_pos
  match labels.get("_last_pos") {
    Some(v) => labels.set(name + "_pos", v)
    None => ()
  }
  // Copy _last_len to name_len
  match labels.get("_last_len") {
    Some(v) => labels.set(name + "_len", v)
    None => ()
  }
  EvalResult::success(r.pos, labels~, events=r.events)
}

///|
/// Runs a PEG parse from a start rule over tokens.
/// Returns the final result with labels and events, or None on failure.
/// Events include rule match notifications for semantic processing.
pub fn run_parse(
  peg : PEG,
  _spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
) -> EvalResult? {
  let ctx = EvalContext::new(peg, tokens)
  // Collect all rule match events
  let all_events : Array[(String, Map[String, Json])] = []
  // Define call_rule function that emits events for matched rules
  fn call_rule(name : String, pos : Int) -> EvalResult {
    match peg.get_rule(name) {
      Some(node) => {
        let result = eval_node(ctx, node, pos, call_rule)
        if result.ok {
          // Emit event for this matched rule
          let event_labels : Map[String, Json] = Map::new()
          for key, value in result.labels {
            event_labels.set(key, value)
          }
          all_events.push((name, event_labels))
        }
        result
      }
      None => EvalResult::failure(pos)
    }
  }

  // Get start rule AST
  let start_node = peg.get_rule(start_rule)
  match start_node {
    None => None
    Some(node) => {
      let result = eval_node(ctx, node, 0, call_rule)
      if result.ok {
        // Merge all rule match events into the result
        let merged_events = append_events(result.events, all_events)
        Some(
          EvalResult::success(
            result.pos,
            labels=result.labels,
            events=merged_events,
          ),
        )
      } else {
        None
      }
    }
  }
}
