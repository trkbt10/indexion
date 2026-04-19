///|
/// KGFSpec represents the complete KGF specification for a language.
///
/// Sections are parsed lazily: the raw text for each === section is stored
/// at construction time and the heavy parsing (lex patterns, grammar rules,
/// semantic blocks, etc.) is deferred until the first accessor call.
/// Once parsed, results are memoized in the corresponding cache field.
///
/// Phase 1 (eager, at registry load):
///   language, resolver, features, ignore
/// Phase 2 (lazy, on first access):
///   tokens, keyword_kinds        — lex section (pattern compilation is heavy)
///   rules, attrs                 — grammar + attrs sections
///   semantics                    — semantics section
///   preprocess, preprocess_fst   — preprocess sections
pub struct KGFSpec {
  language : String
  // ── Eager fields (Phase 1) ──────────────────────
  resolver : ResolverSpec
  features : Map[String, Array[String]]?
  ignore : Array[String]?
  // ── Lazy section sources ────────────────────────
  /// Raw text of each === section, kept for deferred parsing.
  mut lex_source : String?
  mut grammar_source : String?
  mut attrs_source : String?
  mut semantics_source : String?
  mut preprocess_source : String?
  mut preprocess_fst_source : String?
  mut classify_source : String?
  // ── Memoized caches ─────────────────────────────
  mut tokens_cache : Array[TokenDef]?
  mut keyword_kinds_cache : Map[String, Bool]?
  mut rules_cache : Map[String, RuleDef]?
  mut attrs_cache : Map[String, Array[AttrAction]]?
  mut semantics_cache : Map[String, Array[SemOnBlock]]??
  mut preprocess_cache : Array[String]??
  mut preprocess_fst_cache : Array[PreprocessFstSpec]??
  mut classify_cache : ClassifyModel??
}

///|
/// Creates a new KGFSpec with all sections eagerly populated (legacy path).
/// Used by tests and code that already has parsed results.
pub fn KGFSpec::new(
  language : String,
  tokens? : Array[TokenDef] = [],
  keyword_kinds? : Map[String, Bool] = {},
  rules? : Map[String, RuleDef] = Map::new(),
  attrs? : Map[String, Array[AttrAction]] = Map::new(),
  resolver? : ResolverSpec = ResolverSpec::new(),
  features? : Map[String, Array[String]]? = None,
  semantics? : Map[String, Array[SemOnBlock]]? = None,
  preprocess? : Array[String]? = None,
  preprocess_fst? : Array[PreprocessFstSpec]? = None,
  ignore? : Array[String]? = None,
  classify? : ClassifyModel? = None,
) -> KGFSpec {
  {
    language,
    resolver,
    features,
    ignore,
    // No raw sources — caches are pre-filled
    lex_source: None,
    grammar_source: None,
    attrs_source: None,
    semantics_source: None,
    preprocess_source: None,
    preprocess_fst_source: None,
    classify_source: None,
    tokens_cache: Some(tokens),
    keyword_kinds_cache: Some(keyword_kinds),
    rules_cache: Some(rules),
    attrs_cache: Some(attrs),
    semantics_cache: Some(semantics),
    preprocess_cache: Some(preprocess),
    preprocess_fst_cache: Some(preprocess_fst),
    classify_cache: Some(classify),
  }
}

///|
/// Creates a KGFSpec with deferred section parsing.
/// Only language, resolver, features, and ignore are parsed eagerly.
/// The raw section texts are stored for lazy parsing on first access.
pub fn KGFSpec::new_lazy(
  language : String,
  resolver : ResolverSpec,
  features : Map[String, Array[String]]?,
  ignore : Array[String]?,
  lex_source : String,
  grammar_source : String,
  attrs_source : String,
  semantics_source : String,
  preprocess_source : String,
  preprocess_fst_source : String,
  classify_source : String,
) -> KGFSpec {
  {
    language,
    resolver,
    features,
    ignore,
    lex_source: Some(lex_source),
    grammar_source: Some(grammar_source),
    attrs_source: Some(attrs_source),
    semantics_source: Some(semantics_source),
    preprocess_source: Some(preprocess_source),
    preprocess_fst_source: Some(preprocess_fst_source),
    classify_source: Some(classify_source),
    tokens_cache: None,
    keyword_kinds_cache: None,
    rules_cache: None,
    attrs_cache: None,
    semantics_cache: None,
    preprocess_cache: None,
    preprocess_fst_cache: None,
    classify_cache: None,
  }
}

