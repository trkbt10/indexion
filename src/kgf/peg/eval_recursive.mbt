///|
/// Recursive PEG evaluator - fast but can stack overflow on very large files.
/// Use for files with < 10000 tokens.

///|
/// Recursive evaluation context.
priv struct RecEvalContext {
  peg : PEG
  tokens : Array[@types.Tok]
  token_ids : Array[Int]
  memo : Array[MemoState]
  num_positions : Int
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit
  emit_filter : @hashset.HashSet[String]?
}

///|
/// Creates recursive evaluation context.
fn RecEvalContext::new(
  peg : PEG,
  tokens : Array[@types.Tok],
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter? : @hashset.HashSet[String]? = None,
) -> RecEvalContext {
  let num_nodes = peg.fast_nodes.length()
  let num_positions = tokens.length() + 1
  let memo_size = num_nodes * num_positions
  let memo : Array[MemoState] = Array::make(memo_size, Unknown)
  let token_ids : Array[Int] = Array::make(tokens.length(), -1)
  for i = 0; i < tokens.length(); i = i + 1 {
    let kind = tokens[i].kind
    match peg.get_token_id(kind) {
      Some(id) => token_ids[i] = id
      None => token_ids[i] = -1
    }
  }
  { peg, tokens, token_ids, memo, num_positions, on_rule_match, emit_filter }
}

///|
/// Check if rule should be emitted.
fn should_emit_rule_rec(ctx : RecEvalContext, name : String) -> Bool {
  match ctx.emit_filter {
    Some(filter) => filter.contains(name)
    None => true
  }
}

///|
/// Fast recursive evaluator.
fn eval_rec(ctx : RecEvalContext, node_id : Int, pos : Int) -> FastEvalResult {
  let memo_idx = node_id * ctx.num_positions + pos
  match ctx.memo[memo_idx] {
    Succeeded(end_pos, labels) => {
      // Clone labels to avoid mutation issues
      let cloned : Map[String, Json] = {}
      for key, value in labels {
        cloned.set(key, value)
      }
      return { ok: true, end_pos, labels: cloned }
    }
    Failed => return { ok: false, end_pos: pos, labels: empty_labels() }
    Unknown => ()
  }
  let result = eval_node_rec(ctx, node_id, pos)
  if result.ok {
    ctx.memo[memo_idx] = Succeeded(result.end_pos, result.labels)
  } else {
    ctx.memo[memo_idx] = Failed
  }
  result
}

