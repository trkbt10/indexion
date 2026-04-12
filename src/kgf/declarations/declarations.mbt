///|
pub struct PubDeclaration {
  kind : String
  name : String
  line : Int
  start_pos : Int
  end_pos : Int
  category : String
  end_line : Int
  start_tok : Int // token index (inclusive), -1 if unavailable
  end_tok : Int // token index (exclusive), -1 if unavailable
}

///|
priv struct DeclarationSpan {
  line : Int
  start_pos : Int
  end_pos : Int
  end_line : Int
  start_tok : Int
  end_tok : Int
}

///|
/// Span selection preference for declaration matching.
pub(all) enum SpanPreference {
  /// Prefer the longest span containing the name (captures full declaration + body).
  Longest
  /// Prefer the shortest span containing the name (pinpoints the declaration itself).
  Shortest
}

///|
/// Visibility filter for declaration extraction.
pub(all) enum DeclarationVisibility {
  /// All declarations regardless of visibility (uses parse events + attrs directly).
  All
  /// Public declarations only (uses semantics evaluation with `when` conditions).
  PublicOnly
}

///|
fn preprocess_content(content : String, spec : @kgf_types.KGFSpec) -> String {
  match spec.get_preprocess() {
    Some(steps) =>
      @kgf_preprocess.apply_preprocess(
        content,
        Some(steps),
        spec.get_preprocess_fst(),
      ) catch {
        _ => panic()
      }
    None => content
  }
}

