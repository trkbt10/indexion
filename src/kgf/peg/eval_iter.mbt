///|
/// Iterative (trampoline-based) PEG evaluator to avoid stack overflow.
/// Handles large files that would cause SIGSEGV with recursive approach.
/// Optimized to avoid array copying by using indices.

///|
/// Memo entry states for memoization.
/// Stores labels to support labeled captures across backtracking.
priv enum MemoState {
  Unknown
  Failed
  Succeeded(Int, Map[String, Json]) // (end_pos, labels)
}

///|
/// FastEvalResult holds evaluation result with labels.
priv struct FastEvalResult {
  ok : Bool
  end_pos : Int
  labels : Map[String, Json]
}

///|
/// Creates empty labels map.
fn empty_labels() -> Map[String, Json] {
  Map::new()
}

///|
/// Merges labels from source into target (in place).
fn merge_labels(target : Map[String, Json], source : Map[String, Json]) -> Unit {
  for key, value in source {
    if key == "_text" {
      match (target.get("_text"), value) {
        (Some(String(base)), String(new_text)) =>
          target.set("_text", (base + new_text).to_json())
        _ => target.set(key, value)
      }
    } else {
      target.set(key, value)
    }
  }
}

///|
/// Work item for the evaluation stack.
/// Uses indices instead of copying arrays for better performance.
priv enum WorkItem {
  /// Evaluate a node and push result
  Eval(Int, Int) // node_id, pos
  /// Continue Seq: node_id, elem_index, start_pos, current_pos, labels
  SeqCont(Int, Int, Int, Int, Map[String, Json])
  /// Continue Choice: node_id, alt_index, pos
  ChoiceCont(Int, Int, Int)
  /// Continue Star: child_id, start_pos, current_pos, labels
  StarCont(Int, Int, Int, Map[String, Json])
  /// Continue Plus first: child_id, node_id, start_pos
  PlusFirst(Int, Int, Int)
  /// Continue Plus rest: child_id, start_pos, current_pos, labels
  PlusRest(Int, Int, Int, Map[String, Json])
  /// Continue Optional: node_id, pos
  OptionalCont(Int, Int)
  /// Continue Label: label_name, start_pos
  LabelCont(String, Int)
  /// Continue RuleRef: rule_name, target_is_rule_ref, start_pos
  RuleRefCont(String, Bool, Int)
}

///|
/// Iterative evaluation context.
priv struct IterEvalContext {
  peg : PEG
  tokens : Array[@types.Tok]
  token_ids : Array[Int]
  memo : Array[MemoState]
  num_positions : Int
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit
  emit_filter : @hashset.HashSet[String]?
  work : Array[WorkItem]
  results : Array[FastEvalResult]
  brace_pairs : BracePairs
}

///|
/// Creates iterative evaluation context.
fn IterEvalContext::new(
  peg : PEG,
  tokens : Array[@types.Tok],
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter? : @hashset.HashSet[String]? = None,
) -> IterEvalContext {
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
  // Pre-compute bracket pairs for fast balanced matching
  let brace_pairs = compute_brace_pairs(tokens)
  {
    peg,
    tokens,
    token_ids,
    memo,
    num_positions,
    on_rule_match,
    emit_filter,
    work: Array::new(capacity=1024),
    results: Array::new(capacity=256),
    brace_pairs,
  }
}

///|
/// Check if rule should be emitted.
fn should_emit_rule_iter(ctx : IterEvalContext, name : String) -> Bool {
  match ctx.emit_filter {
    Some(filter) => filter.contains(name)
    None => true
  }
}

