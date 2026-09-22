///|
/// Recursive PEG evaluator - fast but can stack overflow on very large files.
/// Use for files with < 10000 tokens.
///
/// Common types (MemoState, FastEvalResult, etc.) are defined in eval_common.mbt.

///|
/// Recursive evaluation context.
priv struct RecEvalContext {
  peg : PEG
  tokens : Array[@types.Tok]
  token_ids : Array[Int]
  memo : Array[MemoState]
  num_positions : Int
  /// Arena of pending rule-match events. Nothing here is delivered until the
  /// start rule succeeds; see the transactional-delivery note in
  /// `eval_common.mbt`.
  event_log : EventLog
  emit_filter : @hashset.HashSet[String]?
}

///|
/// Creates recursive evaluation context.
fn RecEvalContext::new(
  peg : PEG,
  tokens : Array[@types.Tok],
  emit_filter? : @hashset.HashSet[String]? = None,
) -> RecEvalContext {
  let num_nodes = peg.fast_nodes.length()
  let num_positions = tokens.length() + 1
  let memo = create_memo(num_nodes, num_positions)
  let token_ids = compute_token_ids(peg, tokens)
  {
    peg,
    tokens,
    token_ids,
    memo,
    num_positions,
    event_log: EventLog::new(),
    emit_filter,
  }
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
    Succeeded(end_pos, labels, events) => {
      // Clone labels (cheap for TokRef). The event handle is an immutable
      // index, so replaying the memoized subtree's events is just reusing it.
      let cloned = clone_labels(labels)
      return { ok: true, end_pos, labels: cloned, events, }
    }
    Failed =>
      return {
        ok: false,
        end_pos: pos,
        labels: empty_labels(),
        events: EVENTS_NIL,
      }
    Unknown => ()
  }
  let result = eval_node_rec(ctx, node_id, pos)
  if result.ok {
    // Store an independent copy in the memo so future hits hand out a
    // pristine accumulator even if the current caller mutates `result`.
    ctx.memo[memo_idx] = Succeeded(
      result.end_pos,
      clone_labels(result.labels),
      result.events,
    )
  } else {
    ctx.memo[memo_idx] = Failed
  }
  result
}