///|
fn to_lower_str(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    let code = c.to_int()
    if code >= 0x41 && code <= 0x5A {
      result.push((code + 32).unsafe_to_char())
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}

///|
pub fn tokenize_source(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[@kgf_types.Tok]? {
  let reg = match registry {
    Some(r) => r
    None => return None
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => return None
  }
  let spec = match reg.get_spec(lang) {
    Some(s) => s
    None => return None
  }
  let prepared = preprocess_content(content, spec)
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  Some(lexer.tokenize(prepared))
}

///|
fn is_doc_token_kind(kind : String) -> Bool {
  kind.has_prefix("Doc")
}

///|
pub fn extract_doc_map(tokens : Array[@kgf_types.Tok]) -> Map[Int, String] {
  let result : Map[Int, String] = {}
  let token_lines = build_token_lines(tokens)
  let mut i = 0
  while i < tokens.length() {
    let kind = tokens[i].get_kind()
    if is_doc_token_kind(kind) {
      let doc_buf = StringBuilder::new()
      let mut first = true
      while i < tokens.length() {
        let k = tokens[i].get_kind()
        if is_doc_token_kind(k) {
          let value = tokens[i].get_value()
          if value.length() > 0 {
            if !first {
              doc_buf.write_string("\n")
            }
            doc_buf.write_string(value)
            first = false
          }
          i += 1
        } else if k == "NL" || k == "SKIP" || k == "WS" {
          i += 1
        } else {
          break
        }
      }
      let doc = doc_buf.to_string()
      if doc.length() > 0 && i < tokens.length() {
        let target_line = if i < token_lines.length() {
          token_lines[i]
        } else {
          1
        }
        result.set(target_line, doc)
      }
    } else {
      i += 1
    }
  }
  result
}

///|
fn build_token_lines(tokens : Array[@kgf_types.Tok]) -> Array[Int] {
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  token_lines
}

///|
pub fn extract_doc_map_from_source(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Map[Int, String] {
  match tokenize_source(content, path, registry) {
    Some(tokens) => extract_doc_map(tokens)
    None => {}
  }
}

///|
/// Result of parsing source code.
priv struct ParsedSource {
  spec : @kgf_types.KGFSpec
  tokens : Array[@kgf_types.Tok]
  events : Array[(String, Map[String, Json])]
  prepared : String
  line_offsets : Array[Int]
}

///|
/// Shared parse step: content → spec → tokenize → parse.
/// Returns None if any step fails (no spec, parse error, etc.)
fn parse_source(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> ParsedSource? {
  let reg = match registry {
    Some(r) => r
    None => return None
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => return None
  }
  let spec = match reg.get_spec(lang) {
    Some(s) => s
    None => return None
  }
  let prepared = preprocess_content(content, spec)
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(prepared)
  let peg = @kgf_peg.build_peg(spec) catch { _ => return None }
  let start_rule = spec.get_start_rule()
  let parse_result = match @kgf_peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return None
  }
  let line_offsets = build_line_offsets(prepared)
  Some({ spec, tokens, events: parse_result.get_events(), prepared, line_offsets })
}

///|
/// Extract declarations from source code.
///
/// `visibility`:
/// - `All`: all declarations via parse events + attrs (no semantics evaluation)
/// - `PublicOnly`: public declarations via semantics `when` conditions + doc_map
///
/// doc_map is populated only in PublicOnly mode (semantics needed for $scope doc resolution).
pub fn extract_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
  visibility~ : DeclarationVisibility = PublicOnly,
) -> (Array[PubDeclaration], Map[Int, String]) {
  match visibility {
    All => (extract_all_declarations_from_events(content, path, registry), {})
    PublicOnly =>
      extract_pub_declarations_via_semantics(content, path, registry)
  }
}

///|
/// Extract public declarations via semantics (declares edges) + doc map.
/// Convenience wrapper over `extract_declarations(visibility=PublicOnly)`.
pub fn extract_pub_declarations_and_doc_map(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[PubDeclaration], Map[Int, String]) {
  extract_declarations(content, path, registry, visibility=PublicOnly)
}

///|
/// Internal: public declarations via semantics evaluation.
fn extract_pub_declarations_via_semantics(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[PubDeclaration], Map[Int, String]) {
  let parsed = match parse_source(content, path, registry) {
    Some(result) => result
    None => return ([], {})
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @kgf_semantics.SemEvalCtx::new(
    parsed.spec,
    graph,
    path,
    "",
    parsed.spec.get_language(),
    fn(_) { false },
  )
  for event in parsed.events {
    @kgf_semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  let declarations : Array[PubDeclaration] = []
  let doc_map : Map[Int, String] = {}
  let function_kinds : Array[String] = match
    parsed.spec.get_feature("function_kinds") {
    Some(kinds) => kinds
    None => []
  }
  let declaration_spans = extract_declaration_spans(
    parsed.events,
    parsed.tokens,
    parsed.prepared,
    parsed.line_offsets,
  )
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    let name = edge.attrs.get("name").unwrap_or("")
    let kind = edge.attrs.get("kind").unwrap_or("")
    let doc = edge.attrs.get("doc").unwrap_or("")
    let normalized = to_lower_str(kind)
    let category = if contains_str(function_kinds, kind) {
      "function"
    } else {
      "type"
    }
    let approx_line = estimate_declaration_line(
      parsed.prepared, name, parsed.line_offsets,
    )
    let pref : SpanPreference = if category == "function" {
      Shortest
    } else {
      Longest
    }
    let span = best_declaration_span(
      declaration_spans, parsed.prepared, name, approx_line, preference=pref,
    )
    let line = match span {
      Some(value) => value.line
      None => approx_line
    }
    let start_pos = match span {
      Some(value) => value.start_pos
      None => 0
    }
    let end_pos = match span {
      Some(value) => value.end_pos
      None => 0
    }
    let end_line = match span {
      Some(value) => value.end_line
      None => line
    }
    let start_tok = match span {
      Some(value) => value.start_tok
      None => -1
    }
    let end_tok = match span {
      Some(value) => value.end_tok
      None => -1
    }
    declarations.push({
      kind: normalized,
      name,
      line,
      start_pos,
      end_pos,
      category,
      end_line,
      start_tok,
      end_tok,
    })
    if doc.length() > 0 {
      doc_map.set(line, doc)
    }
  }
  (declarations, doc_map)
}

///|
/// Extract all declarations from parse events, regardless of visibility.
/// Uses KGF attrs metadata + parse events only (no semantics evaluation).
///
/// The attrs section maps grammar rules to `def` actions with id and kind.
/// Parse events provide the token ranges. This captures both public and
/// private declarations — consumers filter by kind (e.g. function_kinds).
pub fn extract_all_declarations_from_events(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[PubDeclaration] {
  let parsed = match parse_source(content, path, registry) {
    Some(result) => result
    None => return []
  }
  // Build mapping from attrs: rule_name → (id_field_name, kind_value)
  // for all rules with a `def` action
  let def_rules : Map[String, (String, String)] = {}
  for entry in parsed.spec.get_attrs() {
    let rule_name = entry.0
    let actions = entry.1
    for action in actions {
      if action.get_kind() == "def" {
        let id_field = action.get_param("id").unwrap_or("")
        let kind_value = action.get_param("kind").unwrap_or("")
        if id_field.length() > 0 {
          def_rules.set(rule_name, (id_field, kind_value))
        }
      }
    }
  }
  if def_rules.is_empty() {
    return []
  }
  // Determine function_kinds for category assignment
  let function_kinds : Map[String, Bool] = {}
  match parsed.spec.get_feature("function_kinds") {
    Some(kinds) =>
      for kind in kinds {
        function_kinds.set(kind, true)
      }
    None => ()
  }
  let result : Array[PubDeclaration] = []
  // Scan parse events for rules with def actions
  for event in parsed.events {
    let rule_name = event.0
    let labels = event.1
    match def_rules.get(rule_name) {
      None => continue
      Some((id_field, kind_value)) => {
        let name = match labels.get(id_field + "_text") {
          Some(String(s)) => s
          _ =>
            match labels.get(id_field) {
              Some(String(s)) => s
              _ => continue
            }
        }
        if name.length() == 0 {
          continue
        }
        let start_tok = match event_token_index(labels, "_start_tok") {
          Some(value) => value
          None => continue
        }
        let end_tok = match event_token_index(labels, "_end_tok") {
          Some(value) => value
          None => continue
        }
        if start_tok < 0 ||
          end_tok <= start_tok ||
          start_tok >= parsed.tokens.length() {
          continue
        }
        // Calculate line numbers from token positions
        let start_pos = parsed.tokens[start_tok].get_pos()
        let last_tok_index = if end_tok - 1 < parsed.tokens.length() {
          end_tok - 1
        } else {
          parsed.tokens.length() - 1
        }
        let end_pos = parsed.tokens[last_tok_index].get_pos() +
          parsed.tokens[last_tok_index].get_text().length()
        let line = line_for_char_offset(parsed.line_offsets, start_pos)
        let end_line = if end_pos > start_pos {
          line_for_char_offset(parsed.line_offsets, end_pos - 1)
        } else {
          line
        }
        let category = if function_kinds.contains(kind_value) {
          "function"
        } else {
          "type"
        }
        result.push({
          kind: to_lower_str(kind_value),
          name,
          line,
          start_pos,
          end_pos,
          category,
          end_line,
          start_tok,
          end_tok,
        })
      }
    }
  }
  result
}

///|
pub fn count_pub_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Int {
  let (decls, _) = extract_pub_declarations_and_doc_map(content, path, registry)
  decls.length()
}

///|
fn build_line_offsets(content : String) -> Array[Int] {
  let offsets : Array[Int] = [0]
  for i, c in content {
    if c == '\n' {
      offsets.push(i + 1)
    }
  }
  offsets
}

///|
fn line_for_char_offset(line_offsets : Array[Int], pos : Int) -> Int {
  for line = line_offsets.length() - 1; line >= 0; line = line - 1 {
    if pos >= line_offsets[line] {
      return line + 1
    }
  }
  1
}

///|
fn parse_int_or_none(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut result = 0
  for ch in text {
    if ch < '0' || ch > '9' {
      return None
    }
    result = result * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(result)
}

///|
fn event_token_index(labels : Map[String, Json], key : String) -> Int? {
  match labels.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    Some(String(value)) => parse_int_or_none(value)
    _ => None
  }
}

///|
fn extract_declaration_spans(
  events : Array[(String, Map[String, Json])],
  tokens : Array[@kgf_types.Tok],
  content : String,
  line_offsets : Array[Int],
) -> Array[DeclarationSpan] {
  let spans : Array[DeclarationSpan] = []
  for event in events {
    let labels = event.1
    let start_tok = match event_token_index(labels, "_start_tok") {
      Some(value) => value
      None => continue
    }
    let end_tok = match event_token_index(labels, "_end_tok") {
      Some(value) => value
      None => continue
    }
    if start_tok < 0 || end_tok <= start_tok || start_tok >= tokens.length() {
      continue
    }
    let last_tok_index = if end_tok - 1 < tokens.length() {
      end_tok - 1
    } else {
      tokens.length() - 1
    }
    if last_tok_index < start_tok {
      continue
    }
    let start_pos = tokens[start_tok].get_pos()
    let last_tok = tokens[last_tok_index]
    let end_pos = last_tok.get_pos() + last_tok.get_text().length()
    if start_pos < 0 || end_pos <= start_pos || end_pos > content.length() {
      continue
    }
    let line = line_for_char_offset(line_offsets, start_pos)
    let end_line = line_for_char_offset(line_offsets, end_pos - 1)
    spans.push({ line, start_pos, end_pos, end_line, start_tok, end_tok })
  }
  spans
}

///|
fn best_declaration_span(
  spans : Array[DeclarationSpan],
  content : String,
  name : String,
  approx_line : Int,
  preference~ : SpanPreference = Longest,
) -> DeclarationSpan? {
  let mut best : DeclarationSpan? = None
  let mut best_distance = 1 << 30
  let mut best_len : Int = match preference {
    Longest => 0 // start small, pick larger
    Shortest => 1 << 30 // start large, pick smaller
  }
  for span in spans {
    let span_text = content[span.start_pos:span.end_pos].to_string()
    if !span_text.contains(name) {
      continue
    }
    let distance = (span.line - approx_line).abs()
    let length = span.end_pos - span.start_pos
    let better_len = match preference {
      Longest => length > best_len
      Shortest => length < best_len
    }
    let better = distance < best_distance ||
      (distance == best_distance && better_len)
    if better {
      best = Some(span)
      best_distance = distance
      best_len = length
    }
  }
  best
}

///|
fn estimate_declaration_line(
  content : String,
  name : String,
  line_offsets : Array[Int],
) -> Int {
  if name.length() == 0 {
    return 1
  }
  let content_chars = content.to_array()
  let name_chars = name.to_array()
  let content_len = content_chars.length()
  let name_len = name_chars.length()
  for i = 0; i < content_len - name_len + 1; i = i + 1 {
    let mut matched = true
    for j = 0; j < name_len; j = j + 1 {
      if content_chars[i + j] != name_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      for line = line_offsets.length() - 1; line >= 0; line = line - 1 {
        if i >= line_offsets[line] {
          return line + 1
        }
      }
    }
  }
  1
}

///|
fn contains_str(arr : Array[String], value : String) -> Bool {
  for item in arr {
    if item == value {
      return true
    }
  }
  false
}
