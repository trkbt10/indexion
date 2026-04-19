///|
/// Common types and utilities for PEG evaluators.
/// Shared between recursive and iterative implementations.
///
/// ## Labels accumulation model
///
/// PEG rules accumulate labels across sequence elements and across every
/// iteration of `*`/`+` repetitions. Among those labels, `_text` (and
/// `<name>_text` labels derived from labeled captures) hold the textual span
/// of every token consumed so far — the accumulator grows monotonically for
/// the whole duration of a repetition.
///
/// Representing `_text` as a plain `String` that is rebuilt on every merge
/// makes `Item*` over an N-token file cost O(N^2) string copies, which is
/// the dominant cost on large C++ files (e.g. mozc).
///
/// To avoid this, `Labels` stores the text accumulator as a list of string
/// chunks (a rope). Merges only push new chunks — concatenation happens
/// exactly once, when the labels escape to a rule-match callback or to the
/// final parse result (see `materialize`).

///|
/// A rope-like text accumulator: an ordered list of string chunks that is
/// concatenated lazily at the `materialize` boundary.
priv struct TextRope {
  chunks : Array[String]
}

///|
fn TextRope::empty() -> TextRope {
  { chunks: [] }
}

///|
/// Deep copy — each Labels owner must hold its own chunk array because
/// `merge_into` mutates the target in place.
fn TextRope::clone(self : TextRope) -> TextRope {
  let copy : Array[String] = []
  for c in self.chunks {
    copy.push(c)
  }
  { chunks: copy }
}

///|
fn TextRope::is_empty(self : TextRope) -> Bool {
  self.chunks.length() == 0
}

///|
/// Appends a single chunk in place — O(1) amortized.
fn TextRope::push_chunk(self : TextRope, s : String) -> Unit {
  self.chunks.push(s)
}

///|
/// Appends every chunk of `other` to `self` in place — O(|other|).
fn TextRope::extend(self : TextRope, other : TextRope) -> Unit {
  for c in other.chunks {
    self.chunks.push(c)
  }
}

///|
/// Concatenates all chunks into a single String.
fn TextRope::to_string(self : TextRope) -> String {
  let mut total = 0
  for c in self.chunks {
    total = total + c.length()
  }
  let buf = StringBuilder::new(size_hint=total)
  for c in self.chunks {
    buf.write_string(c)
  }
  buf.to_string()
}

///|
/// A labels accumulator used during PEG evaluation.
///
/// The primary text accumulator (`_text`) is a hot-path field: it grows once
/// per consumed token. Keeping it as a dedicated struct field avoids a
/// hashed `Map.get("_text")` on every merge — that lookup alone dominates
/// profiles on large C++ files. Additional named text captures
/// (`<name>_text`, emitted by labeled sub-trees) live in `extra_texts`, as
/// do ad-hoc meta labels in `meta`.
priv struct LabelsMap {
  text : TextRope
  meta : Map[String, Json]
  extra_texts : Map[String, TextRope]
}

///|
fn LabelsMap::new() -> LabelsMap {
  { text: TextRope::empty(), meta: Map::new(), extra_texts: Map::new() }
}

///|
/// Returns a new LabelsMap sharing no mutable state with `self`.
fn LabelsMap::clone(self : LabelsMap) -> LabelsMap {
  let meta : Map[String, Json] = Map::new()
  for k, v in self.meta {
    meta.set(k, v)
  }
  let extra_texts : Map[String, TextRope] = Map::new()
  for k, v in self.extra_texts {
    extra_texts.set(k, v.clone())
  }
  { text: self.text.clone(), meta, extra_texts }
}

///|
fn LabelsMap::set_meta(self : LabelsMap, key : String, value : Json) -> Unit {
  self.meta.set(key, value)
}

///|
/// Returns the text rope for `key`, allocating if absent. Only use for
/// non-primary (`<name>_text`) keys; the primary `_text` has a dedicated
/// accessor (`self.text`).
fn LabelsMap::get_extra_rope(self : LabelsMap, key : String) -> TextRope {
  match self.extra_texts.get(key) {
    Some(rope) => rope
    None => {
      let rope = TextRope::empty()
      self.extra_texts.set(key, rope)
      rope
    }
  }
}

///|
fn LabelsMap::push_text_chunk(self : LabelsMap, chunk : String) -> Unit {
  self.text.push_chunk(chunk)
}

///|
fn LabelsMap::extend_primary_text(self : LabelsMap, other : TextRope) -> Unit {
  if other.is_empty() {
    return
  }
  self.text.extend(other)
}