///|
/// Evaluate a single node recursively.
fn eval_node_rec(
  ctx : RecEvalContext,
  node_id : Int,
  pos : Int,
) -> FastEvalResult {
  let compiled = ctx.peg.fast_nodes[node_id]
  match compiled {
    FEmpty => { ok: true, end_pos: pos, labels: empty_labels() }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        let tok = ctx.tokens[pos]
        let labels : Map[String, Json] = Map::new()
        labels.set("_last", tok.get_value().to_json())
        labels.set("_last_pos", tok.pos.to_double().to_json())
        labels.set("_last_len", tok.text.length().to_double().to_json())
        // Use token value (cleaned by strip/skip_value) for text accumulation
        labels.set("_text", tok.get_value().to_json())
        { ok: true, end_pos: pos + 1, labels }
      } else {
        { ok: false, end_pos: pos, labels: empty_labels() }
      }
    FRuleRef(rule_node_id, name) => {
      let target_is_rule_ref = match ctx.peg.fast_nodes.get(rule_node_id) {
        Some(FRuleRef(_, _)) => true
        _ => false
      }
      let result = eval_rec(ctx, rule_node_id, pos)
      if result.ok && not(target_is_rule_ref) && should_emit_rule_rec(ctx, name) {
        (ctx.on_rule_match)(name, result.labels, pos, result.end_pos)
      }
      if result.ok {
        let clean : Map[String, Json] = Map::new()
        match result.labels.get("_last") {
          Some(v) => clean.set("_last", v)
          None => ()
        }
        match result.labels.get("_last_pos") {
          Some(v) => clean.set("_last_pos", v)
          None => ()
        }
        match result.labels.get("_last_len") {
          Some(v) => clean.set("_last_len", v)
          None => ()
        }
        match result.labels.get("_text") {
          Some(v) => clean.set("_text", v)
          None => ()
        }
        { ok: true, end_pos: result.end_pos, labels: clean }
      } else {
        result
      }
    }
    FSeq(elems) => {
      let mut current_pos = pos
      let labels : Map[String, Json] = Map::new()
      for elem_id in elems {
        let result = eval_rec(ctx, elem_id, current_pos)
        if not(result.ok) {
          return { ok: false, end_pos: pos, labels: empty_labels() }
        }
        merge_labels(labels, result.labels)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels }
    }
    FChoice(alts) => {
      for alt_id in alts {
        let result = eval_rec(ctx, alt_id, pos)
        if result.ok {
          return result
        }
      }
      { ok: false, end_pos: pos, labels: empty_labels() }
    }
    FStar(child) => {
      let mut current_pos = pos
      let labels : Map[String, Json] = Map::new()
      while true {
        let result = eval_rec(ctx, child, current_pos)
        if not(result.ok) || result.end_pos == current_pos {
          break
        }
        merge_labels(labels, result.labels)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels }
    }
    FPlus(child) => {
      let first = eval_rec(ctx, child, pos)
      if not(first.ok) {
        return { ok: false, end_pos: pos, labels: empty_labels() }
      }
      let labels : Map[String, Json] = Map::new()
      merge_labels(labels, first.labels)
      let mut current_pos = first.end_pos
      while true {
        let result = eval_rec(ctx, child, current_pos)
        if not(result.ok) || result.end_pos == current_pos {
          break
        }
        merge_labels(labels, result.labels)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels }
    }
    FOptional(child) => {
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        result
      } else {
        { ok: true, end_pos: pos, labels: empty_labels() }
      }
    }
    FLabel(label_name, child) => {
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        let labels = result.labels
        match labels.get("_last") {
          Some(v) => labels.set(label_name, v)
          None => ()
        }
        match labels.get("_last_pos") {
          Some(v) => labels.set(label_name + "_pos", v)
          None => ()
        }
        match labels.get("_last_len") {
          Some(v) => labels.set(label_name + "_len", v)
          None => ()
        }
        match labels.get("_text") {
          Some(v) => labels.set(label_name + "_text", v)
          None => ()
        }
        { ok: true, end_pos: result.end_pos, labels }
      } else {
        result
      }
    }
    FAnd(child) => {
      // And-predicate: succeed if child succeeds, but don't consume input
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        // Success: return original position, no labels propagated
        { ok: true, end_pos: pos, labels: empty_labels() }
      } else {
        // Failure
        { ok: false, end_pos: pos, labels: empty_labels() }
      }
    }
    FNot(child) => {
      // Not-predicate: succeed if child fails, don't consume input
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        // Child succeeded, so Not fails
        { ok: false, end_pos: pos, labels: empty_labels() }
      } else {
        // Child failed, so Not succeeds
        { ok: true, end_pos: pos, labels: empty_labels() }
      }
    }
  }
}

///|
/// Runs recursive PEG parse (internal).
fn run_parse_rec_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter : @hashset.HashSet[String]?,
) -> (Bool, Map[String, Json]) {
  let ctx = RecEvalContext::new(peg, tokens, on_rule_match, emit_filter~)
  match peg.get_fast_rule_body_id(start_rule) {
    None => (false, empty_labels())
    Some(body_node_id) => {
      let result = eval_rec(ctx, body_node_id, 0)
      if result.ok && should_emit_rule_rec(ctx, start_rule) {
        (ctx.on_rule_match)(start_rule, result.labels, 0, result.end_pos)
      }
      (result.ok, result.labels)
    }
  }
}

///|
/// Runs recursive PEG parse and returns EvalResult.
pub fn run_parse_filtered_rec(
  peg : PEG,
  _spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
  active_rules : @hashset.HashSet[String],
) -> EvalResult? {
  let events : Array[(String, Map[String, Json])] = []
  let callback = fn(
    rule_name : String,
    labels : Map[String, Json],
    _start_pos : Int,
    _end_pos : Int,
  ) {
    events.push((rule_name, labels))
  }
  let (ok, final_labels) = run_parse_rec_internal(
    peg,
    tokens,
    start_rule,
    callback,
    Some(active_rules),
  )
  if ok {
    Some(EvalResult::success(tokens.length(), labels=final_labels, events~))
  } else {
    None
  }
}
