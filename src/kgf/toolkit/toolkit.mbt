///|
/// LanguageToolkit caches all runtime artifacts derived from a KGFSpec.
///
/// Creating a Lexer, building feature sets (identifier kinds, vocabulary kinds,
/// qualifier separators, etc.) from spec features — these are pure derivations
/// that never change for a given spec. Rather than letting each consumer rebuild
/// them on every file, LanguageToolkit constructs them once and exposes the
/// cached results.
///
/// Obtain a toolkit via `ToolkitRegistry::get(lang)` or the convenience
/// `ToolkitRegistry::for_path(path)`.
pub struct LanguageToolkit {
  spec : @types.KGFSpec
  lexer : @lexer.Lexer
  identifier_set : Map[String, Bool]
  vocabulary_set : Map[String, Bool]
  allowed_keywords : Map[String, Bool]
  qualifier_separators : Map[String, Bool]
  self_keywords : Map[String, Bool]
}

///|
/// Build a LanguageToolkit from a KGFSpec.
/// All derived artifacts are computed eagerly at construction time, so
/// subsequent access is zero-cost.
pub fn LanguageToolkit::from_spec(spec : @types.KGFSpec) -> LanguageToolkit {
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let identifier_set = build_set_from_feature(spec, "identifier_kinds")
  let identifier_set = if identifier_set.is_empty() {
    // Default fallback when spec has no identifier_kinds feature
    let set : Map[String, Bool] = {}
    set["Ident"] = true
    set
  } else {
    identifier_set
  }
  let vocabulary_set = build_set_from_feature(spec, "vocabulary_token_kinds")
  let allowed_keywords = {
    let set = build_set_from_feature(spec, "function_keyword")
    let self_kws = build_set_from_feature(spec, "self_keyword")
    for entry in self_kws {
      set[entry.0] = true
    }
    set
  }
  let qualifier_separators = build_set_from_feature(
    spec, "qualifier_separators",
  )
  let self_keywords = build_set_from_feature(spec, "self_keyword")
  {
    spec,
    lexer,
    identifier_set,
    vocabulary_set,
    allowed_keywords,
    qualifier_separators,
    self_keywords,
  }
}

///|
/// Access the underlying KGFSpec.
pub fn LanguageToolkit::get_spec(self : LanguageToolkit) -> @types.KGFSpec {
  self.spec
}

///|
/// The compiled lexer for this language (built once from spec tokens).
pub fn LanguageToolkit::get_lexer(self : LanguageToolkit) -> @lexer.Lexer {
  self.lexer
}

///|
/// Token kinds that represent identifiers (e.g. Ident, TypeIdent).
pub fn LanguageToolkit::get_identifier_set(
  self : LanguageToolkit,
) -> Map[String, Bool] {
  self.identifier_set
}

///|
/// Token kinds whose text content should be sub-tokenized for vocabulary
/// comparison (e.g. doc comments, string literals).
pub fn LanguageToolkit::get_vocabulary_set(
  self : LanguageToolkit,
) -> Map[String, Bool] {
  self.vocabulary_set
}

///|
/// Keywords allowed in proxy function bodies (function_keyword + self_keyword).
pub fn LanguageToolkit::get_allowed_keywords(
  self : LanguageToolkit,
) -> Map[String, Bool] {
  self.allowed_keywords
}

///|
/// Qualifier separator token kinds (DOT, DCOLON, SCOPE, etc.).
pub fn LanguageToolkit::get_qualifier_separators(
  self : LanguageToolkit,
) -> Map[String, Bool] {
  self.qualifier_separators
}

///|
/// Self-keyword token kinds (KW_self, KW_this, etc.).
pub fn LanguageToolkit::get_self_keywords(
  self : LanguageToolkit,
) -> Map[String, Bool] {
  self.self_keywords
}

///|
/// Tokenize source content using the cached lexer.
pub fn LanguageToolkit::tokenize(
  self : LanguageToolkit,
  content : String,
) -> Array[@types.Tok] {
  self.lexer.tokenize(content)
}

///|
/// Apply preprocessing steps from the spec to content, then tokenize.
pub fn LanguageToolkit::preprocess_and_tokenize(
  self : LanguageToolkit,
  content : String,
) -> Array[@types.Tok] {
  let prepared = self.preprocess(content)
  self.lexer.tokenize(prepared)
}

///|
/// Apply preprocessing steps from the spec to content.
/// Returns content unchanged if no preprocess section exists.
pub fn LanguageToolkit::preprocess(
  self : LanguageToolkit,
  content : String,
) -> String {
  match self.spec.get_preprocess() {
    Some(steps) =>
      @preprocess.apply_preprocess(
        content,
        Some(steps),
        self.spec.get_preprocess_fst(),
      ) catch {
        _ => panic()
      }
    None => content
  }
}

///|
/// Check if a token kind is an identifier.
pub fn LanguageToolkit::is_identifier(
  self : LanguageToolkit,
  kind : String,
) -> Bool {
  self.identifier_set.contains(kind)
}

///|
/// Check if a token kind is a keyword.
pub fn LanguageToolkit::is_keyword(
  self : LanguageToolkit,
  kind : String,
) -> Bool {
  self.spec.is_keyword(kind)
}

// ── Helpers ──

///|
fn build_set_from_feature(
  spec : @types.KGFSpec,
  feature_name : String,
) -> Map[String, Bool] {
  let set : Map[String, Bool] = {}
  match spec.get_feature(feature_name) {
    Some(values) =>
      for v in values {
        set[v] = true
      }
    None => ()
  }
  set
}