///|
/// Try to skip balanced brackets without recursion.
/// Returns end position if brackets can be skipped, or start position if not.
fn try_bracket_skip(ctx : IterEvalContext, start_pos : Int) -> Int {
  let mut pos = start_pos
  while pos < ctx.tokens.length() {
    let kind = ctx.tokens[pos].kind
    // Check if this is an opening bracket
    if kind == "LBRACE" || kind == "LPAREN" || kind == "LBRACKET" {
      match ctx.brace_pairs.get_close(pos) {
        Some(close_pos) =>
          // Jump to position after closing bracket
          pos = close_pos + 1
        None =>
          // No matching bracket, can't skip
          return start_pos
      }
    } else {
      // Not an opening bracket, stop skipping
      break
    }
  }
  pos
}

///|
/// Iterative main loop.
fn eval_iter_loop(ctx : IterEvalContext) -> Unit {
  while ctx.work.length() > 0 {
    let item = ctx.work.pop().unwrap()
    match item {
      Eval(node_id, pos) => process_eval(ctx, node_id, pos)
      SeqCont(node_id, idx, start_pos, current_pos, labels) =>
        process_seq_cont(ctx, node_id, idx, start_pos, current_pos, labels)
      ChoiceCont(node_id, idx, pos) =>
        process_choice_cont(ctx, node_id, idx, pos)
      StarCont(child_id, start_pos, current_pos, labels) =>
        process_star_cont(ctx, child_id, start_pos, current_pos, labels)
      PlusFirst(child_id, node_id, start_pos) =>
        process_plus_first(ctx, child_id, node_id, start_pos)
      PlusRest(child_id, start_pos, current_pos, labels) =>
        process_plus_rest(ctx, child_id, start_pos, current_pos, labels)
      OptionalCont(node_id, pos) => process_optional_cont(ctx, node_id, pos)
      LabelCont(label_name, _) => process_label_cont(ctx, label_name)
      RuleRefCont(rule_name, target_is_rule_ref, start_pos) =>
        process_rule_ref_cont(ctx, rule_name, target_is_rule_ref, start_pos)
    }
  }
}

///|
/// Process Eval work item.
fn process_eval(ctx : IterEvalContext, node_id : Int, pos : Int) -> Unit {
  // Check memo first
  let memo_idx = node_id * ctx.num_positions + pos
  match ctx.memo[memo_idx] {
    Succeeded(end_pos, labels) => {
      // Clone labels to avoid mutation issues
      let cloned : Map[String, Json] = {}
      for key, value in labels {
        cloned.set(key, value)
      }
      ctx.results.push({ ok: true, end_pos, labels: cloned })
      return
    }
    Failed => {
      ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
      return
    }
    Unknown => ()
  }
  // Process node
  let compiled = ctx.peg.fast_nodes[node_id]
  match compiled {
    FEmpty => {
      let labels = empty_labels()
      ctx.memo[memo_idx] = Succeeded(pos, labels)
      ctx.results.push({ ok: true, end_pos: pos, labels })
    }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        let tok = ctx.tokens[pos]
        let labels : Map[String, Json] = Map::new()
        labels.set("_last", tok.get_value().to_json())
        labels.set("_last_pos", tok.pos.to_double().to_json())
        labels.set("_last_len", tok.text.length().to_double().to_json())
        labels.set("_text", tok.text.to_json())
        ctx.memo[memo_idx] = Succeeded(pos + 1, labels)
        ctx.results.push({ ok: true, end_pos: pos + 1, labels })
      } else {
        ctx.memo[memo_idx] = Failed
        ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
      }
    FRuleRef(rule_node_id, name) => {
      let target_is_rule_ref = match ctx.peg.fast_nodes.get(rule_node_id) {
        Some(FRuleRef(_, _)) => true
        _ => false
      }
      ctx.work.push(RuleRefCont(name, target_is_rule_ref, pos))
      ctx.work.push(Eval(rule_node_id, pos))
    }
    FSeq(elems) =>
      if elems.length() == 0 {
        let labels = empty_labels()
        ctx.memo[memo_idx] = Succeeded(pos, labels)
        ctx.results.push({ ok: true, end_pos: pos, labels })
      } else {
        // Push continuation with index 0, then eval first element
        ctx.work.push(SeqCont(node_id, 0, pos, pos, Map::new()))
        ctx.work.push(Eval(elems[0], pos))
      }
    FChoice(alts) =>
      if alts.length() == 0 {
        ctx.memo[memo_idx] = Failed
        ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
      } else {
        ctx.work.push(ChoiceCont(node_id, 0, pos))
        ctx.work.push(Eval(alts[0], pos))
      }
    FStar(child) => {
      // Try bracket skip optimization first
      let skip_end = try_bracket_skip(ctx, pos)
      if skip_end > pos {
        // Skipped brackets, continue evaluating child from new position
        ctx.work.push(StarCont(child, pos, skip_end, Map::new()))
        ctx.work.push(Eval(child, skip_end))
      } else {
        ctx.work.push(StarCont(child, pos, pos, Map::new()))
        ctx.work.push(Eval(child, pos))
      }
    }
    FPlus(child) => {
      ctx.work.push(PlusFirst(child, node_id, pos))
      ctx.work.push(Eval(child, pos))
    }
    FOptional(child) => {
      ctx.work.push(OptionalCont(node_id, pos))
      ctx.work.push(Eval(child, pos))
    }
    FLabel(label_name, child) => {
      ctx.work.push(LabelCont(label_name, pos))
      ctx.work.push(Eval(child, pos))
    }
  }
}