///|
fn LabelsMap::extend_extra_text(
  self : LabelsMap,
  key : String,
  other : TextRope,
) -> Unit {
  if other.is_empty() {
    return
  }
  self.get_extra_rope(key).extend(other)
}

///|
/// Lazy labels: defer allocation until actually needed. `TokRef` references
/// a single already-lexed token and materializes on demand; `Full` owns its
/// own LabelsMap accumulator.
priv enum Labels {
  NoLabels // empty
  TokRef(Int) // single-token reference
  Full(LabelsMap) // owned accumulator
}

///|
/// Memo entry states for memoization.
priv enum MemoState {
  Unknown
  Failed
  Succeeded(Int, Labels) // (end_pos, labels)
}

///|
/// FastEvalResult holds evaluation result with lazy labels.
priv struct FastEvalResult {
  ok : Bool
  end_pos : Int
  labels : Labels
}

///|
fn empty_labels() -> Labels {
  Labels::NoLabels
}

///|
fn token_labels(token_idx : Int) -> Labels {
  Labels::TokRef(token_idx)
}

///|
fn full_labels(map : LabelsMap) -> Labels {
  Labels::Full(map)
}

///|
/// Builds a `LabelsMap` for a single token: populates `_last*` metadata and
/// seeds `_text` with the token's textual value.
fn labels_map_from_token(
  tok : @types.Tok,
) -> LabelsMap {
  let out = LabelsMap::new()
  let value = tok.get_value()
  out.set_meta("_last", value.to_json())
  out.set_meta("_last_pos", tok.pos.to_double().to_json())
  out.set_meta("_last_len", tok.text.length().to_double().to_json())
  out.push_text_chunk(value)
  out
}

///|
/// Internal: expands a Labels into an owned `LabelsMap`.
///
/// `Labels::NoLabels` and `Labels::TokRef` allocate fresh maps as usual.
///
/// `Labels::Full(map)` is returned **without cloning**: merging into the same
/// accumulator across thousands of `*` iterations is the hot path, and
/// re-copying the rope+meta maps each step would re-introduce the exact
/// O(N^2) behaviour this refactor is removing.
///
/// The ownership contract is therefore: `merge_labels` takes ownership of
/// `first` and returns a Labels that the caller owns; no one else may hold
/// a handle to `first`. Evaluators enforce this by popping labels off the
/// result/work stacks before merging and by `clone_labels`-ing any Labels
/// pulled out of the memo before it is re-exposed to the result stack (see
/// `process_eval` / `eval_rec`). Every memo write also clones before
/// storing so the memo retains its own independent snapshot.
fn take_owned_labels_map(
  labels : Labels,
  tokens : Array[@types.Tok],
) -> LabelsMap {
  match labels {
    Labels::NoLabels => LabelsMap::new()
    Labels::TokRef(idx) => labels_map_from_token(tokens[idx])
    Labels::Full(map) => map
  }
}

///|
/// Internal: expands a Labels into a freshly-owned `LabelsMap`. Always
/// allocates so the result shares no mutable state with `labels`. Used by
/// label-continuation paths that need to add new keys to an existing
/// accumulator without mutating the original (which is still referenced by
/// the memo or the downstream result stack).
fn to_owned_labels_map(
  labels : Labels,
  tokens : Array[@types.Tok],
) -> LabelsMap {
  match labels {
    Labels::NoLabels => LabelsMap::new()
    Labels::TokRef(idx) => labels_map_from_token(tokens[idx])
    Labels::Full(map) => map.clone()
  }
}

///|
/// Clones labels — every Labels variant that owns mutable state is
/// deep-copied so the result can be safely mutated independently.
fn clone_labels(labels : Labels) -> Labels {
  match labels {
    Labels::NoLabels => Labels::NoLabels
    Labels::TokRef(idx) => Labels::TokRef(idx)
    Labels::Full(map) => Labels::Full(map.clone())
  }
}

///|
/// Merges labels into a target accumulator in place. Text fields are
/// appended chunk-wise (O(1) amortized per token); metadata is overwritten.
fn merge_into(
  target : LabelsMap,
  source : Labels,
  tokens : Array[@types.Tok],
) -> Unit {
  match source {
    Labels::NoLabels => ()
    Labels::TokRef(idx) => {
      let tok = tokens[idx]
      let value = tok.get_value()
      target.push_text_chunk(value)
      target.set_meta("_last", value.to_json())
      target.set_meta("_last_pos", tok.pos.to_double().to_json())
      target.set_meta("_last_len", tok.text.length().to_double().to_json())
    }
    Labels::Full(map) => {
      for key, value in map.meta {
        target.set_meta(key, value)
      }
      target.extend_primary_text(map.text)
      for key, rope in map.extra_texts {
        target.extend_extra_text(key, rope)
      }
    }
  }
}

