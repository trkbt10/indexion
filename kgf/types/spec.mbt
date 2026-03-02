///|
/// KGFSpec represents the complete KGF specification for a language.
/// Contains tokens, rules, attributes, resolver configuration, semantics, and preprocessing options.
pub struct KGFSpec {
  language : String
  tokens : Array[TokenDef]
  rules : Map[String, RuleDef]
  attrs : Map[String, Array[AttrAction]]
  resolver : ResolverSpec
  semantics : Map[String, Array[SemOnBlock]]?
  preprocess : Array[String]?
  preprocess_fst : Array[PreprocessFstSpec]?
}

///|
/// Creates a new KGFSpec with the specified parameters.
pub fn KGFSpec::new(
  language : String,
  tokens? : Array[TokenDef] = [],
  rules? : Map[String, RuleDef] = Map::new(),
  attrs? : Map[String, Array[AttrAction]] = Map::new(),
  resolver? : ResolverSpec = ResolverSpec::new(),
  semantics? : Map[String, Array[SemOnBlock]]? = None,
  preprocess? : Array[String]? = None,
  preprocess_fst? : Array[PreprocessFstSpec]? = None
) -> KGFSpec {
  { language, tokens, rules, attrs, resolver, semantics, preprocess, preprocess_fst }
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
