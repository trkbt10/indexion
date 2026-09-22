///|
/// Iterative (trampoline-based) PEG evaluator to avoid stack overflow.
/// Handles large files that would cause SIGSEGV with recursive approach.
/// Optimized to avoid array copying by using indices.
///
/// Common types (MemoState, FastEvalResult, etc.) are defined in eval_common.mbt.

///|
/// Work item for the evaluation stack.
/// Uses Labels for lazy label evaluation.
/// The continuations that accumulate across children (`Seq`, `Star`,
/// `Plus`) also carry the event handle of the children accepted so far, so
/// that abandoning the continuation abandons their events too.
priv enum WorkItem {
  /// Evaluate a node and push result
  Eval(Int, Int) // node_id, pos
  /// Continue Seq: node_id, elem_index, start_pos, current_pos, labels, events
  SeqCont(Int, Int, Int, Int, Labels, Int)
  /// Continue Choice: node_id, alt_index, pos
  ChoiceCont(Int, Int, Int)
  /// Continue Star: child_id, start_pos, current_pos, labels, events
  StarCont(Int, Int, Int, Labels, Int)
  /// Continue Plus first: child_id, node_id, start_pos
  PlusFirst(Int, Int, Int)
  /// Continue Plus rest: child_id, start_pos, current_pos, labels, events
  PlusRest(Int, Int, Int, Labels, Int)
  /// Continue Optional: node_id, pos
  OptionalCont(Int, Int)
  /// Continue Label: label_name
  LabelCont(String)
  /// Continue RuleRef: rule_name, start_pos
  RuleRefCont(String, Int)
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
  /// Arena of pending rule-match events. Nothing here is delivered until the
  /// parse finishes; see the transactional-delivery note in `eval_common.mbt`.
  event_log : EventLog
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
    event_log: EventLog::new(),
    emit_filter,
    diagnostics_enabled,
    furthest_pos: 0,
    furthest_expected: [],
    furthest_expected_set: HashSet([]),
    work: Array(capacity=1024),
    results: Array(capacity=256),
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
      SeqCont(node_id, idx, start_pos, current_pos, labels, events) =>
        process_seq_cont(
          ctx, node_id, idx, start_pos, current_pos, labels, events,
        )
      ChoiceCont(node_id, idx, pos) =>
        process_choice_cont(ctx, node_id, idx, pos)
      StarCont(child_id, start_pos, current_pos, labels, events) =>
        process_star_cont(ctx, child_id, start_pos, current_pos, labels, events)
      PlusFirst(child_id, node_id, start_pos) =>
        process_plus_first(ctx, child_id, node_id, start_pos)
      PlusRest(child_id, start_pos, current_pos, labels, events) =>
        process_plus_rest(ctx, child_id, start_pos, current_pos, labels, events)
      OptionalCont(node_id, pos) => process_optional_cont(ctx, node_id, pos)
      LabelCont(label_name) => process_label_cont(ctx, label_name)
      RuleRefCont(rule_name, start_pos) =>
        process_rule_ref_cont(ctx, rule_name, start_pos)
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
    Succeeded(end_pos, labels, events) => {
      // The event handle is an immutable index, so reusing a memo entry
      // replays exactly the events of the subtree it recorded — and emits
      // nothing while the entry is merely probed.
      let cloned = clone_labels(labels)
      ctx.results.push({ ok: true, end_pos, labels: cloned, events, })
      return
    }
    Failed => {
      ctx.results.push(fail_result(pos))
      return
    }
    Unknown => ()
  }
  let compiled = ctx.peg.fast_nodes[node_id]
  match compiled {
    FEmpty => {
      let labels = empty_labels()
      ctx.memo[memo_idx] = Succeeded(pos, labels, EVENTS_NIL)
      ctx.results.push({ ok: true, end_pos: pos, labels, events: EVENTS_NIL, })
    }
    FFail => {
      ctx.memo[memo_idx] = Failed
      ctx.results.push(fail_result(pos))
    }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        // Use token reference - defer Map creation
        let labels = token_labels(pos)
        ctx.memo[memo_idx] = Succeeded(pos + 1, labels, EVENTS_NIL)
        ctx.results.push({
          ok: true,
          end_pos: pos + 1,
          labels,
          events: EVENTS_NIL,
        })
      } else {
        record_token_failure(ctx, pos, expected_id)
        ctx.memo[memo_idx] = Failed
        ctx.results.push(fail_result(pos))
      }
    // Pure indirection: the definition node it jumps to owns the event, so
    // no continuation is needed — the child's result is this node's result.
    FRuleCall(rule_def_id) => ctx.work.push(Eval(rule_def_id, pos))
    FRuleRef(rule_node_id, name) => {
      ctx.work.push(RuleRefCont(name, pos))
      ctx.work.push(Eval(rule_node_id, pos))
    }
    FSeq(elems) =>
      if elems.length() == 0 {
        let labels = empty_labels()
        ctx.memo[memo_idx] = Succeeded(pos, labels, EVENTS_NIL)
        ctx.results.push({ ok: true, end_pos: pos, labels, events: EVENTS_NIL, })
      } else {
        ctx.work.push(SeqCont(node_id, 0, pos, pos, empty_labels(), EVENTS_NIL))
        ctx.work.push(Eval(elems[0], pos))
      }
    FChoice(alts) =>
      if alts.length() == 0 {
        ctx.memo[memo_idx] = Failed
        ctx.results.push(fail_result(pos))
      } else {
        ctx.work.push(ChoiceCont(node_id, 0, pos))
        ctx.work.push(Eval(alts[0], pos))
      }
    FStar(child) => {
      ctx.work.push(StarCont(child, pos, pos, empty_labels(), EVENTS_NIL))
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
  events : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if !result.ok {
    // The sequence backtracks: `events` names the already-matched prefix's
    // rule instances, which are not part of the parse. Dropping the handle
    // drops them — nothing downstream can reach those arena nodes again.
    let memo_idx = node_id * ctx.num_positions + start_pos
    ctx.memo[memo_idx] = Failed
    ctx.results.push(fail_result(start_pos))
    return
  }
  let merged = merge_labels(labels, result.labels, ctx.tokens)
  let merged_events = ctx.event_log.concat(events, result.events)
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
    // The event handle is immutable, so it is shared as-is.
    ctx.memo[memo_idx] = Succeeded(new_pos, clone_labels(merged), merged_events)
    ctx.results.push({
      ok: true,
      end_pos: new_pos,
      labels: merged,
      events: merged_events,
    })
  } else {
    ctx.work.push(
      SeqCont(node_id, next_idx, start_pos, new_pos, merged, merged_events),
    )
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
    // Only the winning alternative's events survive; a rejected alternative
    // pushed a failure carrying EVENTS_NIL, so its events are already gone.
    let memo_idx = node_id * ctx.num_positions + pos
    ctx.memo[memo_idx] = Succeeded(
      result.end_pos,
      clone_labels(result.labels),
      result.events,
    )
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
    ctx.results.push(fail_result(pos))
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
  events : Int,
  schedule_next : (Int, Int, Labels, Int) -> WorkItem,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if !result.ok || result.end_pos == current_pos {
    // The iteration that failed (or made no progress) is not part of the
    // match; only the events of the accepted iterations are kept.
    ctx.results.push({ ok: true, end_pos: current_pos, labels, events, })
    return
  }
  let merged = merge_labels(labels, result.labels, ctx.tokens)
  let merged_events = ctx.event_log.concat(events, result.events)
  let new_pos = result.end_pos
  ctx.work.push(schedule_next(child_id, new_pos, merged, merged_events))
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
  events : Int,
) -> Unit {
  repetition_cont(ctx, child_id, current_pos, labels, events, fn(c, p, l, e) {
    StarCont(c, start_pos, p, l, e)
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
    ctx.results.push(fail_result(start_pos))
    return
  }
  let current_pos = result.end_pos
  ctx.work.push(
    PlusRest(child_id, start_pos, current_pos, result.labels, result.events),
  )
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
  events : Int,
) -> Unit {
  repetition_cont(ctx, child_id, current_pos, labels, events, fn(c, p, l, e) {
    PlusRest(c, start_pos, p, l, e)
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
    ctx.memo[memo_idx] = Succeeded(
      result.end_pos,
      clone_labels(result.labels),
      result.events,
    )
    ctx.results.push(result)
  } else {
    // The absent branch matched: the failed attempt contributed EVENTS_NIL.
    let memo_idx = node_id * ctx.num_positions + pos
    let labels = empty_labels()
    ctx.memo[memo_idx] = Succeeded(pos, labels, EVENTS_NIL)
    ctx.results.push({ ok: true, end_pos: pos, labels, events: EVENTS_NIL, })
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
      events: result.events,
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
  start_pos : Int,
) -> Unit {
  let result = ctx.results.pop().unwrap()
  if !result.ok {
    ctx.results.push(result)
    return
  }
  // Record this rule's own event *after* its body's events, keeping the
  // accumulated order post-order. An alias rule (`Outer -> Inner`) records
  // here like any other rule: its body already recorded `Inner`, so the
  // handle reads `Inner, Outer`. Nothing is delivered yet — the event only
  // becomes observable if an ancestor keeps this handle.
  let events = if should_emit_rule_iter(ctx, rule_name) {
    let labels_map = materialize(result.labels, ctx.tokens)
    labels_map.set(@types.META_START_TOK, start_pos.to_json())
    labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
    let leaf = ctx.event_log.leaf(rule_name, labels_map)
    ctx.event_log.concat(result.events, leaf)
  } else {
    result.events
  }
  // Named labels defined inside the rule must not leak to its caller.
  match result.labels {
    Labels::TokRef(_) | Labels::NoLabels =>
      ctx.results.push({
        ok: true,
        end_pos: result.end_pos,
        labels: result.labels,
        events,
      })
    Labels::Full(map) => {
      let clean = strip_named_labels(map)
      ctx.results.push({
        ok: true,
        end_pos: result.end_pos,
        labels: full_labels(clean),
        events,
      })
    }
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
  // A lookahead consumes no input and contributes no events: its
  // sub-derivation is a probe, never part of the parse tree.
  if matched {
    let labels = empty_labels()
    ctx.memo[memo_idx] = Succeeded(pos, labels, EVENTS_NIL)
    ctx.results.push({ ok: true, end_pos: pos, labels, events: EVENTS_NIL, })
  } else {
    ctx.memo[memo_idx] = Failed
    ctx.results.push(fail_result(pos))
  }
}

///|
/// Drives the work loop to completion and returns the start rule's result
/// together with the events of the final derivation.
///
/// This is the single delivery point of the iterative evaluator: the events
/// are read out of the arena exactly once, by walking the handle the
/// surviving derivation ended up holding. Attempts that were backtracked
/// over left their arena nodes unreachable, so they are never walked. A
/// partial parse (`end_pos < tokens.length()`) still yields the events of
/// the prefix it did consume.
fn run_iter_to_completion(
  ctx : IterEvalContext,
  start_rule : String,
  body_node_id : Int,
) -> (FastEvalResult, Map[String, Json], Array[(String, Map[String, Json])]) {
  ctx.work.push(Eval(body_node_id, 0))
  eval_iter_loop(ctx)
  let result = ctx.results.pop().unwrap_or(fail_result(0))
  let mut events_handle = result.events
  if result.ok && should_emit_rule_iter(ctx, start_rule) {
    let labels_map = materialize(result.labels, ctx.tokens)
    labels_map.set(@types.META_START_TOK, (0).to_json())
    labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
    let leaf = ctx.event_log.leaf(start_rule, labels_map)
    events_handle = ctx.event_log.concat(events_handle, leaf)
  }
  let events : Array[(String, Map[String, Json])] = []
  ctx.event_log.collect(events_handle, events)
  let final_labels = materialize(result.labels, ctx.tokens)
  (result, final_labels, events)
}

///|
/// Runs iterative PEG parse (internal).
fn run_parse_iter_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  emit_filter : @hashset.HashSet[String]?,
) -> (Bool, Map[String, Json], Array[(String, Map[String, Json])]) {
  let ctx = IterEvalContext::new(peg, tokens, emit_filter~)
  match peg.get_fast_rule_body_id(start_rule) {
    None => (false, Map([]), [])
    Some(body_node_id) => {
      let (result, final_labels, events) = run_iter_to_completion(
        ctx, start_rule, body_node_id,
      )
      (result.ok, final_labels, events)
    }
  }
}

///|
/// Runs iterative PEG parse, handing every event of the final derivation to
/// `on_rule_match`.
///
/// The callback is invoked once per surviving rule instance, in post-order,
/// after parsing completes — not while the parser is still exploring. A rule
/// that matched inside an alternative the parser later rejected is never
/// reported.
pub fn run_parse_iter(
  peg : PEG,
  _spec : @types.KGFSpec,
  start_rule : String,
  tokens : Array[@types.Tok],
  active_rules : @hashset.HashSet[String],
  on_rule_match : (String, Map[String, Json], Int, Int) -> Unit,
) -> Bool {
  let (ok, _, events) = run_parse_iter_internal(
    peg,
    tokens,
    start_rule,
    Some(active_rules),
  )
  deliver_events(events, on_rule_match)
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
  let (ok, final_labels, events) = run_parse_iter_internal(
    peg,
    tokens,
    start_rule,
    Some(active_rules),
  )
  if ok {
    Some(EvalResult::success(tokens.length(), labels=final_labels, events~))
  } else {
    None
  }
}
