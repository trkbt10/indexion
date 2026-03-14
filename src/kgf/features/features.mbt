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
pub fn load_registry(
  explicit_path? : String = "",
  target_dir? : String = ".",
  target_dirs? : Array[String] = [],
) -> @kgf_registry.KGFRegistry? {
  match find_kgfs_dir(explicit_path~, target_dir~, target_dirs~) {
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
