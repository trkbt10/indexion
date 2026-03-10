///|
/// Common types and utilities for PEG evaluators.
/// Shared between recursive and iterative implementations.

///|
/// Lazy labels: defer Map creation until actually needed.
/// TokenRef stores token index - only materialize when labels are accessed.
priv enum Labels {
  NoLabels // Empty labels (no allocation)
  TokRef(Int) // Reference to token at index
  Full(Map[String, Json]) // Materialized labels
}

///|
/// Memo entry states for memoization.
/// Uses Labels for efficient storage.
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
/// Creates empty labels.
fn empty_labels() -> Labels {
  Labels::NoLabels
}

///|
/// Creates token reference labels (deferred materialization).
fn token_labels(token_idx : Int) -> Labels {
  Labels::TokRef(token_idx)
}

///|
/// Creates full labels from a Map.
fn full_labels(map : Map[String, Json]) -> Labels {
  Labels::Full(map)
}

///|
/// Materializes labels to Map for external use.
fn materialize(
  labels : Labels,
  tokens : Array[@types.Tok],
) -> Map[String, Json] {
  match labels {
    Labels::NoLabels => Map::new()
    Labels::TokRef(idx) => {
      let tok = tokens[idx]
      let map : Map[String, Json] = Map::new()
      let value = tok.get_value()
      map.set("_last", value.to_json())
      map.set("_last_pos", tok.pos.to_double().to_json())
      map.set("_last_len", tok.text.length().to_double().to_json())
      map.set("_text", value.to_json())
      map
    }
    Labels::Full(map) => map
  }
}

///|
/// Clones labels (cheap for NoLabels and TokRef).
fn clone_labels(labels : Labels) -> Labels {
  match labels {
    Labels::NoLabels => Labels::NoLabels
    Labels::TokRef(idx) => Labels::TokRef(idx)
    Labels::Full(map) => {
      let cloned : Map[String, Json] = Map::new()
      for key, value in map {
        cloned.set(key, value)
      }
      Labels::Full(cloned)
    }
  }
}

///|
/// Merges labels into a target Map (in place).
/// Special handling for _text: concatenates instead of replacing.
fn merge_into_map(
  target : Map[String, Json],
  source : Labels,
  tokens : Array[@types.Tok],
) -> Unit {
  match source {
    Labels::NoLabels => ()
    Labels::TokRef(idx) => {
      let tok = tokens[idx]
      let value = tok.get_value()
      // _text concatenation
      match target.get("_text") {
        Some(String(base)) => target.set("_text", (base + value).to_json())
        _ => target.set("_text", value.to_json())
      }
      target.set("_last", value.to_json())
      target.set("_last_pos", tok.pos.to_double().to_json())
      target.set("_last_len", tok.text.length().to_double().to_json())
    }
    Labels::Full(map) =>
      for key, value in map {
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
}

///|
/// Merges two Labels into a new Labels.
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
        // Must materialize to merge different tokens
        let map = materialize(first, tokens)
        merge_into_map(map, second, tokens)
        Labels::Full(map)
      }
    _ => {
      let map = materialize(first, tokens)
      merge_into_map(map, second, tokens)
      Labels::Full(map)
    }
  }
}

///|
/// Pre-computes token IDs for fast matching.
fn compute_token_ids(peg : PEG, tokens : Array[@types.Tok]) -> Array[Int] {
  let token_ids : Array[Int] = Array::make(tokens.length(), -1)
  for i = 0; i < tokens.length(); i = i + 1 {
    let kind = tokens[i].kind
    match peg.get_token_id(kind) {
      Some(id) => token_ids[i] = id
      None => token_ids[i] = -1
    }
  }
  token_ids
}

///|
/// Creates memoization array for PEG evaluation.
fn create_memo(num_nodes : Int, num_positions : Int) -> Array[MemoState] {
  let memo_size = num_nodes * num_positions
  Array::make(memo_size, Unknown)
}