///|
/// Returns the language name.
pub fn KGFSpec::get_language(self : KGFSpec) -> String {
  self.language
}

///|
/// Returns the tokens (lazy: parses lex section on first call).
pub fn KGFSpec::get_tokens(self : KGFSpec) -> Array[TokenDef] {
  self.ensure_lex_parsed()
  self.tokens_cache.unwrap_or([])
}

///|
/// Returns the keyword kinds set (lazy: parses lex section on first call).
pub fn KGFSpec::get_keyword_kinds(self : KGFSpec) -> Map[String, Bool] {
  self.ensure_lex_parsed()
  self.keyword_kinds_cache.unwrap_or({})
}

///|
/// Returns true if the given token kind is classified as a keyword.
pub fn KGFSpec::is_keyword(self : KGFSpec, kind : String) -> Bool {
  self.get_keyword_kinds().contains(kind)
}

///|
/// Returns the rules (lazy: parses grammar section on first call).
pub fn KGFSpec::get_rules(self : KGFSpec) -> Map[String, RuleDef] {
  self.ensure_grammar_parsed()
  self.rules_cache.unwrap_or(Map::new())
}

///|
/// Returns a specific rule by name.
pub fn KGFSpec::get_rule(self : KGFSpec, name : String) -> RuleDef? {
  self.get_rules().get(name)
}

///|
/// Returns the attributes (lazy: parses attrs section on first call).
pub fn KGFSpec::get_attrs(self : KGFSpec) -> Map[String, Array[AttrAction]] {
  self.ensure_attrs_parsed()
  self.attrs_cache.unwrap_or(Map::new())
}

///|
/// Returns a specific attribute actions by name.
pub fn KGFSpec::get_attr(self : KGFSpec, name : String) -> Array[AttrAction]? {
  self.get_attrs().get(name)
}

///|
/// Returns the resolver configuration (eager — always available).
pub fn KGFSpec::get_resolver(self : KGFSpec) -> ResolverSpec {
  self.resolver
}

///|
/// Returns KGF feature metadata (eager — always available).
pub fn KGFSpec::get_features(self : KGFSpec) -> Map[String, Array[String]]? {
  self.features
}

///|
/// Returns a specific feature value list by name.
pub fn KGFSpec::get_feature(self : KGFSpec, name : String) -> Array[String]? {
  match self.features {
    Some(features) => features.get(name)
    None => None
  }
}

///|
/// Returns the semantics (lazy: parses semantics section on first call).
pub fn KGFSpec::get_semantics(
  self : KGFSpec,
) -> Map[String, Array[SemOnBlock]]? {
  self.ensure_semantics_parsed()
  self.semantics_cache.unwrap_or(None)
}

///|
/// Returns specific semantic blocks by rule name.
pub fn KGFSpec::get_semantic(
  self : KGFSpec,
  rule_name : String,
) -> Array[SemOnBlock]? {
  match self.get_semantics() {
    Some(sem) => sem.get(rule_name)
    None => None
  }
}

///|
/// Returns the preprocess directives (lazy).
pub fn KGFSpec::get_preprocess(self : KGFSpec) -> Array[String]? {
  self.ensure_preprocess_parsed()
  self.preprocess_cache.unwrap_or(None)
}

///|
/// Returns the preprocess FST specifications (lazy).
pub fn KGFSpec::get_preprocess_fst(self : KGFSpec) -> Array[PreprocessFstSpec]? {
  self.ensure_preprocess_fst_parsed()
  self.preprocess_fst_cache.unwrap_or(None)
}

