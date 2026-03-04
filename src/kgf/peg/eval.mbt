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
  all_events : Array[(String, Map[String, Json])]
}

///|
/// Creates a new evaluation context.
pub fn EvalContext::new(peg : PEG, tokens : Array[@types.Tok]) -> EvalContext {
  { peg, tokens, memo: Map::new(), all_events: [] }
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

// Trampoline-based evaluation to avoid stack overflow

///|
/// Frame types for the evaluation stack.
enum EvalFrame {
  // Evaluate a node and continue
  EvalNode(Node, Int, MemoKey?)
  // Continue sequence evaluation
  SeqCont(
    Array[Node],
    Int,
    Int,
    Map[String, Json],
    Array[(String, Map[String, Json])],
    Int
  )
  // Continue choice evaluation
  ChoiceCont(Array[Node], Int, Int, Int)
  // Continue star evaluation
  StarCont(
    Node,
    Int,
    Map[String, Json],
    Array[(String, Map[String, Json])],
    Int
  )
  // Continue plus evaluation (after first match)
  PlusCont(
    Node,
    Int,
    Map[String, Json],
    Array[(String, Map[String, Json])],
    Int
  )
  // Optional continuation
  OptionalCont(Int)
  // Apply label
  LabelCont(String, Int)
  // Rule call continuation
  RuleCont(String, Int)
  // Store memo result
  StoreMemo(MemoKey)
}

///|
/// Evaluates nodes using an explicit stack (trampoline).
fn eval_trampoline(
  ctx : EvalContext,
  start_node : Node,
  start_pos : Int,
) -> EvalResult {
  let stack : Array[EvalFrame] = []
  let results : Array[EvalResult] = []

  // Push initial evaluation
  stack.push(EvalNode(start_node, start_pos, None))

  while stack.length() > 0 {
    let frame = stack.pop().unwrap()
    match frame {
      EvalNode(node, pos, memo_key) => {
        // Check memo first
        let key = match memo_key {
          Some(k) => k
          None => make_memo_key(node, pos)
        }
        match ctx.memo.get(key) {
          Some(cached) => {
            results.push(cached)
            continue
          }
          None => ()
        }

        // Push memo storage frame
        stack.push(StoreMemo(key))

        // Evaluate based on node type
        match node {
          Empty => results.push(EvalResult::success(pos))
          Sym(name) =>
            if ctx.peg.is_token(name) {
              // Token match
              if pos < ctx.tokens.length() && ctx.tokens[pos].kind == name {
                let tok = ctx.tokens[pos]
                let labels : Map[String, Json] = Map::new()
                labels.set("_last", tok.get_value().to_json())
                labels.set("_last_pos", tok.pos.to_double().to_json())
                labels.set("_last_len", tok.text.length().to_double().to_json())
                results.push(EvalResult::success(pos + 1, labels~))
              } else {
                results.push(EvalResult::failure(pos))
              }
            } else {
              // Rule reference
              stack.push(RuleCont(name, pos))
              match ctx.peg.get_rule(name) {
                Some(rule_node) => stack.push(EvalNode(rule_node, pos, None))
                None => results.push(EvalResult::failure(pos))
              }
            }
          Seq(elems) =>
            if elems.length() == 0 {
              results.push(EvalResult::success(pos))
            } else {
              // Push continuation for sequence
              stack.push(SeqCont(elems, 1, pos, Map::new(), [], pos))
              // Evaluate first element
              stack.push(EvalNode(elems[0], pos, None))
            }
          Choice(alts) =>
            if alts.length() == 0 {
              results.push(EvalResult::failure(pos))
            } else {
              // Push continuation for trying next alternatives
              stack.push(ChoiceCont(alts, 1, pos, pos))
              // Try first alternative
              stack.push(EvalNode(alts[0], pos, None))
            }
          Star(child) => {
            // Push continuation for star
            stack.push(StarCont(child, pos, Map::new(), [], pos))
            // Try first match
            stack.push(EvalNode(child, pos, None))
          }
          Plus(child) => {
            // Push continuation for plus (requires at least one match)
            stack.push(PlusCont(child, pos, Map::new(), [], pos))
            // Try first match
            stack.push(EvalNode(child, pos, None))
          }
          Optional(child) => {
            // Optional always succeeds - if child fails, return success at original pos
            stack.push(OptionalCont(pos))
            stack.push(EvalNode(child, pos, None))
          }
          Label(name, child) => {
            stack.push(LabelCont(name, pos))
            stack.push(EvalNode(child, pos, None))
          }
        }
      }
      SeqCont(elems, idx, orig_pos, labels, events, current_pos) => {
        // Get result of previous element
        let prev = results.pop().unwrap()
        if not(prev.ok) {
          results.push(EvalResult::failure(orig_pos))
        } else {
          let new_labels = merge_labels(labels, prev.labels)
          let new_events = append_events(events, prev.events)
          let new_pos = prev.pos
          if idx >= elems.length() {
            // All elements matched
            results.push(
              EvalResult::success(new_pos, labels=new_labels, events=new_events),
            )
          } else {
            // Continue with next element
            stack.push(
              SeqCont(elems, idx + 1, orig_pos, new_labels, new_events, new_pos),
            )
            stack.push(EvalNode(elems[idx], new_pos, None))
          }
        }
      }
      ChoiceCont(alts, idx, orig_pos, _) => {
        // Get result of previous alternative
        let prev = results.pop().unwrap()
        if prev.ok {
          // Found a match
          results.push(prev)
        } else if idx >= alts.length() {
          // No more alternatives
          results.push(EvalResult::failure(orig_pos))
        } else {
          // Try next alternative
          stack.push(ChoiceCont(alts, idx + 1, orig_pos, orig_pos))
          stack.push(EvalNode(alts[idx], orig_pos, None))
        }
      }
      OptionalCont(orig_pos) => {
        // Optional always succeeds
        let prev = results.pop().unwrap()
        if prev.ok {
          results.push(prev)
        } else {
          // Child failed, but optional succeeds at original position
          results.push(EvalResult::success(orig_pos))
        }
      }
      StarCont(child, start_pos, labels, events, current_pos) => {
        // Get result of previous iteration
        let prev = results.pop().unwrap()
        if not(prev.ok) || prev.pos == current_pos {
          // No match or no progress - done with star
          results.push(EvalResult::success(current_pos, labels~, events~))
        } else {
          // Continue iterating
          let new_labels = merge_labels(labels, prev.labels)
          let new_events = append_events(events, prev.events)
          stack.push(
            StarCont(child, start_pos, new_labels, new_events, prev.pos),
          )
          stack.push(EvalNode(child, prev.pos, None))
        }
      }
      PlusCont(child, start_pos, labels, events, current_pos) => {
        // Get result of previous iteration
        let prev = results.pop().unwrap()
        if labels.length() == 0 && events.length() == 0 {
          // This is the first iteration
          if not(prev.ok) {
            // Plus requires at least one match
            results.push(EvalResult::failure(start_pos))
          } else {
            // First match succeeded, continue like star
            stack.push(
              StarCont(child, start_pos, prev.labels, prev.events, prev.pos),
            )
            stack.push(EvalNode(child, prev.pos, None))
          }
          // Subsequent iterations - same as star
        } else if not(prev.ok) || prev.pos == current_pos {
          results.push(EvalResult::success(current_pos, labels~, events~))
        } else {
          let new_labels = merge_labels(labels, prev.labels)
          let new_events = append_events(events, prev.events)
          stack.push(
            StarCont(child, start_pos, new_labels, new_events, prev.pos),
          )
          stack.push(EvalNode(child, prev.pos, None))
        }
      }
      LabelCont(name, orig_pos) => {
        let prev = results.pop().unwrap()
        if not(prev.ok) {
          results.push(EvalResult::failure(orig_pos))
        } else {
          let labels = prev.labels
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
          results.push(
            EvalResult::success(prev.pos, labels~, events=prev.events),
          )
        }
      }
      RuleCont(name, _orig_pos) => {
        let prev = results.pop().unwrap()
        if prev.ok {
          // Emit event for this matched rule
          let event_labels : Map[String, Json] = Map::new()
          for key, value in prev.labels {
            event_labels.set(key, value)
          }
          ctx.all_events.push((name, event_labels))
          // Clean labels - only keep _last for parent scope
          let clean_labels : Map[String, Json] = Map::new()
          match prev.labels.get("_last") {
            Some(v) => clean_labels.set("_last", v)
            None => ()
          }
          match prev.labels.get("_last_pos") {
            Some(v) => clean_labels.set("_last_pos", v)
            None => ()
          }
          match prev.labels.get("_last_len") {
            Some(v) => clean_labels.set("_last_len", v)
            None => ()
          }
          results.push(
            EvalResult::success(
              prev.pos,
              labels=clean_labels,
              events=prev.events,
            ),
          )
        } else {
          results.push(prev)
        }
      }
      StoreMemo(key) => {
        // Get result and store in memo, then push back
        let result = results.pop().unwrap()
        ctx.memo.set(key, result)
        results.push(result)
      }
    }
  }

  if results.length() > 0 {
    results.pop().unwrap()
  } else {
    EvalResult::failure(start_pos)
  }
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

  // Get start rule AST
  match peg.get_rule(start_rule) {
    None => None
    Some(node) => {
      let result = eval_trampoline(ctx, node, 0)
      if result.ok {
        // Merge all rule match events into the result
        let merged_events = append_events(result.events, ctx.all_events)
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
