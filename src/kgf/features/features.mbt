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

///|
/// A public declaration extracted from source code via KGF tokenization.
pub struct PubDeclaration {
  /// Declaration kind derived from token kind (e.g. "fn", "struct", "class").
  kind : String
  /// Declaration name (the identifier following the declaration keyword).
  name : String
  /// Line number (1-indexed).
  line : Int
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
    kind == "KW_func" {
    return Some(kind.substring(start=3))
  }
  // Type declarations
  if kind == "KW_struct" ||
    kind == "KW_class" ||
    kind == "KW_enum" ||
    kind == "KW_type" ||
    kind == "KW_trait" ||
    kind == "KW_interface" {
    return Some(kind.substring(start=3))
  }
  // Variable/constant declarations
  if kind == "KW_let" || kind == "KW_const" || kind == "KW_var" {
    return Some(kind.substring(start=3))
  }
  None
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
  let result : Array[PubDeclaration] = []
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
      // Skip whitespace/newlines between visibility and declaration
      while j < tokens.length() {
        let next_kind = tokens[j].get_kind()
        if next_kind == "NL" ||
          next_kind == "WS" ||
          next_kind == "LPAREN" ||
          next_kind == "RPAREN" {
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
/// Count public declarations in source code using KGF tokenization.
/// Convenience wrapper around extract_pub_declarations.
pub fn count_pub_declarations(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Int {
  extract_pub_declarations(content, path, registry).length()
}
