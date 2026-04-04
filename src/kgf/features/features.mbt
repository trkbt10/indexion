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
/// Check if token kind represents an identifier.
/// Handles variations: Ident, IDENT, identifier, etc.
pub fn is_identifier_kind(kind : String) -> Bool {
  let lower = to_lower_str(kind)
  lower == "ident" || lower == "identifier" || lower == "id"
}

///|
/// Convert KGF token to TF-IDF feature string.
/// Strategy:
/// - Identifiers: "kind:text" for name similarity
/// - Keywords/operators: "kind" only for structural similarity
/// - Literals: "kind" only (ignore actual values)
pub fn kgf_tok_to_tfidf_token(tok : @kgf_types.Tok) -> String {
  let kind = tok.get_kind()
  if is_identifier_kind(kind) {
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
  let result : Array[String] = []
  for tok in tokens {
    result.push(kgf_tok_to_tfidf_token(tok))
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
  let functions = extract_functions(tokens, path)
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
/// Check if a token kind represents a visibility modifier.
/// Detects KW_pub, KW_public, KW_export by prefix convention.
fn is_visibility_keyword(kind : String) -> Bool {
  kind == "KW_pub" || kind == "KW_public" || kind == "KW_export"
}

///|
/// Check if a token kind represents a declaration keyword.
/// Returns the normalized kind name (e.g. "KW_fn" -> "fn", "KW_function" -> "function").
fn declaration_kind(kind : String) -> String? {
  // Function declarations
  if kind == "KW_fn" ||
    kind == "KW_function" ||
    kind == "KW_def" ||
    kind == "KW_func" ||
    kind == "KW_fun" {
    return Some(kind[3:].to_string())
  }
  // Type declarations
  if kind == "KW_struct" ||
    kind == "KW_class" ||
    kind == "KW_enum" ||
    kind == "KW_type" ||
    kind == "KW_trait" ||
    kind == "KW_interface" ||
    kind == "KW_protocol" ||
    kind == "KW_actor" ||
    kind == "KW_object" ||
    kind == "KW_record" ||
    kind == "KW_module" {
    return Some(kind[3:].to_string())
  }
  // Variable/constant declarations
  if kind == "KW_let" || kind == "KW_const" || kind == "KW_var" {
    return Some(kind[3:].to_string())
  }
  None
}

///|
/// Extract public declarations from pre-tokenized tokens.
/// Language-agnostic: uses KGF token kinds to detect visibility + declaration patterns.
pub fn extract_pub_declarations_from_tokens(
  tokens : Array[@kgf_types.Tok],
) -> Array[PubDeclaration] {
  let result : Array[PubDeclaration] = []
  // Build token -> line number mapping
  let mut line = 1
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  // Scan for visibility keyword followed by declaration keyword + identifier
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    if is_visibility_keyword(tok.get_kind()) {
      // Look ahead for a declaration keyword
      let mut j = i + 1
      // Skip whitespace, newlines, and visibility modifier args like (all), (readonly)
      while j < tokens.length() {
        let next_kind = tokens[j].get_kind()
        if next_kind == "NL" ||
          next_kind == "WS" ||
          next_kind == "LPAREN" ||
          next_kind == "RPAREN" ||
          (
            is_identifier_kind(next_kind) &&
            is_visibility_modifier_arg(tokens[j].get_text())
          ) {
          j += 1
        } else {
          break
        }
      }
      if j < tokens.length() {
        match declaration_kind(tokens[j].get_kind()) {
          Some(kind) => {
            // Find the identifier (name) after the declaration keyword
            let mut k = j + 1
            while k < tokens.length() {
              let kind_k = tokens[k].get_kind()
              if is_identifier_kind(kind_k) || kind_k == "TypeIdent" {
                result.push({
                  kind,
                  name: tokens[k].get_text(),
                  line: token_lines[i],
                  category: "function",
                })
                break
              } else if kind_k == "NL" || kind_k == "LBRACE" {
                break // No identifier found before block/newline
              }
              k += 1
            }
            i = k + 1
            continue
          }
          None => ()
        }
      }
    }
    i += 1
  }
  result
}

///|
/// Check if an identifier is a visibility modifier argument (e.g. "all", "readonly", "open").
fn is_visibility_modifier_arg(text : String) -> Bool {
  text == "all" || text == "readonly" || text == "open" || text == "priv"
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
/// Extract public declarations from source code using KGF tokenization.
/// Language-agnostic: uses KGF token kinds to detect visibility + declaration patterns.
/// Returns empty array if registry or spec is unavailable.
pub fn extract_pub_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[PubDeclaration] {
  match tokenize_source(content, path, registry) {
    Some(tokens) => extract_pub_declarations_from_tokens(tokens)
    None => []
  }
}

///|
/// Count public declarations in source code using KGF tokenization.
/// Convenience wrapper around extract_pub_declarations.
pub fn count_pub_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Int {
  extract_pub_declarations(content, path, registry).length()
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
    spec, graph, path, "", spec.get_language(), fn(_) { false },
  )
  let events = parse_result.get_events()
  for event in events {
    @kgf_semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  // Extract public declarations and doc map from declares edges
  let declarations : Array[PubDeclaration] = []
  let doc_map : Map[Int, String] = {}
  // Build function_kinds set from KGF spec features
  let function_kinds : Array[String] = match spec.get_feature("function_kinds") {
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
    let normalized = normalize_kind(kind)
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
/// Normalize edge kind to short form (e.g. "Function" -> "fn", "Class" -> "class").
fn normalize_kind(kind : String) -> String {
  match kind {
    "Function" => "fn"
    "Class" => "class"
    "Struct" => "struct"
    "Enum" => "enum"
    "Interface" => "interface"
    "Trait" => "trait"
    "Type" => "type"
    "Protocol" => "protocol"
    "Actor" => "actor"
    "Record" => "record"
    "Module" => "module"
    "Variable" => "var"
    "Const" => "const"
    "Property" => "property"
    "Method" => "method"
    "Macro" => "macro"
    _ => kind
  }
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
/// Node type label for code-oriented files (no HEADING token in KGF spec).
pub let node_type_code : String = "code"

///|
/// Node type label for document-oriented files (HEADING token present in KGF spec).
pub let node_type_document : String = "document"

///|
/// Collect file extensions for document-oriented KGF specs (those with HEADING tokens).
/// Returns extensions like [".md", ".markdown", ".mdx"] from all matching specs.
pub fn get_document_extensions(
  registry : @kgf_registry.KGFRegistry?,
) -> Array[String] {
  let reg = match registry {
    Some(r) => r
    None => return []
  }
  let exts : Array[String] = []
  let seen : Map[String, Bool] = {}
  for spec_entry in reg.specs {
    let spec = spec_entry.1
    if spec_has_heading_token(spec) {
      let sources = spec.get_resolver().get_sources()
      for src in sources {
        let ext = if src.has_prefix(".") { src } else { "." + src }
        if !seen.contains(ext) {
          exts.push(ext)
          seen[ext] = true
        }
      }
    }
  }
  exts
}

///|
/// Collect document path patterns from document-oriented KGF specs.
/// Derives patterns from spec resolver's `sources` (extensions) and
/// `indexes` (e.g. /README.md, /index.md) — no hardcoded paths.
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
    if !spec_has_heading_token(spec) {
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
/// Check if a KGF spec defines a HEADING token kind.
/// Specs with HEADING tokens (e.g. markdown.kgf) are document-oriented
/// and should be indexed by section splitting rather than function extraction.
pub fn spec_has_heading_token(spec : @kgf_types.KGFSpec) -> Bool {
  for tok_def in spec.get_tokens() {
    if tok_def.get_name() == "HEADING" {
      return true
    }
  }
  false
}

///|
/// Detect whether a file's KGF spec has HEADING tokens.
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
  Some(spec_has_heading_token(spec))
}

///|
/// A heading extracted from tokens (language-agnostic via KGF HEADING token).
pub(all) struct Heading {
  /// Heading level (1 for "#", 2 for "##", etc.)
  level : Int
  /// Heading text (concatenated TEXT tokens following the HEADING token)
  text : String
  /// URL-safe anchor
  anchor : String
  /// Line number in source
  line : Int
}

///|
/// Extract headings from KGF tokens.
/// Works with any KGF spec that defines a HEADING token kind.
pub fn extract_headings(
  tokens : Array[@kgf_types.Tok],
) -> Array[Heading] {
  let headings : Array[Heading] = []
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
    if kind == "HEADING" {
      let level = count_heading_level(tok.get_text())
      let heading_line = line
      i += 1
      // Skip whitespace
      while i < tokens.length() {
        let k = tokens[i].get_kind()
        if k == "SKIP" || k == "WS" {
          i += 1
        } else {
          break
        }
      }
      // Collect TEXT tokens until NL
      let buf = StringBuilder::new()
      let mut first = true
      while i < tokens.length() {
        let k = tokens[i].get_kind()
        if k == "NL" {
          break
        }
        if k == "TEXT" || k == "INLINE_CODE" {
          if !first {
            buf.write_string(" ")
          }
          buf.write_string(tokens[i].get_text())
          first = false
        }
        i += 1
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
/// Count '#' characters to determine heading level.
fn count_heading_level(text : String) -> Int {
  let mut level = 0
  for c in text {
    if c == '#' {
      level += 1
    } else {
      break
    }
  }
  level
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
/// Split content into sections at HEADING boundaries of the given level.
/// Returns (id, title, content, level) tuples suitable for search indexing.
/// Uses KGF tokenization — no markdown-specific hardcoding.
pub fn extract_sections_from_tokens(
  tokens : Array[@kgf_types.Tok],
  content : String,
  page_id : String,
  page_title : String,
  split_level~ : Int = 2,
) -> Array[(String, String, String, Int)] {
  let headings = extract_headings(tokens)
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