///|
/// Process Seq continuation with index-based tracking.
fn process_seq_cont(
  ctx : IterEvalContext,
  node_id : Int,
  idx : Int,
  start_pos : Int,
  current_pos : Int,
  labels : Map[String, Json],
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if not(result.ok) {
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: start_pos, labels: empty_labels() })
    return
  }
  merge_labels(labels, result.labels)
  let new_pos = result.end_pos
  // Get elems from node
  let elems = match ctx.peg.fast_nodes[node_id] {
    FSeq(e) => e
    _ => return // Should not happen
  }
  let next_idx = idx + 1
  if next_idx >= elems.length() {
    // All children succeeded
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Succeeded(new_pos, labels)
    ctx.results.push({ ok: true, end_pos: new_pos, labels })
  } else {
    // Continue with next child
    ctx.work.push(SeqCont(node_id, next_idx, start_pos, new_pos, labels))
    ctx.work.push(Eval(elems[next_idx], new_pos))
  }
}

///|
/// Process Choice continuation with index-based tracking.
fn process_choice_cont(
  ctx : IterEvalContext,
  node_id : Int,
  idx : Int,
  pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if result.ok {
    let memo_idx = node_id * ctx.num_positions + pos
    ctx.memo[memo_idx] = Succeeded(result.end_pos, result.labels)
    ctx.results.push(result)
    return
  }
  // Get alts from node
  let alts = match ctx.peg.fast_nodes[node_id] {
    FChoice(a) => a
    _ => return
  }
  let next_idx = idx + 1
  if next_idx >= alts.length() {
    let memo_idx = node_id * ctx.num_positions + pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
  } else {
    ctx.work.push(ChoiceCont(node_id, next_idx, pos))
    ctx.work.push(Eval(alts[next_idx], pos))
  }
}

///|
/// Process Star continuation.
fn process_star_cont(
  ctx : IterEvalContext,
  child_id : Int,
  start_pos : Int,
  current_pos : Int,
  labels : Map[String, Json],
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if not(result.ok) || result.end_pos == current_pos {
    ctx.results.push({ ok: true, end_pos: current_pos, labels })
    return
  }
  merge_labels(labels, result.labels)
  let new_pos = result.end_pos
  // Try bracket skip optimization for next iteration
  let skip_end = try_bracket_skip(ctx, new_pos)
  if skip_end > new_pos {
    ctx.work.push(StarCont(child_id, start_pos, skip_end, labels))
    ctx.work.push(Eval(child_id, skip_end))
  } else {
    ctx.work.push(StarCont(child_id, start_pos, new_pos, labels))
    ctx.work.push(Eval(child_id, new_pos))
  }
  ignore(start_pos)
}

