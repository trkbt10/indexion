///|
/// Iterative (trampoline-based) PEG evaluator to avoid stack overflow.
/// Handles large files that would cause SIGSEGV with recursive approach.
/// Optimized to avoid array copying by using indices.
///
/// Common types (MemoState, FastEvalResult, etc.) are defined in eval_common.mbt.

///|
/// Work item for the evaluation stack.
/// Uses Labels for lazy label evaluation.
priv enum WorkItem {
  /// Evaluate a node and push result
  Eval(Int, Int) // node_id, pos
  /// Continue Seq: node_id, elem_index, start_pos, current_pos, labels
  SeqCont(Int, Int, Int, Int, Labels)
  /// Continue Choice: node_id, alt_index, pos
  ChoiceCont(Int, Int, Int)
  /// Continue Star: child_id, start_pos, current_pos, labels
  StarCont(Int, Int, Int, Labels)
  /// Continue Plus first: child_id, node_id, start_pos
  PlusFirst(Int, Int, Int)
  /// Continue Plus rest: child_id, start_pos, current_pos, labels
  PlusRest(Int, Int, Int, Labels)
  /// Continue Optional: node_id, pos
  OptionalCont(Int, Int)
  /// Continue Label: label_name
  LabelCont(String)
  /// Continue RuleRef: rule_name, target_is_rule_ref, start_pos
  RuleRefCont(String, Bool, Int)
  /// Continue And-predicate: node_id, pos (for memoization)
  AndCont(Int, Int)
  /// Continue Not-predicate: node_id, pos (for memoization)
  NotCont(Int, Int)
}

///|
/// Iterative evaluation context.
priv struct IterEvalContext {
  peg : PEG
  tokens : Array[@types.Tok]
  token_ids : Array[Int]
  token_names : Array[String]
  memo : Array[MemoState]
  num_positions : Int
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit
  emit_filter : @hashset.HashSet[String]?
  diagnostics_enabled : Bool
  mut furthest_pos : Int
  furthest_expected : Array[String]
  furthest_expected_set : @hashset.HashSet[String]
  work : Array[WorkItem]
  results : Array[FastEvalResult]
}

///|
/// Creates iterative evaluation context.
fn IterEvalContext::new(
  peg : PEG,
  tokens : Array[@types.Tok],
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
  emit_filter? : @hashset.HashSet[String]? = None,
  diagnostics_enabled? : Bool = false,
) -> IterEvalContext {
  let num_nodes = peg.fast_nodes.length()
  let num_positions = tokens.length() + 1
  let memo = create_memo(num_nodes, num_positions)
  let token_ids = compute_token_ids(peg, tokens)
  let token_names = compute_token_names(peg)
  {
    peg,
    tokens,
    token_ids,
    token_names,
    memo,
    num_positions,
    on_rule_match,
    emit_filter,
    diagnostics_enabled,
    furthest_pos: 0,
    furthest_expected: [],
    furthest_expected_set: @hashset.new(),
    work: Array::new(capacity=1024),
    results: Array::new(capacity=256),
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
/// Records a failed token expectation for diagnostic runs.
fn record_token_failure(
  ctx : IterEvalContext,
  pos : Int,
  expected_id : Int,
) -> Unit {
  if !ctx.diagnostics_enabled || pos < ctx.furthest_pos {
    return
  }
  if pos > ctx.furthest_pos {
    ctx.furthest_pos = pos
    ctx.furthest_expected.clear()
    ctx.furthest_expected_set.clear()
  }
  let expected = if expected_id >= 0 && expected_id < ctx.token_names.length() {
    ctx.token_names[expected_id]
  } else {
    ""
  }
  if expected.length() > 0 && !ctx.furthest_expected_set.contains(expected) {
    ctx.furthest_expected_set.add(expected)
    ctx.furthest_expected.push(expected)
  }
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
      LabelCont(label_name) => process_label_cont(ctx, label_name)
      RuleRefCont(rule_name, target_is_rule_ref, start_pos) =>
        process_rule_ref_cont(ctx, rule_name, target_is_rule_ref, start_pos)
      AndCont(node_id, pos) => process_predicate_cont(ctx, node_id, pos, false)
      NotCont(node_id, pos) => process_predicate_cont(ctx, node_id, pos, true)
    }
  }
}