///|
/// Returns the classify model (lazy: parses classify section on first call).
/// The model contains trained weights computed from a document corpus,
/// not hand-authored vocabulary lists.
pub fn KGFSpec::get_classify(self : KGFSpec) -> ClassifyModel? {
  self.ensure_classify_parsed()
  self.classify_cache.unwrap_or(None)
}

///|
/// Returns the ignore patterns for this language (eager — always available).
pub fn KGFSpec::get_ignore(self : KGFSpec) -> Array[String]? {
  self.ignore
}

///|
/// Returns the start rule name.
/// Uses convention: "Module" > "Program" > "Doc" > "File" > first rule found.
pub fn KGFSpec::get_start_rule(self : KGFSpec) -> String {
  let rules = self.get_rules()
  let conventions = ["Module", "Program", "Doc", "File"]
  for name in conventions {
    if rules.contains(name) {
      return name
    }
  }
  for entry in rules {
    return entry.0
  }
  ""
}

///|
/// Names of the `=== features` entries whose values are token kind names
/// (as opposed to booleans, strings, or token values).
///
/// This is the single source of truth for the set of "token-referencing
/// features" — any consumer that walks feature values as token kinds (e.g.
/// `kgf check` validation, `kgf tokenize` feature enrichment) must iterate
/// this list rather than redeclaring it locally. Adding a new token-valued
/// feature requires updating this list only.
pub fn token_referencing_feature_names() -> Array[String] {
  [
    FEATURE_SECTION_TOKEN,
    FEATURE_HEADING_TEXT_TOKENS,
    FEATURE_REFERENCE_TOKEN_KINDS,
    FEATURE_COVERAGE_TOKEN_KINDS,
    FEATURE_VOCABULARY_TOKEN_KINDS,
    FEATURE_IDENTIFIER_KINDS,
    FEATURE_EMBEDDED_CODE_FENCE,
    FEATURE_EMBEDDED_CONTENT_TOKEN,
  ]
}

///|
/// KGF feature name constants. These strings appear in `=== features`
/// sections of .kgf files — treating them as first-class identifiers in
/// MoonBit avoids spelling drift between call sites.
pub const FEATURE_SECTION_TOKEN : String = "section_token"

///|
pub const FEATURE_HEADING_TEXT_TOKENS : String = "heading_text_tokens"

///|
pub const FEATURE_REFERENCE_TOKEN_KINDS : String = "reference_token_kinds"

///|
pub const FEATURE_COVERAGE_TOKEN_KINDS : String = "coverage_token_kinds"

///|
pub const FEATURE_VOCABULARY_TOKEN_KINDS : String = "vocabulary_token_kinds"

///|
pub const FEATURE_IDENTIFIER_KINDS : String = "identifier_kinds"

///|
pub const FEATURE_EMBEDDED_CODE_FENCE : String = "embedded_code_fence"

///|
pub const FEATURE_EMBEDDED_CONTENT_TOKEN : String = "embedded_content_token"

// ── Lazy parsing helpers ──────────────────────────

///|
/// Parse the lex section if not yet parsed, and cache the results.
/// Uses the `parse_lex_section` callback registered by the parser package.
fn KGFSpec::ensure_lex_parsed(self : KGFSpec) -> Unit {
  if self.tokens_cache is Some(_) {
    return
  }
  match self.lex_source {
    Some(source) => {
      let (tokens, keyword_kinds) = (parse_lex_lazy.val)(source)
      self.tokens_cache = Some(tokens)
      self.keyword_kinds_cache = Some(keyword_kinds)
      self.lex_source = None // Free memory
    }
    None => {
      self.tokens_cache = Some([])
      self.keyword_kinds_cache = Some({})
    }
  }
}

///|
/// Parse the grammar section if not yet parsed.
fn KGFSpec::ensure_grammar_parsed(self : KGFSpec) -> Unit {
  if self.rules_cache is Some(_) {
    return
  }
  match self.grammar_source {
    Some(source) => {
      self.rules_cache = Some((parse_grammar_lazy.val)(source))
      self.grammar_source = None
    }
    None => self.rules_cache = Some(Map::new())
  }
}