///|
/// Process Plus first continuation.
fn process_plus_first(
  ctx : IterEvalContext,
  child_id : Int,
  node_id : Int,
  start_pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if not(result.ok) {
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: start_pos, labels: empty_labels() })
    return
  }
  let labels : Map[String, Json] = Map::new()
  merge_labels(labels, result.labels)
  let current_pos = result.end_pos
  ctx.work.push(PlusRest(child_id, start_pos, current_pos, labels))
  ctx.work.push(Eval(child_id, current_pos))
}

///|
/// Process Plus rest continuation.
fn process_plus_rest(
  ctx : IterEvalContext,
  child_id : Int,
  start_pos : Int,
  current_pos : Int,
  labels : Map[String, Json],
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if not(result.ok) || result.end_pos == current_pos {
    ctx.results.push({ ok: true, end_pos: current_pos, labels })
    return
  }
  merge_labels(labels, result.labels)
  let new_pos = result.end_pos
  ctx.work.push(PlusRest(child_id, start_pos, new_pos, labels))
  ctx.work.push(Eval(child_id, new_pos))
  ignore(start_pos)
}

///|
/// Process Optional continuation.
fn process_optional_cont(
  ctx : IterEvalContext,
  node_id : Int,
  pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if result.ok {
    let memo_idx = node_id * ctx.num_positions + pos
    ctx.memo[memo_idx] = Succeeded(result.end_pos, result.labels)
    ctx.results.push(result)
  } else {
    let memo_idx = node_id * ctx.num_positions + pos
    let labels = empty_labels()
    ctx.memo[memo_idx] = Succeeded(pos, labels)
    ctx.results.push({ ok: true, end_pos: pos, labels })
  }
}

///|
/// Process Label continuation.
fn process_label_cont(ctx : IterEvalContext, label_name : String) -> Unit {
  let result = ctx.results.pop().unwrap()
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
    ctx.results.push({ ok: true, end_pos: result.end_pos, labels })
  } else {
    ctx.results.push(result)
  }
}

///|
/// Process RuleRef continuation.
fn process_rule_ref_cont(
  ctx : IterEvalContext,
  rule_name : String,
  target_is_rule_ref : Bool,
  start_pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if result.ok &&
    not(target_is_rule_ref) &&
    should_emit_rule_iter(ctx, rule_name) {
    (ctx.on_rule_match)(rule_name, result.labels, start_pos, result.end_pos)
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
    ctx.results.push({ ok: true, end_pos: result.end_pos, labels: clean })
  } else {
    ctx.results.push(result)
  }
}

///|
/// Runs iterative PEG parse (internal).
fn run_parse_iter_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter : @hashset.HashSet[String]?,
) -> (Bool, Map[String, Json]) {
  let ctx = IterEvalContext::new(peg, tokens, on_rule_match, emit_filter~)
  match peg.get_fast_rule_body_id(start_rule) {
    None => (false, empty_labels())
    Some(body_node_id) => {
      ctx.work.push(Eval(body_node_id, 0))
      eval_iter_loop(ctx)
      let result = ctx.results
        .pop()
        .unwrap_or({ ok: false, end_pos: 0, labels: Map::new() })
      if result.ok && should_emit_rule_iter(ctx, start_rule) {
        (ctx.on_rule_match)(start_rule, result.labels, 0, result.end_pos)
      }
      (result.ok, result.labels)
    }
  }
}

///|
/// Runs iterative PEG parse with callback-based event emission.
pub fn run_parse_iter(
  peg : PEG,
  _spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
  active_rules : @hashset.HashSet[String],
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
) -> Bool {
  let (ok, _) = run_parse_iter_internal(
    peg,
    tokens,
    start_rule,
    on_rule_match,
    Some(active_rules),
  )
  ok
}

///|
/// Runs iterative PEG parse and returns EvalResult for compatibility.
pub fn run_parse_filtered_iter(
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
  let (ok, final_labels) = run_parse_iter_internal(
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
