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
  let memo = create_memo(num_nodes, num_positions)
  let token_ids = compute_token_ids(peg, tokens)
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
      // Clone labels (cheap for TokRef)
      let cloned = clone_labels(labels)
      return { ok: true, end_pos, labels: cloned }
    }
    Failed => return { ok: false, end_pos: pos, labels: empty_labels() }
    Unknown => ()
  }
  let result = eval_node_rec(ctx, node_id, pos)
  if result.ok {
    // Store an independent copy in the memo so future hits hand out a
    // pristine accumulator even if the current caller mutates `result`.
    ctx.memo[memo_idx] = Succeeded(result.end_pos, clone_labels(result.labels))
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
    FFail => { ok: false, end_pos: pos, labels: empty_labels() }
    FToken(expected_id) =>
      if pos < ctx.tokens.length() && ctx.token_ids[pos] == expected_id {
        // Use token reference - defer Map creation
        { ok: true, end_pos: pos + 1, labels: token_labels(pos) }
      } else {
        { ok: false, end_pos: pos, labels: empty_labels() }
      }
    FRuleRef(rule_node_id, name) => {
      let target_is_rule_ref = match ctx.peg.fast_nodes.get(rule_node_id) {
        Some(FRuleRef(_, _)) => true
        _ => false
      }
      let result = eval_rec(ctx, rule_node_id, pos)
      if result.ok && !target_is_rule_ref && should_emit_rule_rec(ctx, name) {
        let labels_map = materialize(result.labels, ctx.tokens)
        labels_map.set(@types.META_START_TOK, pos.to_json())
        labels_map.set(@types.META_END_TOK, result.end_pos.to_json())
        (ctx.on_rule_match)(name, labels_map, pos, result.end_pos)
      }
      if result.ok {
        // Named labels defined inside the rule must not leak to its caller.
        match result.labels {
          Labels::TokRef(_) | Labels::NoLabels => result
          Labels::Full(map) => {
            let clean = strip_named_labels(map)
            { ok: true, end_pos: result.end_pos, labels: full_labels(clean) }
          }
        }
      } else {
        result
      }
    }
    FSeq(elems) => {
      let mut current_pos = pos
      let mut labels = empty_labels()
      for elem_id in elems {
        let result = eval_rec(ctx, elem_id, current_pos)
        if !result.ok {
          return { ok: false, end_pos: pos, labels: empty_labels() }
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
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
      let mut labels = empty_labels()
      while true {
        let result = eval_rec(ctx, child, current_pos)
        if !result.ok || result.end_pos == current_pos {
          break
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
        current_pos = result.end_pos
      }
      { ok: true, end_pos: current_pos, labels }
    }
    FPlus(child) => {
      let first = eval_rec(ctx, child, pos)
      if !first.ok {
        return { ok: false, end_pos: pos, labels: empty_labels() }
      }
      let mut labels = first.labels
      let mut current_pos = first.end_pos
      while true {
        let result = eval_rec(ctx, child, current_pos)
        if !result.ok || result.end_pos == current_pos {
          break
        }
        labels = merge_labels(labels, result.labels, ctx.tokens)
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
        { ok: true, end_pos: result.end_pos, labels: full_labels(labels) }
      } else {
        result
      }
    }
    FAnd(child) => {
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        { ok: true, end_pos: pos, labels: empty_labels() }
      } else {
        { ok: false, end_pos: pos, labels: empty_labels() }
      }
    }
    FNot(child) => {
      let result = eval_rec(ctx, child, pos)
      if result.ok {
        { ok: false, end_pos: pos, labels: empty_labels() }
      } else {
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
    None => (false, Map::new())
    Some(body_node_id) => {
      let result = eval_rec(ctx, body_node_id, 0)
      if result.ok && should_emit_rule_rec(ctx, start_rule) {
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