///|
/// Process Eval work item.
fn process_eval(ctx : IterEvalContext, node_id : Int, pos : Int) -> Unit {
  let memo_idx = node_id * ctx.num_positions + pos
  match ctx.memo[memo_idx] {
    Succeeded(end_pos, labels) => {
      let cloned = clone_labels(labels)
      ctx.results.push({ ok: true, end_pos, labels: cloned })
      return
    }
    Failed => {
      ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
      return
    }
    Unknown => ()
  }
  let compiled = ctx.peg.fast_nodes[node_id]
  match compiled {
    FEmpty => {
      let labels = empty_labels()
      ctx.memo[memo_idx] = Succeeded(pos, labels)
      ctx.results.push({ ok: true, end_pos: pos, labels })
    }
    FFail => {
      ctx.memo[memo_idx] = Failed
      ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
    }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        // Use token reference - defer Map creation
        let labels = token_labels(pos)
        ctx.memo[memo_idx] = Succeeded(pos + 1, labels)
        ctx.results.push({ ok: true, end_pos: pos + 1, labels })
      } else {
        record_token_failure(ctx, pos, expected_id)
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
        ctx.work.push(SeqCont(node_id, 0, pos, pos, empty_labels()))
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
      ctx.work.push(StarCont(child, pos, pos, empty_labels()))
      ctx.work.push(Eval(child, pos))
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
      ctx.work.push(LabelCont(label_name))
      ctx.work.push(Eval(child, pos))
    }
    FAnd(child) => {
      ctx.work.push(AndCont(node_id, pos))
      ctx.work.push(Eval(child, pos))
    }
    FNot(child) => {
      ctx.work.push(NotCont(node_id, pos))
      ctx.work.push(Eval(child, pos))
    }
  }
}

///|
/// Process Seq continuation.
fn process_seq_cont(
  ctx : IterEvalContext,
  node_id : Int,
  idx : Int,
  start_pos : Int,
  _current_pos : Int,
  labels : Labels,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if !result.ok {
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: start_pos, labels: empty_labels() })
    return
  }
  let merged = merge_labels(labels, result.labels, ctx.tokens)
  let new_pos = result.end_pos
  let elems = match ctx.peg.fast_nodes[node_id] {
    FSeq(e) => e
    _ => return
  }
  let next_idx = idx + 1
  if next_idx >= elems.length() {
    let memo_idx = node_id * ctx.num_positions + start_pos
    // memo and the downstream result must not share a mutable accumulator:
    // whichever consumer fires next would otherwise see state mutated by
    // the other. The memo entry must survive future `merge_labels` calls.
    ctx.memo[memo_idx] = Succeeded(new_pos, clone_labels(merged))
    ctx.results.push({ ok: true, end_pos: new_pos, labels: merged })
  } else {
    ctx.work.push(SeqCont(node_id, next_idx, start_pos, new_pos, merged))
    ctx.work.push(Eval(elems[next_idx], new_pos))
  }
}

