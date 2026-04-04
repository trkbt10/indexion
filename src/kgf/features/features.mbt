///|
/// KGF-based feature extraction for TF-IDF similarity.
/// Converts KGF lexer tokens to TF-IDF feature strings.

///|
/// Find kgfs directory.
/// Delegates to @config.find_kgfs_dir which is the SoT for path resolution.
pub fn find_kgfs_dir(
  explicit_path? : String = "",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> String? {
  @config.find_kgfs_dir(explicit_path~, target_dir~, target_dirs~)
}

///|
/// Convert string to lowercase.
pub fn to_lower_str(s : String) -> String {
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
/// Build identifier kind set from KGF spec's `identifier_kinds` feature.
pub fn build_identifier_set(spec~ : @kgf_types.KGFSpec) -> Map[String, Bool] {
  let set : Map[String, Bool] = {}
  match spec.get_feature("identifier_kinds") {
    Some(kinds) =>
      for kind in kinds {
        set[kind] = true
      }
    None => ()
  }
  if set.is_empty() {
    // Spec has no identifier_kinds feature — nothing to identify
    set["Ident"] = true
  }
  set
}

///|
/// Check if token kind represents an identifier, using a prebuilt identifier set.
/// The set should be obtained from `build_identifier_set`.
pub fn is_identifier_kind(kind : String, id_set~ : Map[String, Bool]) -> Bool {
  id_set.contains(kind)
}

///|
/// Build vocabulary token kind set from KGF spec's `vocabulary_token_kinds` feature.
/// Tokens of these kinds have their text content sub-tokenized into words
/// for vocabulary-level comparison (e.g., doc comments, string literals).
pub fn build_vocabulary_token_set(
  spec~ : @kgf_types.KGFSpec,
) -> Map[String, Bool] {
  let set : Map[String, Bool] = {}
  match spec.get_feature("vocabulary_token_kinds") {
    Some(kinds) =>
      for kind in kinds {
        set[kind] = true
      }
    None => ()
  }
  set
}

///|
/// Convert KGF token to TF-IDF feature string.
/// Strategy:
/// - Identifiers: "kind:text" for name similarity
/// - Keywords/operators: "kind" only for structural similarity
/// - Literals: "kind" only (ignore actual values)
pub fn kgf_tok_to_tfidf_token(
  tok : @kgf_types.Tok,
  id_set~ : Map[String, Bool],
) -> String {
  let kind = tok.get_kind()
  if is_identifier_kind(kind, id_set~) {
    kind + ":" + tok.get_text()
  } else {
    kind
  }
}

///|
/// Tokenize source code using KGF lexer and convert to TF-IDF tokens.
pub fn tokenize_with_kgf(
  content : String,
  spec : @kgf_types.KGFSpec,
) -> Array[String] {
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(content)
  let id_set = build_identifier_set(spec~)
  let result : Array[String] = []
  for tok in tokens {
    result.push(kgf_tok_to_tfidf_token(tok, id_set~))
  }
  result
}

///|
/// Tokenize files using KGF lexer.
/// Files without KGF spec support are skipped (empty tokens).
/// Returns (tokenized documents, kgf_hit_count).
pub fn tokenize_files_with_kgf(
  files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[Array[String]], Int) {
  let tokenized : Array[Array[String]] = []
  let mut kgf_hits = 0
  for file in files {
    let (path, content) = file
    let tokens = match registry {
      Some(reg) =>
        match reg.detect_from_path(path) {
          Some(lang) =>
            match reg.get_spec(lang) {
              Some(spec) => {
                kgf_hits += 1
                tokenize_with_kgf(content, spec)
              }
              None => []
            }
          None => []
        }
      None => []
    }
    tokenized.push(tokens)
  }
  (tokenized, kgf_hits)
}

///|
/// Build a map from line number (1-indexed) to function name using KGF function extraction.
/// Used to annotate duplicate code blocks with function context.
pub fn build_line_func_map(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Map[Int, String] {
  let result : Map[Int, String] = {}
  let reg = match registry {
    Some(r) => r
    None => return result
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => return result
  }
  let spec = match reg.get_spec(lang) {
    Some(s) => s
    None => return result
  }
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(content)
  let functions = extract_functions(tokens, path, spec~)
  // Build token_index -> line_number mapping by counting NL tokens
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  // Map function start lines to function names
  for func in functions {
    if func.get_start() < token_lines.length() {
      result.set(token_lines[func.get_start()], func.get_name())
    }
  }
  result
}

///|
/// Load KGF registry from kgfs directory if available.
/// `specs_dir` is the CLI --specs-dir value. The default "kgfs" triggers
/// auto-detection; any other value is treated as an explicit path.
pub fn load_registry(
  specs_dir? : String = "kgfs",
  explicit_path? : String = "",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> @kgf_registry.KGFRegistry? {
  let resolved_explicit = if explicit_path.length() > 0 {
    explicit_path
  } else if specs_dir != "kgfs" {
    specs_dir
  } else {
    ""
  }
  match
    find_kgfs_dir(explicit_path=resolved_explicit, target_dir~, target_dirs~) {
    Some(dir) => {
      let reg = @kgf_registry.KGFRegistry::load_from_dir(dir)
      if reg.spec_count() > 0 {
        Some(reg)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Load KGF registry, returning an empty registry if none found.
/// Convenience wrapper over `load_registry` for commands that always need a registry.
pub fn load_registry_or_empty(
  specs_dir? : String = "kgfs",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> @kgf_registry.KGFRegistry {
  match load_registry(specs_dir~, target_dir~, target_dirs~) {
    Some(r) => r
    None => @kgf_registry.KGFRegistry::new()
  }
}

///|
/// A public declaration extracted from source code via KGF tokenization.
pub struct PubDeclaration {
  /// Declaration kind derived from token kind (e.g. "fn", "struct", "class").
  kind : String
  /// Declaration name (the identifier following the declaration keyword).
  name : String
  /// Line number (1-indexed).
  line : Int
  /// Category: "function" for callable declarations, "type" for data/contract declarations.
  /// Determined by the KGF spec's function_kinds feature.
  category : String
}

///|
/// Tokenize source content using KGF registry.
/// Returns None if registry, language detection, or spec lookup fails.
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
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  Some(lexer.tokenize(content))
}

///|
/// Count public declarations in source code using full KGF pipeline.
pub fn count_pub_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Int {
  let (decls, _) = extract_pub_declarations_and_doc_map(content, path, registry)
  decls.length()
}

///|
/// Check if a token kind is a doc comment.
/// Matches any token whose kind starts with "Doc" — covers DocComment, DocLine,
/// DocSection, DocBlockComment, DocInnerComment, DocString, DocAttr, etc.
fn is_doc_token_kind(kind : String) -> Bool {
  kind.has_prefix("Doc")
}

///|
/// Extract doc comments from tokens and map them to the line they precede.
/// Returns Map[line_number, doc_text] where line_number is the first
/// non-doc, non-whitespace line after the doc block.
/// Uses KGF token kinds (DocComment, DocLine, DocSection) — language-agnostic.
pub fn extract_doc_map(tokens : Array[@kgf_types.Tok]) -> Map[Int, String] {
  let result : Map[Int, String] = {}
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  // Scan tokens: collect consecutive doc tokens, then associate with next non-skip line
  let mut i = 0
  while i < tokens.length() {
    let kind = tokens[i].get_kind()
    if is_doc_token_kind(kind) {
      // Start of a doc block — collect all consecutive doc tokens
      let doc_buf = StringBuilder::new()
      let mut first = true
      while i < tokens.length() {
        let k = tokens[i].get_kind()
        if is_doc_token_kind(k) {
          let value = tokens[i].get_value()
          // skip_value tokens (e.g. ///|) produce empty string — skip them
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
      // Associate doc block with current token's line
      let doc = doc_buf.to_string()
      if doc.length() > 0 && i < tokens.length() {
        let target_line = if i < token_lines.length() {
          token_lines[i]
        } else {
          line
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
/// Extract doc comments from source file using KGF tokenization.
/// Returns Map[line_number, doc_text] keyed by declaration line.
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
/// Extract public declarations and doc map using the full KGF pipeline
/// (tokenize → parse → eval_semantics → declares edges).
///
/// Public declarations are identified by `visibility: "public"` attribute
/// on `declares` edges, as defined in each language's KGF semantics.
/// Doc comments are extracted from the `doc` attribute on declares edges.
pub fn extract_pub_declarations_and_doc_map(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[PubDeclaration], Map[Int, String]) {
  let reg = match registry {
    Some(r) => r
    None => return ([], {})
  }
  let lang = match reg.detect_from_path(path) {
    Some(l) => l
    None => return ([], {})
  }
  let spec = match reg.get_spec(lang) {
    Some(s) => s
    None => return ([], {})
  }
  // Tokenize
  let lexer = @kgf_lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(content)
  // Parse
  let peg = @kgf_peg.build_peg(spec) catch { _ => return ([], {}) }
  let start_rule = spec.get_start_rule()
  let parse_result = match @kgf_peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return ([], {})
  }
  // Evaluate semantics
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @kgf_semantics.SemEvalCtx::new(
    spec,
    graph,
    path,
    "",
    spec.get_language(),
    fn(_) { false },
  )
  let events = parse_result.get_events()
  for event in events {
    @kgf_semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  // Extract public declarations and doc map from declares edges
  let declarations : Array[PubDeclaration] = []
  let doc_map : Map[Int, String] = {}
  // Build function_kinds set from KGF spec features
  let function_kinds : Array[String] = match
    spec.get_feature("function_kinds") {
    Some(kinds) => kinds
    None => []
  }
  // Build line number index from tokens for position lookup
  let line_offsets = build_line_offsets(content)
  let edges = graph.get_edges()
  for edge in edges {
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
    // Estimate line number from edge target symbol
    let line = estimate_declaration_line(content, name, line_offsets)
    declarations.push({ kind: normalized, name, line, category })
    if doc.length() > 0 {
      doc_map.set(line, doc)
    }
  }
  (declarations, doc_map)
}

///|
/// Build line start offsets for a source string.
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
/// Estimate the line number of a declaration by searching for its name in the source.
fn estimate_declaration_line(
  content : String,
  name : String,
  line_offsets : Array[Int],
) -> Int {
  if name.length() == 0 {
    return 1
  }
  // Search for the name in the content
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
      // Found the name, calculate line number
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

///|
/// Node type label for code-oriented files (content_type absent or non-document).
pub let node_type_code : String = "code"

///|
/// Node type label for document-oriented files (content_type: document).
pub let node_type_document : String = "document"

///|
/// Collect document path patterns from document-oriented KGF specs (content_type: document).
/// Derives patterns from spec resolver's `sources` (extensions) and
/// `indexes` (e.g. /README.md, /index.html) — no hardcoded paths.
/// Returns (index_patterns, wildcard_patterns) for package-level scope.
pub fn get_document_patterns(
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[String], Array[String]) {
  let reg = match registry {
    Some(r) => r
    None => return ([], [])
  }
  let index_patterns : Array[String] = []
  let wild_patterns : Array[String] = []
  let seen : Map[String, Bool] = {}
  for spec_entry in reg.specs {
    let spec = spec_entry.1
    if !is_document_spec(spec) {
      continue
    }
    let resolver = spec.get_resolver()
    // Index files (e.g. /README.md → README.md)
    for idx in resolver.get_indexes() {
      let clean = if idx.has_prefix("/") {
        let chars = idx.to_array()
        let buf = StringBuilder::new()
        for i = 1; i < chars.length(); i = i + 1 {
          buf.write_char(chars[i])
        }
        buf.to_string()
      } else {
        idx
      }
      if clean.length() > 0 && !seen.contains(clean) {
        index_patterns.push(clean)
        seen[clean] = true
      }
    }
    // Wildcard patterns from extensions
    for src in resolver.get_sources() {
      let ext = if src.has_prefix(".") { src } else { "." + src }
      let pattern = "*" + ext
      if !seen.contains(pattern) {
        wild_patterns.push(pattern)
        seen[pattern] = true
      }
    }
  }
  (index_patterns, wild_patterns)
}

///|
/// Check if a KGF spec is document-oriented via the `content_type` feature.
/// Returns true if content_type is "document".
/// This replaces the old HEADING token check — content type is now
/// explicitly declared by each KGF spec, not inferred from token names.
pub fn is_document_spec(spec : @kgf_types.KGFSpec) -> Bool {
  match spec.get_feature("content_type") {
    Some(values) => values.length() > 0 && values[0] == "document"
    None => false
  }
}

///|
/// Detect whether a file's KGF spec declares `content_type: document`.
/// Returns Some(true) for document-oriented files, Some(false) for code,
/// None if no spec matches the file.
pub fn is_document_file(
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Bool? {
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
  Some(is_document_spec(spec))
}

///|
/// A section heading extracted from tokens via KGF features.
pub(all) struct Heading {
  /// Heading level (derived from section_level strategy in KGF spec).
  level : Int
  /// Heading text (collected from heading_text_tokens defined in KGF spec).
  text : String
  /// URL-safe anchor
  anchor : String
  /// Line number in source
  line : Int
}

///|
/// Extract section headings from KGF tokens.
/// Uses `section_token`, `section_level`, and `heading_text_tokens` features
/// from the KGF spec. No hardcoded token names or level calculation logic.
///
/// When spec is provided, section structure is fully KGF-driven.
/// When spec is None, returns empty (no spec = no section knowledge).
pub fn extract_headings(
  tokens : Array[@kgf_types.Tok],
  spec? : @kgf_types.KGFSpec? = None,
) -> Array[Heading] {
  let headings : Array[Heading] = []
  // Resolve section configuration from KGF spec features
  let the_spec = match spec {
    Some(s) => s
    None => return headings
  }
  let section_token = match the_spec.get_feature("section_token") {
    Some(values) =>
      if values.length() > 0 {
        values[0]
      } else {
        return headings
      }
    None => return headings
  }
  let section_level_strategy = match the_spec.get_feature("section_level") {
    Some(values) => if values.length() > 0 { values[0] } else { "text_length" }
    None => "text_length"
  }
  let text_token_set : Map[String, Bool] = {}
  match the_spec.get_feature("heading_text_tokens") {
    Some(kinds) =>
      for kind in kinds {
        text_token_set[kind] = true
      }
    None => ()
  }
  // If heading_text_tokens includes the section_token itself,
  // the section token's text IS the heading text (e.g. TOML [section.name]).
  let section_is_text = text_token_set.contains(section_token)
  let mut line = 1
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    let kind = tok.get_kind()
    if kind == "NL" {
      line += 1
      i += 1
      continue
    }
    if kind == section_token {
      let level = compute_section_level(tok.get_text(), section_level_strategy)
      let heading_line = line
      let buf = StringBuilder::new()
      if section_is_text {
        // The section token itself carries the heading text
        buf.write_string(tok.get_text())
      }
      i += 1
      if !section_is_text {
        // Skip whitespace after section token
        while i < tokens.length() {
          let k = tokens[i].get_kind()
          if k == "SKIP" || k == "WS" {
            i += 1
          } else {
            break
          }
        }
        // Collect heading text tokens until NL
        let mut first = true
        while i < tokens.length() {
          let k = tokens[i].get_kind()
          if k == "NL" {
            break
          }
          if text_token_set.contains(k) {
            if !first {
              buf.write_string(" ")
            }
            buf.write_string(tokens[i].get_text())
            first = false
          }
          i += 1
        }
      }
      let text = buf.to_string()
      if text.length() > 0 {
        headings.push({
          level,
          text,
          anchor: make_anchor(text),
          line: heading_line,
        })
      }
    } else {
      i += 1
    }
  }
  headings
}

///|
/// Compute section level from token text using the strategy defined in KGF spec.
/// - "text_length": token text length is the level (e.g. "##" → 2)
/// - "flat": all sections are level 1
fn compute_section_level(text : String, strategy : String) -> Int {
  if strategy == "flat" {
    return 1
  }
  // Default: text_length — count characters in the section token text
  let mut count = 0
  for _c in text {
    count += 1
  }
  count
}

///|
/// Convert heading text to URL-safe anchor.
fn make_anchor(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    if c == ' ' || c == '\t' {
      buf.write_char('-')
    } else if (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' {
      buf.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      buf.write_char(Int::unsafe_to_char(c.to_int() + 32))
    }
  }
  buf.to_string()
}

///|
/// Split content into sections at section token boundaries of the given level.
/// Returns (id, title, content, level) tuples suitable for search indexing.
/// Section boundaries are determined by the KGF spec's `section_token` feature.
pub fn extract_sections_from_tokens(
  tokens : Array[@kgf_types.Tok],
  content : String,
  page_id : String,
  page_title : String,
  split_level? : Int = 2,
  spec? : @kgf_types.KGFSpec? = None,
) -> Array[(String, String, String, Int)] {
  let headings = extract_headings(tokens, spec~)
  let lines = split_by_newline(content)
  let results : Array[(String, String, String, Int)] = []
  // Full page as a section
  results.push((page_id, page_title, content, 1))
  // Collect h{split_level} headings as section boundaries
  let section_headings : Array[Heading] = []
  for h in headings {
    if h.level == split_level {
      section_headings.push(h)
    }
  }
  if section_headings.is_empty() {
    return results
  }
  // Extract content between headings
  for idx, heading in section_headings {
    let start_line = heading.line
    let end_line = if idx + 1 < section_headings.length() {
      section_headings[idx + 1].line - 1
    } else {
      lines.length()
    }
    let buf = StringBuilder::new()
    for j = start_line; j < end_line && j < lines.length(); j = j + 1 {
      buf.write_string(lines[j])
      buf.write_string("\n")
    }
    let section_content = buf.to_string()
    if section_content.length() > 0 {
      let id = page_id + "#" + heading.anchor
      results.push((id, heading.text, section_content, split_level))
    }
  }
  results
}
