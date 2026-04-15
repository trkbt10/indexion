///|
/// Semantic grep queries — structural code search beyond token patterns.

///|
/// A semantic query type.
pub enum SemanticQuery {
  /// Find proxy functions (wrappers that just delegate)
  Proxy
  /// Find functions with body shorter than N lines
  Short(Int)
  /// Find functions with body longer than N lines
  Long(Int)
  /// Find functions with N or more parameters
  ParamsGte(Int)
  /// Find pub declarations without doc comments
  Undocumented
  /// Find functions whose name contains a substring
  NameContains(String)
  /// Vector similarity search — find code similar to a natural language query
  Similar(String, Int) // (query_text, top_k)
}

///|
/// Parse a semantic query string.
/// Returns None for unrecognized queries.
pub fn parse_semantic_query(s : String) -> SemanticQuery? {
  if s == "proxy" {
    return Some(Proxy)
  }
  if s == "undocumented" {
    return Some(Undocumented)
  }
  // Parse "short:N", "long:N", "params-gte:N", "name:substr", "similar:query"
  let colon = find_char(s, ':')
  if colon >= 0 {
    let key = @config.substring(s, 0, colon)
    let val = @config.substring_from(s, colon + 1)
    match key {
      "short" => return Some(Short(@common.parse_int(val)))
      "long" => return Some(Long(@common.parse_int(val)))
      "params-gte" => return Some(ParamsGte(@common.parse_int(val)))
      "name" => return Some(NameContains(val))
      "similar" => return Some(Similar(val, 20))
      _ => return None
    }
  }
  None
}

///|
/// A semantic match result.
pub struct SemanticMatch {
  file : String
  line : Int
  name : String
  kind : String
  detail : String
}