///|
/// Process Choice continuation.
fn process_choice_cont(
  ctx : IterEvalContext,
  node_id : Int,
  idx : Int,
  pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if result.ok {
    let memo_idx = node_id * ctx.num_positions + pos
    ctx.memo[memo_idx] = Succeeded(result.end_pos, clone_labels(result.labels))
    ctx.results.push(result)
    return
  }
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
/// Shared continuation body for repetition operators (`Star` and the
/// "rest" phase of `Plus`). Both must, after an iteration completes:
///   1. accept the iteration (stop looping) when the child failed or made
///      no progress, pushing the accumulated labels as a successful match;
///   2. otherwise, merge the child's labels and re-enter the child.
///
/// The only difference is which work-item variant schedules the next
/// iteration, supplied by `schedule_next`.
fn repetition_cont(
  ctx : IterEvalContext,
  child_id : Int,
  current_pos : Int,
  labels : Labels,
  schedule_next : (Int, Int, Labels) -> WorkItem,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if !result.ok || result.end_pos == current_pos {
    ctx.results.push({ ok: true, end_pos: current_pos, labels })
    return
  }
  let merged = merge_labels(labels, result.labels, ctx.tokens)
  let new_pos = result.end_pos
  ctx.work.push(schedule_next(child_id, new_pos, merged))
  ctx.work.push(Eval(child_id, new_pos))
}

///|
/// Process Star continuation.
fn process_star_cont(
  ctx : IterEvalContext,
  child_id : Int,
  start_pos : Int,
  current_pos : Int,
  labels : Labels,
) -> Unit {
  repetition_cont(ctx, child_id, current_pos, labels, fn(c, p, l) {
    StarCont(c, start_pos, p, l)
  })
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
  if !result.ok {
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: start_pos, labels: empty_labels() })
    return
  }
  let current_pos = result.end_pos
  ctx.work.push(PlusRest(child_id, start_pos, current_pos, result.labels))
  ctx.work.push(Eval(child_id, current_pos))
}

///|
/// Process Plus rest continuation.
fn process_plus_rest(
  ctx : IterEvalContext,
  child_id : Int,
  start_pos : Int,
  current_pos : Int,
  labels : Labels,
) -> Unit {
  repetition_cont(ctx, child_id, current_pos, labels, fn(c, p, l) {
    PlusRest(c, start_pos, p, l)
  })
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
    ctx.memo[memo_idx] = Succeeded(result.end_pos, clone_labels(result.labels))
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
    let labels = to_owned_labels_map(result.labels, ctx.tokens)
    match labels.meta.get(@types.META_LAST) {
      Some(v) => labels.set_meta(label_name, v)
      None => ()
    }
    match labels.meta.get(@types.META_LAST_POS) {
      Some(v) => labels.set_meta(label_name + @types.META_POS_SUFFIX, v)
      None => ()
    }
    match labels.meta.get(@types.META_LAST_LEN) {
      Some(v) => labels.set_meta(label_name + @types.META_LEN_SUFFIX, v)
      None => ()
    }
    publish_primary_text_as(labels, label_name + @types.META_TEXT_SUFFIX)
    ctx.results.push({
      ok: true,
      end_pos: result.end_pos,
      labels: full_labels(labels),
    })
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
  if result.ok && !target_is_rule_ref && should_emit_rule_iter(ctx, rule_name) {
    let labels_map = materialize(result.labels, ctx.tokens)
    labels_map.set(@types.META_START_TOK, start_pos.to_json())
    labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
    (ctx.on_rule_match)(rule_name, labels_map, start_pos, result.end_pos)
  }
  if result.ok {
    // Named labels defined inside the rule must not leak to its caller.
    match result.labels {
      Labels::TokRef(_) | Labels::NoLabels => ctx.results.push(result)
      Labels::Full(map) => {
        let clean = strip_named_labels(map)
        ctx.results.push({
          ok: true,
          end_pos: result.end_pos,
          labels: full_labels(clean),
        })
      }
    }
  } else {
    ctx.results.push(result)
  }
}

///|
/// Process And/Not-predicate continuation (unified).
/// When negate is false, behaves as And-predicate; when true, as Not-predicate.
fn process_predicate_cont(
  ctx : IterEvalContext,
  node_id : Int,
  pos : Int,
  negate : Bool,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  let memo_idx = node_id * ctx.num_positions + pos
  let matched = if negate { !result.ok } else { result.ok }
  if matched {
    let labels = empty_labels()
    ctx.memo[memo_idx] = Succeeded(pos, labels)
    ctx.results.push({ ok: true, end_pos: pos, labels })
  } else {
    ctx.memo[memo_idx] = Failed
    ctx.results.push({ ok: false, end_pos: pos, labels: empty_labels() })
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
    None => (false, Map::new())
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
      (result.ok, final_labels)
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
/// Runs iterative PEG parse and returns EvalResult.
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
