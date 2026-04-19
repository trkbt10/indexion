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
///
/// Thin wrapper over MoonBit's `String::to_lower()` kept for API
/// compatibility with downstream callers. Folded here instead of
/// re-implementing the ASCII table so the behavior matches `@tokenize`,
/// which already relies on the builtin.
pub fn to_lower_str(s : String) -> String {
  s.to_lower()
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
/// Build normalized search terms for a token.
/// Includes the raw normalized token text and, for token kinds listed in the
/// spec's `vocabulary_token_kinds`, sub-tokenized vocabulary words.
pub fn token_search_terms(
  tok : @kgf_types.Tok,
  spec~ : @kgf_types.KGFSpec,
) -> Array[String] {
  let result : Array[String] = []
  let raw = tok.get_text().to_lower()
  if raw.length() > 0 {
    result.push(raw)
  }
  let vocab_kinds = build_vocabulary_token_set(spec~)
  if !vocab_kinds.contains(tok.get_kind()) {
    return result
  }
  for term in subtokenize_vocab_words(tok.get_text()) {
    if term.length() > 0 && !result.contains(term) {
      result.push(term)
    }
  }
  result
}

///|
fn subtokenize_vocab_words(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for ch in text {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' {
      buf.write_char(ch)
    } else {
      let word = buf.to_string().to_lower()
      if word.length() >= 3 && !result.contains(word) {
        result.push(word)
      }
      buf.reset()
    }
  }
  let last = buf.to_string().to_lower()
  if last.length() >= 3 && !result.contains(last) {
    result.push(last)
  }
  result
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
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  tokenize_with_toolkit(content, toolkit)
}

///|
/// Tokenize source code using a cached LanguageToolkit.
/// Prefer this over `tokenize_with_kgf` when processing multiple files of the
/// same language — the toolkit reuses compiled lexer and feature sets.
pub fn tokenize_with_toolkit(
  content : String,
  toolkit : @kgf_toolkit.LanguageToolkit,
) -> Array[String] {
  let tokens = toolkit.tokenize(content)
  let id_set = toolkit.get_identifier_set()
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
///
/// Uses ToolkitRegistry internally so that files sharing the same language
/// reuse the compiled Lexer and feature sets (no redundant construction).
pub fn tokenize_files_with_kgf(
  files : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry?,
) -> (Array[Array[String]], Int) {
  let tokenized : Array[Array[String]] = []
  let mut kgf_hits = 0
  match registry {
    Some(reg) => {
      let toolkit_reg = @kgf_toolkit.ToolkitRegistry::new(reg)
      for file in files {
        let (path, content) = file
        let tokens = match toolkit_reg.for_path(path) {
          Some(toolkit) => {
            kgf_hits += 1
            tokenize_with_toolkit(content, toolkit)
          }
          None => []
        }
        tokenized.push(tokens)
      }
    }
    None =>
      for _file in files {
        tokenized.push([])
      }
  }
  (tokenized, kgf_hits)
}

///|
/// Build a map from line number (1-indexed) to function name.
/// Uses KGF grammar pipeline (tokenize→parse→eval_semantics→declares edges)
/// for accurate function boundary detection across all languages.
pub fn build_line_func_map(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Map[Int, String] {
  let result : Map[Int, String] = {}
  let (decls, _) = @kgf_declarations.extract_pub_declarations_and_doc_map(
    content, path, registry,
  )
  for decl in decls {
    if decl.category == "function" {
      result.set(decl.line, decl.name)
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
  let toolkit_reg = @kgf_toolkit.ToolkitRegistry::new(reg)
  toolkit_reg.tokenize(content, path)
}

///|
/// Apply preprocessing steps from the spec to content.
/// Delegates to LanguageToolkit::preprocess for the actual work.
pub fn preprocess_content(
  content : String,
  spec : @kgf_types.KGFSpec,
) -> String {
  @kgf_toolkit.LanguageToolkit::from_spec(spec).preprocess(content)
}

///|
/// Node type label for code-oriented files (content_type absent or non-document).
pub let node_type_code : String = "code"

///|
/// Node type label for document-oriented files (content_type: document).
pub let node_type_document : String = "document"

///|
/// Return the declared content type for a KGF spec.
pub fn content_type_for_spec(spec : @kgf_types.KGFSpec) -> String? {
  match spec.get_feature("content_type") {
    Some(values) => if values.length() > 0 { Some(values[0]) } else { None }
    None => None
  }
}

///|
/// Resolve the declared content type for a file path via its KGF spec.
/// Returns None if the file has no matching spec or the spec declares no content type.
pub fn content_type_for_file(
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> String? {
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
  content_type_for_spec(spec)
}

///|
/// Check if a KGF spec is document-oriented via the `content_type` feature.
pub fn is_document_spec(spec : @kgf_types.KGFSpec) -> Bool {
  content_type_for_spec(spec) == Some("document")
}

///|
/// Detect whether a file's KGF spec declares `content_type: document`.
/// Returns Some(true) for document-oriented files, Some(false) for files with
/// a matching non-document spec, and None if no spec matches the file.
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
