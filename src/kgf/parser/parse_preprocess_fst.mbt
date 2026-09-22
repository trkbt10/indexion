///|
/// # KGF Preprocess FST Section Syntax
///
/// The `=== preprocess_fst` section defines Finite State Transducers (FST)
/// for text preprocessing. FSTs transform input text character-by-character
/// using state machines. Common uses: Base64 decoding, escape handling.
///
/// ## JSON Schema
///
/// ```json
/// {
///   "name": "fst-name",
///   "initial": "state-name",
///   "classes": {
///     "class-name": "regex-pattern",
///     ...
///   },
///   "states": {
///     "state-name": [
///       { "on": "class-or-*", "to": "next-state", "actions": [...] },
///       ...
///     ],
///     ...
///   }
/// }
/// ```
///
/// ## Character Classes
///
/// Define character sets for transition matching:
/// ```json
/// "classes": {
///   "b64char": "[A-Za-z0-9+/]",
///   "padding": "[=]",
///   "digit": "[0-9]",
///   "hex": "[0-9a-fA-F]"
/// }
/// ```
///
/// ## Transitions
///
/// Each state has an array of transitions. First matching transition wins.
/// Use `"on": "*"` for wildcard (match any character).
///
/// ## Actions
///
/// | Action | Description |
/// |--------|-------------|
/// | `{"type": "emitInput"}` | Emit the current input character |
/// | `{"type": "emit", "value": "X"}` | Emit a specific string |
/// | `{"type": "buf"}` | Buffer the input character |
/// | `{"type": "flush", "pad": N}` | Flush buffer with padding (0, 1, 2) |
///
/// ## Example: Base64 Decoder
///
/// ```json
/// === preprocess_fst
/// {
///   "name": "base64",
///   "initial": "s0",
///   "classes": {
///     "b64": "[A-Za-z0-9+/]",
///     "eq": "[=]"
///   },
///   "states": {
///     "s0": [
///       {"on": "b64", "to": "s1", "actions": [{"type": "buf"}]}
///     ],
///     "s1": [
///       {"on": "b64", "to": "s2", "actions": [{"type": "buf"}]}
///     ],
///     "s2": [
///       {"on": "b64", "to": "s3", "actions": [{"type": "buf"}]},
///       {"on": "eq", "to": "s3p1", "actions": []}
///     ],
///     "s3": [
///       {"on": "b64", "to": "s0", "actions": [{"type": "buf"}, {"type": "flush", "pad": 0}]},
///       {"on": "eq", "to": "s0", "actions": [{"type": "flush", "pad": 1}]}
///     ],
///     "s3p1": [
///       {"on": "eq", "to": "s0", "actions": [{"type": "flush", "pad": 2}]}
///     ]
///   }
/// }
/// ```

///|
/// Parses preprocess_fst section as JSON (single object or array).
/// Returns None if the section is empty.
pub fn parse_preprocess_fst(text : String) -> Array[@types.PreprocessFstSpec]? {
  let trimmed = trim_str(text)
  if trimmed.length() == 0 {
    return None
  }
  let json : Json = @json.parse(trimmed) catch { _ => return None }
  // Handle array of specs
  if json is Array(arr) {
    let result : Array[@types.PreprocessFstSpec] = []
    for item in arr {
      match parse_single_fst_spec(item) {
        Some(spec) => result.push(spec)
        None => return None
      }
    }
    return Some(result)
  }
  // Handle single object
  match parse_single_fst_spec(json) {
    Some(spec) => Some([spec])
    None => None
  }
}

///|
/// Parses a single FST spec from JSON.
fn parse_single_fst_spec(json : Json) -> @types.PreprocessFstSpec? {
  // Validate required fields
  guard json
    is {
      "name": String(name),
      "initial": String(initial),
      "classes": Object(classes_json),
      "states": Object(states_json),
      ..
    } else {
    return None
  }
  // Parse character classes
  let classes : Map[String, String] = Map([])
  for entry in classes_json {
    let class_name = entry.0
    if entry.1 is String(pattern) {
      classes.set(class_name, pattern)
    } else {
      return None
    }
  }
  // Parse states
  let states : Map[String, Array[@types.FstTransition]] = Map([])
  for entry in states_json {
    let state_name = entry.0
    if entry.1 is Array(transitions_json) {
      let transitions : Array[@types.FstTransition] = []
      for t_json in transitions_json {
        match parse_fst_transition(t_json) {
          Some(t) => transitions.push(t)
          None => return None
        }
      }
      states.set(state_name, transitions)
    } else {
      return None
    }
  }
  Some(@types.PreprocessFstSpec::new(name, classes, initial, states))
}

///|
/// Parses a single FST transition from JSON.
fn parse_fst_transition(json : Json) -> @types.FstTransition? {
  guard json
    is {
      "on": String(on),
      "to": String(to),
      "actions": Array(actions_json),
      ..
    } else {
    return None
  }
  let actions : Array[@types.FstAction] = []
  for a_json in actions_json {
    match parse_fst_action(a_json) {
      Some(a) => actions.push(a)
      None => return None
    }
  }
  Some(@types.FstTransition::new(on, to, actions))
}

///|
/// Parses a single FST action from JSON.
fn parse_fst_action(json : Json) -> @types.FstAction? {
  guard json is { "type": String(action_type), .. } else { return None }
  match action_type {
    "emitInput" => Some(@types.FstAction::emit_input())
    "emit" =>
      if json is { "value": String(value), .. } {
        Some(@types.FstAction::emit(value))
      } else {
        None
      }
    "buf" => Some(@types.FstAction::buf())
    "flush" =>
      if json is { "pad": Number(pad, ..), .. } {
        Some(@types.FstAction::flush(pad.to_int()))
      } else {
        None
      }
    _ => None
  }
}
