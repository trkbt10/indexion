///|
/// Extracts a section body by heading marker `=== name`.
fn section(text : String, name : String) -> String {
  let marker = "=== " + name
  let idx = find_substring(text, marker)
  guard idx >= 0 else { return "" }
  let body = substr_from(text, idx + marker.length())
  let split_idx = find_substring(body, "===")
  if split_idx >= 0 {
    substr(body, 0, split_idx)
  } else {
    body
  }
}

///|
/// Extracts language name from the first `language: xxx` line.
fn extract_language(text : String) -> String {
  let lines = split_lines(text)
  for line in lines {
    let trimmed = trim_str(line)
    if starts_with(trimmed, "language:") {
      return trim_str(substr_from(trimmed, 9))
    }
  }
  "generic"
}

///|
/// Parses a full KGF document text into a structured spec.
pub fn parse_kgf(text : String) -> @types.KGFSpec? {
  let language = extract_language(text)
  let tokens = parse_lex(section(text, "lex"))
  let rules = parse_rules(section(text, "grammar"))
  let attrs = parse_attrs(section(text, "attrs"))
  let resolver = parse_resolver(section(text, "resolver"))
  let semantics = parse_semantics(section(text, "semantics"))
  let preprocess = parse_preprocess(section(text, "preprocess"))
  let preprocess_fst = parse_preprocess_fst(section(text, "preprocess_fst"))
  Some(
    @types.KGFSpec::new(
      language,
      tokens~,
      rules~,
      attrs~,
      resolver~,
      semantics~,
      preprocess~,
      preprocess_fst~,
    ),
  )
}

///|
/// Parses preprocess section into list of transducer names.
fn parse_preprocess(text : String) -> Array[String]? {
  let lines = split_lines(text)
  let result : Array[String] = []
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() > 0 && not(starts_with(trimmed, "#")) {
      result.push(trimmed)
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}
