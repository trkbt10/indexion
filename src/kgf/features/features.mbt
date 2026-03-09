///|
/// KGF-based feature extraction for TF-IDF similarity.
/// Converts KGF lexer tokens to TF-IDF feature strings.

///|
/// Find kgfs directory by searching relative paths.
pub fn find_kgfs_dir() -> String? {
  let paths = [
    "kgfs", "../kgfs", "../../kgfs", "../../../kgfs", "../../../../kgfs",
  ]
  for path in paths {
    try {
      if @fs.is_dir(path) {
        return Some(path)
      }
    } catch {
      _ => continue
    }
  }
  None
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
      Some(reg) => {
        match reg.detect_from_path(path) {
          Some(lang) => {
            match reg.get_spec(lang) {
              Some(spec) => {
                kgf_hits += 1
                tokenize_with_kgf(content, spec)
              }
              None => []
            }
          }
          None => []
        }
      }
      None => []
    }
    tokenized.push(tokens)
  }
  (tokenized, kgf_hits)
}

///|
/// Load KGF registry from kgfs directory if available.
pub fn load_registry() -> @kgf_registry.KGFRegistry? {
  match find_kgfs_dir() {
    Some(dir) => {
      let reg = @kgf_registry.KGFRegistry::load_from_dir(dir)
      if reg.spec_count() > 0 { Some(reg) } else { None }
    }
    None => None
  }
}