///|
/// Evaluate a single node recursively.
///
/// Every branch is responsible for the event handles of its children:
/// a construct that *accepts* a child concatenates the child's handle into
/// its own (post-order: children first), and a construct that *rejects* a
/// child simply returns `EVENTS_NIL`, discarding whatever that failed
/// attempt produced. That discard is what makes delivery transactional.
fn eval_node_rec(
  ctx : RecEvalContext,
  node_id : Int,
  pos : Int,
) -> FastEvalResult {
  let compiled = ctx.peg.fast_nodes[node_id]
  match compiled {
    FEmpty =>
      { ok: true, end_pos: pos, labels: empty_labels(), events: EVENTS_NIL, }
    FFail =>
      { ok: false, end_pos: pos, labels: empty_labels(), events: EVENTS_NIL, }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        // Use token reference - defer Map creation
        {
          ok: true,
          end_pos: pos + 1,
          labels: token_labels(pos),
          events: EVENTS_NIL,
        }
      } else {
        { ok: false, end_pos: pos, labels: empty_labels(), events: EVENTS_NIL, }
      }
    // Pure indirection: the definition node it jumps to owns the event.
    FRuleCall(rule_def_id) => eval_rec(ctx, rule_def_id, pos)
    FRuleRef(rule_node_id, name) => {
      let result = eval_rec(ctx, rule_node_id, pos)
      if !result.ok {
        return result
      }
      // Record this rule's own event *after* its body's events, so the
      // accumulated order stays post-order. Nothing is delivered here: the
      // handle only becomes observable if an ancestor keeps it.
      let events = if should_emit_rule_rec(ctx, name) {
        let labels_map = materialize(result.labels, ctx.tokens)
        labels_map.set(@types.META_START_TOK, pos.to_json())
        labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
        let leaf = ctx.event_log.leaf(name, labels_map)
        ctx.event_log.concat(result.events, leaf)
      } else {
        result.events
      }
      // Named labels defined inside the rule must not leak to its caller.
      match result.labels {
        Labels::TokRef(_) | Labels::NoLabels =>
          { ok: true, end_pos: result.end_pos, labels: result.labels, events, }
        Labels::Full(map) => {
          let clean = strip_named_labels(map)
          {
            ok: true,
            end_pos: result.end_pos,
            labels: full_labels(clean),
            events,
          }
        }
      }
    }
    FSeq(elems) => {
      let mut current_pos = pos
      let mut labels = empty_labels()
      let mut events = EVENTS_NIL
      for elem_id in elems {
        let result = eval_rec(ctx, elem_id, current_pos)
        if !result.ok {
          // The sequence backtracks: every event the already-matched prefix
          // produced belongs to a derivation that is not in the parse.
          return {
            ok: false,
            end_pos: pos,
            labels: empty_labels(),
            events: EVENTS_NIL,
          }
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
        events = ctx.event_log.concat(events, result.events)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels, events, }
    }
    FChoice(alts) => {
      for alt_id in alts {
        let result = eval_rec(ctx, alt_id, pos)
        if result.ok {
          // Only the winning alternative's events survive; the rejected
          // ones were already dropped by returning EVENTS_NIL above.
          return result
        }
      }
      { ok: false, end_pos: pos, labels: empty_labels(), events: EVENTS_NIL, }
    }
    FStar(child) => {
      let mut current_pos = pos
      let mut labels = empty_labels()
      let mut events = EVENTS_NIL
      while true {
        let result = eval_rec(ctx, child, current_pos)
        // The iteration that fails (or stalls) is not part of the match, so
        // its events are dropped with it.
        if !result.ok || result.end_pos == current_pos {
          break
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
        events = ctx.event_log.concat(events, result.events)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels, events, }
    }
    FPlus(child) => {
      let first = eval_rec(ctx, child, pos)
      if !first.ok {
        return {
          ok: false,
          end_pos: pos,
          labels: empty_labels(),
          events: EVENTS_NIL,
        }
      }
      let mut labels = first.labels
      let mut events = first.events
      let mut current_pos = first.end_pos
      while true {
        let result = eval_rec(ctx, child, current_pos)
        if !result.ok || result.end_pos == current_pos {
          break
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
        events = ctx.event_log.concat(events, result.events)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels, events, }
    }
    FOptional(child) => {
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        result
      } else {
        // The absent branch matched: the failed attempt's events go away.
        { ok: true, end_pos: pos, labels: empty_labels(), events: EVENTS_NIL, }
      }
    }
    FLabel(label_name, child) => {
      let result = eval_rec(ctx, child, pos)
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
        {
          ok: true,
          end_pos: result.end_pos,
          labels: full_labels(labels),
          events: result.events,
        }
      } else {
        result
      }
    }
    // Predicates consume no input and contribute no events: a lookahead is
    // a probe, and its sub-derivation is never part of the parse tree.
    FAnd(child) => {
      let result = eval_rec(ctx, child, pos)
      {
        ok: result.ok,
        end_pos: pos,
        labels: empty_labels(),
        events: EVENTS_NIL,
      }
    }
    FNot(child) => {
      let result = eval_rec(ctx, child, pos)
      {
        ok: !result.ok,
        end_pos: pos,
        labels: empty_labels(),
        events: EVENTS_NIL,
      }
    }
  }
}

///|
/// Runs recursive PEG parse (internal).
///
/// Returns the raw result plus the events of the final derivation, in
/// post-order, each rule instance exactly once. Events accumulated by
/// attempts that were backtracked over are unreachable from the returned
/// handle and are therefore never collected.
fn run_parse_rec_internal(
  peg : PEG,
  tokens : Array[@types.Tok],
  start_rule : String,
  emit_filter : @hashset.HashSet[String]?,
) -> (Bool, Map[String, Json], Array[(String, Map[String, Json])]) {
  let ctx = RecEvalContext::new(peg, tokens, emit_filter~)
  match peg.get_fast_rule_body_id(start_rule) {
    None => (false, Map([]), [])
    Some(body_node_id) => {
      let result = eval_rec(ctx, body_node_id, 0)
      let mut events_handle = result.events
      if result.ok && should_emit_rule_rec(ctx, start_rule) {
        let labels_map = materialize(result.labels, ctx.tokens)
        labels_map.set(@types.META_START_TOK, (0).to_json())
        labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
        let leaf = ctx.event_log.leaf(start_rule, labels_map)
        events_handle = ctx.event_log.concat(events_handle, leaf)
      }
      // Delivery happens exactly here, once, for the surviving derivation.
      // A partial parse still delivers the events of the prefix it consumed.
      let events : Array[(String, Map[String, Json])] = []
      ctx.event_log.collect(events_handle, events)
      let final_labels = materialize(result.labels, ctx.tokens)
      (result.ok, final_labels, events)
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
  let (ok, final_labels, events) = run_parse_rec_internal(
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