///|
/// Merges two Labels. Ownership rule: callers relinquish both `first` and
/// `second` to this function. The returned Labels is safe to mutate further
/// (in practice, to feed back as `first` into the next merge).
///
/// Callers must not retain an aliased handle to either argument after the
/// call — the evaluators satisfy this by popping labels off the work stack
/// before merging and by `clone_labels`-ing any value pulled from the memo
/// before it is introduced to the result stack.
fn merge_labels(
  first : Labels,
  second : Labels,
  tokens : Array[@types.Tok],
) -> Labels {
  match (first, second) {
    (Labels::NoLabels, other) => other
    (other, Labels::NoLabels) => other
    (Labels::TokRef(idx1), Labels::TokRef(idx2)) =>
      if idx1 == idx2 {
        Labels::TokRef(idx1)
      } else {
        let map = take_owned_labels_map(first, tokens)
        merge_into(map, second, tokens)
        Labels::Full(map)
      }
    _ => {
      let map = take_owned_labels_map(first, tokens)
      merge_into(map, second, tokens)
      Labels::Full(map)
    }
  }
}

///|
/// Materializes labels into a freshly-allocated output `Map[String, Json]`
/// suitable for external consumption (rule-match callbacks, parse results).
/// This is the single boundary where text ropes are concatenated to strings.
fn materialize(
  labels : Labels,
  tokens : Array[@types.Tok],
) -> Map[String, Json] {
  let out : Map[String, Json] = Map::new()
  match labels {
    Labels::NoLabels => ()
    Labels::TokRef(idx) => {
      let tok = tokens[idx]
      let value = tok.get_value()
      out.set("_last", value.to_json())
      out.set("_last_pos", tok.pos.to_double().to_json())
      out.set("_last_len", tok.text.length().to_double().to_json())
      out.set("_text", value.to_json())
    }
    Labels::Full(map) => {
      for key, value in map.meta {
        out.set(key, value)
      }
      if !map.text.is_empty() {
        out.set("_text", map.text.to_string().to_json())
      }
      for key, rope in map.extra_texts {
        out.set(key, rope.to_string().to_json())
      }
    }
  }
  out
}

///|
/// Publishes the primary `_text` rope of `labels` under a `<name>_text`
/// name. Used by labeled captures (`name:Rule`) to expose the text span of
/// the labeled sub-tree under the caller's chosen label.
fn publish_primary_text_as(labels : LabelsMap, dst_key : String) -> Unit {
  if labels.text.is_empty() {
    return
  }
  labels.extra_texts.set(dst_key, labels.text.clone())
}

///|
/// Keeps only the internal metadata and the primary `_text` accumulator on
/// `labels`, discarding user-defined named labels. Used on rule-ref
/// boundaries: labels defined inside a rule must not escape to its caller.
fn strip_named_labels(labels : LabelsMap) -> LabelsMap {
  let out = LabelsMap::new()
  for key, value in labels.meta {
    if key == "_last" || key == "_last_pos" || key == "_last_len" {
      out.set_meta(key, value)
    }
  }
  if !labels.text.is_empty() {
    out.text.extend(labels.text)
  }
  out
}

///|
/// Pre-computes token IDs for fast matching.
fn compute_token_ids(peg : PEG, tokens : Array[@types.Tok]) -> Array[Int] {
  let token_ids : Array[Int] = Array::make(tokens.length(), -1)
  for i in 0..<tokens.length() {
    let kind = tokens[i].kind
    match peg.get_token_id(kind) {
      Some(id) => token_ids[i] = id
      None => token_ids[i] = -1
    }
  }
  token_ids
}

///|
/// Pre-computes token names by token ID for diagnostics.
fn compute_token_names(peg : PEG) -> Array[String] {
  let token_names : Array[String] = Array::make(peg.token_ids.length(), "")
  for name, id in peg.token_ids {
    if id >= 0 && id < token_names.length() {
      token_names[id] = name
    }
  }
  token_names
}

///|
/// Creates memoization array for PEG evaluation.
fn create_memo(num_nodes : Int, num_positions : Int) -> Array[MemoState] {
  let memo_size = num_nodes * num_positions
  Array::make(memo_size, Unknown)
}
