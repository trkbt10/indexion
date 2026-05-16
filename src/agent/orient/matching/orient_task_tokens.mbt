///|
type LocalFileBrief = @types.LocalFileBrief

///|
type LocalTermRank = @types.LocalTermRank

///|
type AgentOrientMap = @types.AgentOrientMap

///|
type AgentOrientMapFile = @types.AgentOrientMapFile

///|
/// Tokenize orientation task and summary text into canonical matching terms.
pub fn task_tokens(text : String) -> Array[String] {
  collect_orient_tokens(text, unique=true)
}

///|
pub fn task_token_stream(text : String) -> Array[String] {
  collect_orient_tokens(text, unique=false)
}

///|
pub fn collect_orient_tokens(text : String, unique~ : Bool) -> Array[String] {
  let result : Array[String] = []
  // Side index for O(1) dedup membership. The legacy `result.contains(_)`
  // scan turned into O(N²) on large documents (e.g. multi-MB HTML
  // fixtures) and dominated cold-cache orient time. Building the map
  // alongside the array preserves insertion order in `result` while
  // keeping the dedup cost constant.
  let seen : Map[String, Unit] = {}
  for token in @tokenizer.extract_word_tokens(@tokenizer.normalize_text(text)) {
    push_orient_token(result, seen, token, unique~)
    for part in split_orient_token(token) {
      push_orient_token(result, seen, part, unique~)
    }
  }
  result
}

///|
pub fn push_orient_token(
  result : Array[String],
  seen : Map[String, Unit],
  token : String,
  unique~ : Bool,
) -> Unit {
  let canonical = canonical_orient_token(token)
  if canonical.length() < 2 {
    return
  }
  if unique {
    if seen.contains(canonical) {
      return
    }
    seen.set(canonical, ())
  }
  result.push(canonical)
}

///|
pub fn split_orient_token(token : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for ch in token {
    if ch == '-' || ch == '_' {
      let part = buf.to_string()
      if part.length() > 0 {
        parts.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

///|
pub fn canonical_orient_token(token : String) -> String {
  if token.length() > 5 && token.has_suffix("ies") {
    return @config_paths.substring(token, 0, token.length() - 3) + "y"
  }
  if token.length() > 5 &&
    (
      token.has_suffix("sses") ||
      token.has_suffix("ches") ||
      token.has_suffix("shes") ||
      token.has_suffix("xes") ||
      token.has_suffix("zes")
    ) {
    return @config_paths.substring(token, 0, token.length() - 2)
  }
  if token.length() > 4 && token.has_suffix("s") && !token.has_suffix("ss") {
    return @config_paths.substring(token, 0, token.length() - 1)
  }
  token
}

///|
pub fn matched_terms_in_tokens(
  task_terms : Array[String],
  text_terms : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for term in task_terms {
    if text_terms.contains(term) {
      result.push(term)
    }
  }
  result
}
