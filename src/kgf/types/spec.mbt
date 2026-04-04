///|
/// KGFSpec represents the complete KGF specification for a language.
/// Contains tokens, rules, attributes, resolver configuration, semantics, and preprocessing options.
pub struct KGFSpec {
  language : String
  tokens : Array[TokenDef]
  /// Token names classified as keywords by `KEYWORD` declarations in the lex section.
  keyword_kinds : Map[String, Bool]
  rules : Map[String, RuleDef]
  attrs : Map[String, Array[AttrAction]]
  resolver : ResolverSpec
  features : Map[String, Array[String]]?
  semantics : Map[String, Array[SemOnBlock]]?
  preprocess : Array[String]?
  preprocess_fst : Array[PreprocessFstSpec]?
  ignore : Array[String]?
}

///|
/// Creates a new KGFSpec with the specified parameters.
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
) -> KGFSpec {
  {
    language,
    tokens,
    keyword_kinds,
    rules,
    attrs,
    resolver,
    features,
    semantics,
    preprocess,
    preprocess_fst,
    ignore,
  }
}

///|
/// Returns the language name.
pub fn KGFSpec::get_language(self : KGFSpec) -> String {
  self.language
}

///|
/// Returns the tokens.
pub fn KGFSpec::get_tokens(self : KGFSpec) -> Array[TokenDef] {
  self.tokens
}

///|
/// Returns the keyword kinds set.
pub fn KGFSpec::get_keyword_kinds(self : KGFSpec) -> Map[String, Bool] {
  self.keyword_kinds
}

///|
/// Returns true if the given token kind is classified as a keyword.
pub fn KGFSpec::is_keyword(self : KGFSpec, kind : String) -> Bool {
  self.keyword_kinds.contains(kind)
}

///|
/// Returns the rules.
pub fn KGFSpec::get_rules(self : KGFSpec) -> Map[String, RuleDef] {
  self.rules
}

///|
/// Returns a specific rule by name.
pub fn KGFSpec::get_rule(self : KGFSpec, name : String) -> RuleDef? {
  self.rules.get(name)
}

///|
/// Returns the attributes.
pub fn KGFSpec::get_attrs(self : KGFSpec) -> Map[String, Array[AttrAction]] {
  self.attrs
}

///|
/// Returns a specific attribute actions by name.
pub fn KGFSpec::get_attr(self : KGFSpec, name : String) -> Array[AttrAction]? {
  self.attrs.get(name)
}

///|
/// Returns the resolver configuration.
pub fn KGFSpec::get_resolver(self : KGFSpec) -> ResolverSpec {
  self.resolver
}

///|
/// Returns KGF feature metadata.
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
/// Returns the semantics.
pub fn KGFSpec::get_semantics(
  self : KGFSpec,
) -> Map[String, Array[SemOnBlock]]? {
  self.semantics
}

///|
/// Returns specific semantic blocks by rule name.
pub fn KGFSpec::get_semantic(
  self : KGFSpec,
  rule_name : String,
) -> Array[SemOnBlock]? {
  match self.semantics {
    Some(sem) => sem.get(rule_name)
    None => None
  }
}

///|
/// Returns the preprocess directives.
pub fn KGFSpec::get_preprocess(self : KGFSpec) -> Array[String]? {
  self.preprocess
}

///|
/// Returns the preprocess FST specifications.
pub fn KGFSpec::get_preprocess_fst(self : KGFSpec) -> Array[PreprocessFstSpec]? {
  self.preprocess_fst
}

///|
/// Returns the ignore patterns for this language.
pub fn KGFSpec::get_ignore(self : KGFSpec) -> Array[String]? {
  self.ignore
}

///|
/// Returns the start rule name.
/// Uses convention: "Module" > "Program" > "Doc" > "File" > first rule found.
pub fn KGFSpec::get_start_rule(self : KGFSpec) -> String {
  // Check common conventions in priority order
  let conventions = ["Module", "Program", "Doc", "File"]
  for name in conventions {
    if self.rules.contains(name) {
      return name
    }
  }
  // Fall back to first rule found
  for entry in self.rules {
    return entry.0
  }
  // No rules
  ""
}