///|
/// Parse the attrs section if not yet parsed.
fn KGFSpec::ensure_attrs_parsed(self : KGFSpec) -> Unit {
  if self.attrs_cache is Some(_) {
    return
  }
  match self.attrs_source {
    Some(source) => {
      self.attrs_cache = Some((parse_attrs_lazy.val)(source))
      self.attrs_source = None
    }
    None => self.attrs_cache = Some(Map::new())
  }
}

///|
/// Parse the semantics section if not yet parsed.
fn KGFSpec::ensure_semantics_parsed(self : KGFSpec) -> Unit {
  if self.semantics_cache is Some(_) {
    return
  }
  match self.semantics_source {
    Some(source) => {
      self.semantics_cache = Some((parse_semantics_lazy.val)(source))
      self.semantics_source = None
    }
    None => self.semantics_cache = Some(None)
  }
}

///|
/// Parse the preprocess section if not yet parsed.
fn KGFSpec::ensure_preprocess_parsed(self : KGFSpec) -> Unit {
  if self.preprocess_cache is Some(_) {
    return
  }
  match self.preprocess_source {
    Some(source) => {
      self.preprocess_cache = Some((parse_preprocess_lazy.val)(source))
      self.preprocess_source = None
    }
    None => self.preprocess_cache = Some(None)
  }
}

///|
/// Parse the preprocess_fst section if not yet parsed.
fn KGFSpec::ensure_preprocess_fst_parsed(self : KGFSpec) -> Unit {
  if self.preprocess_fst_cache is Some(_) {
    return
  }
  match self.preprocess_fst_source {
    Some(source) => {
      self.preprocess_fst_cache = Some((parse_preprocess_fst_lazy.val)(source))
      self.preprocess_fst_source = None
    }
    None => self.preprocess_fst_cache = Some(None)
  }
}

///|
/// Parse the classify section if not yet parsed.
fn KGFSpec::ensure_classify_parsed(self : KGFSpec) -> Unit {
  if self.classify_cache is Some(_) {
    return
  }
  match self.classify_source {
    Some(source) => {
      self.classify_cache = Some((parse_classify_lazy.val)(source))
      self.classify_source = None
    }
    None => self.classify_cache = Some(None)
  }
}

// ── Parser callbacks (set by the parser package to avoid circular deps) ──

///|
/// Callback: parse lex section text → (tokens, keyword_kinds).
/// Set by the parser package at init time.
pub let parse_lex_lazy : Ref[(String) -> (Array[TokenDef], Map[String, Bool])] = Ref::new(fn(
    _s,
  ) {
    ([], {})
  },
)

///|
/// Callback: parse grammar section text → rules.
pub let parse_grammar_lazy : Ref[(String) -> Map[String, RuleDef]] = Ref::new(fn(
  _s,
) {
  Map::new()
})

///|
/// Callback: parse attrs section text → attrs.
pub let parse_attrs_lazy : Ref[(String) -> Map[String, Array[AttrAction]]] = Ref::new(fn(
    _s,
  ) {
    Map::new()
  },
)

///|
/// Callback: parse semantics section text → semantics.
pub let parse_semantics_lazy : Ref[(String) -> Map[String, Array[SemOnBlock]]?] = Ref::new(fn(
    _s,
  ) {
    None
  },
)

///|
/// Callback: parse preprocess section text → preprocess directives.
pub let parse_preprocess_lazy : Ref[(String) -> Array[String]?] = Ref::new(fn(
  _s,
) {
  None
})

///|
/// Callback: parse preprocess_fst section text → FST specs.
pub let parse_preprocess_fst_lazy : Ref[(String) -> Array[PreprocessFstSpec]?] = Ref::new(fn(
    _s,
  ) {
    None
  },
)

///|
/// Callback: parse classify section text → trained classify model.
pub let parse_classify_lazy : Ref[(String) -> ClassifyModel?] = Ref::new(fn(
  _s,
) {
  None
})