///|
/// Run a semantic query against a single file's tokens.
pub fn run_semantic_query_on_file(
  query : SemanticQuery,
  tokens : Array[@kgf_types.Tok],
  path : String,
  content : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[SemanticMatch] {
  let spec = match registry {
    Some(r) =>
      match r.detect_from_path(path) {
        Some(lang) => r.get_spec(lang)
        None => None
      }
    None => None
  }
  match query {
    Undocumented => query_undocumented(content, path, registry)
    Similar(_, _) => [] // Handled at corpus level in run_similar_search
    _ =>
      // All other queries require a KGF spec
      match spec {
        Some(s) =>
          match query {
            Proxy => query_proxy(content, path, registry, spec=s)
            Short(n) =>
              query_by_length(tokens, path, content, registry, max_lines=n)
            Long(n) =>
              query_by_length(tokens, path, content, registry, min_lines=n)
            ParamsGte(n) =>
              query_by_params(tokens, path, content, registry, min_params=n)
            NameContains(substr) =>
              query_name_contains(tokens, path, content, registry, substr)
            _ => []
          }
        None => []
      }
  }
}

///|
/// Find proxy functions using the existing detect_proxy_functions API.
fn query_proxy(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
  spec~ : @kgf_types.KGFSpec,
) -> Array[SemanticMatch] {
  let proxies = @kgf_features.detect_proxy_functions(
    content,
    path,
    registry,
    spec~,
  )
  let results : Array[SemanticMatch] = []
  for p in proxies {
    results.push({
      file: path,
      line: p.line,
      name: p.name,
      kind: "proxy fn",
      detail: "delegates to " + p.delegate_target,
    })
  }
  results
}

///|
/// Find functions by body line count.
fn query_by_length(
  tokens : Array[@kgf_types.Tok],
  path : String,
  content : String,
  registry : @kgf_registry.KGFRegistry?,
  max_lines? : Int = -1,
  min_lines? : Int = -1,
) -> Array[SemanticMatch] {
  let functions = @kgf_features.extract_functions(content, path, registry)
  let token_lines = build_token_lines(tokens)
  let total_lines = @common.count_lines(content)
  let results : Array[SemanticMatch] = []
  for func in functions {
    let start_line = if func.get_start() < token_lines.length() {
      token_lines[func.get_start()]
    } else {
      1
    }
    let end_line = if func.get_end() > 0 &&
      func.get_end() - 1 < token_lines.length() {
      token_lines[func.get_end() - 1]
    } else {
      total_lines
    }
    let body_lines = end_line - start_line + 1
    let matches = if max_lines >= 0 {
      body_lines <= max_lines
    } else if min_lines >= 0 {
      body_lines >= min_lines
    } else {
      false
    }
    if matches {
      results.push({
        file: path,
        line: start_line,
        name: func.get_name(),
        kind: "fn",
        detail: body_lines.to_string() + " lines",
      })
    }
  }
  results
}

///|
/// Find functions with N or more parameters.
fn query_by_params(
  tokens : Array[@kgf_types.Tok],
  path : String,
  content : String,
  registry : @kgf_registry.KGFRegistry?,
  min_params? : Int = 0,
) -> Array[SemanticMatch] {
  let functions = @kgf_features.extract_functions(content, path, registry)
  let token_lines = build_token_lines(tokens)
  let results : Array[SemanticMatch] = []
  for func in functions {
    let param_count = count_params(tokens, func.get_start(), func.get_end())
    if param_count >= min_params {
      let line = if func.get_start() < token_lines.length() {
        token_lines[func.get_start()]
      } else {
        1
      }
      results.push({
        file: path,
        line,
        name: func.get_name(),
        kind: "fn",
        detail: param_count.to_string() + " params",
      })
    }
  }
  results
}

///|
/// Count parameters in a function signature by counting commas + 1 inside
/// the first LPAREN/RPAREN pair after the function name.
fn count_params(tokens : Array[@kgf_types.Tok], start : Int, end : Int) -> Int {
  // Find first LPAREN
  let mut paren_start = -1
  let mut i = start
  while i < end && i < tokens.length() {
    if tokens[i].get_kind() == "LPAREN" {
      paren_start = i
      break
    }
    i += 1
  }
  if paren_start < 0 {
    return 0
  }
  // Find matching RPAREN
  let mut depth = 0
  let mut comma_count = 0
  let mut has_params = false
  i = paren_start
  while i < end && i < tokens.length() {
    let kind = tokens[i].get_kind()
    if kind == "LPAREN" {
      depth += 1
    } else if kind == "RPAREN" {
      depth -= 1
      if depth == 0 {
        break
      }
    } else if kind == "COMMA" && depth == 1 {
      comma_count += 1
    } else if depth == 1 && kind != "NL" && kind != "WS" && kind != "SKIP" {
      has_params = true
    }
    i += 1
  }
  if has_params {
    comma_count + 1
  } else {
    0
  }
}

///|
/// Find undocumented pub declarations.
fn query_undocumented(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[SemanticMatch] {
  let (declarations, doc_map) = @kgf_declarations.extract_pub_declarations_and_doc_map(
    content, path, registry,
  )
  let results : Array[SemanticMatch] = []
  for decl in declarations {
    match doc_map.get(decl.line) {
      Some(_) => ()
      None =>
        results.push({
          file: path,
          line: decl.line,
          name: decl.name,
          kind: "pub " + decl.kind,
          detail: "no doc comment",
        })
    }
  }
  results
}

///|
/// Find functions whose name contains a substring.
fn query_name_contains(
  tokens : Array[@kgf_types.Tok],
  path : String,
  content : String,
  registry : @kgf_registry.KGFRegistry?,
  substr : String,
) -> Array[SemanticMatch] {
  let functions = @kgf_features.extract_functions(content, path, registry)
  let token_lines = build_token_lines(tokens)
  let results : Array[SemanticMatch] = []
  for func in functions {
    if contains_substring(func.get_name(), substr) {
      let line = if func.get_start() < token_lines.length() {
        token_lines[func.get_start()]
      } else {
        1
      }
      results.push({
        file: path,
        line,
        name: func.get_name(),
        kind: "fn",
        detail: "name matches '" + substr + "'",
      })
    }
  }
  results
}

///|
fn contains_substring(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  let h = haystack.to_array()
  let n = needle.to_array()
  for i = 0; i <= h.length() - n.length(); i = i + 1 {
    let mut matched = true
    for j = 0; j < n.length(); j = j + 1 {
      if h[i + j] != n[j] {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}
