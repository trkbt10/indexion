///|
/// PEG represents a compiled PEG grammar with parsed rule ASTs.
pub struct PEG {
  tokens : @hashset.HashSet[String]
  ast : Map[String, Node]
  attrs : Map[String, Array[@types.AttrAction]]
}

///|
/// Creates a new empty PEG.
pub fn PEG::new() -> PEG {
  { tokens: @hashset.new(), ast: Map::new(), attrs: Map::new() }
}

///|
/// Returns the token set.
pub fn PEG::get_tokens(self : PEG) -> @hashset.HashSet[String] {
  self.tokens
}

///|
/// Checks if a name is a token.
pub fn PEG::is_token(self : PEG, name : String) -> Bool {
  self.tokens.contains(name)
}

///|
/// Returns the AST map.
pub fn PEG::get_ast(self : PEG) -> Map[String, Node] {
  self.ast
}

///|
/// Gets the AST node for a specific rule.
pub fn PEG::get_rule(self : PEG, name : String) -> Node? {
  self.ast.get(name)
}

///|
/// Returns the attributes map.
pub fn PEG::get_attrs(self : PEG) -> Map[String, Array[@types.AttrAction]] {
  self.attrs
}

///|
/// Gets the attribute actions for a specific rule.
pub fn PEG::get_rule_attrs(
  self : PEG,
  name : String,
) -> Array[@types.AttrAction]? {
  self.attrs.get(name)
}

///|
/// Builds a PEG from a KGFSpec.
/// Parses all rule expressions into AST nodes and collects token names.
pub fn build_peg(spec : @types.KGFSpec) -> PEG raise {
  let tokens : @hashset.HashSet[String] = @hashset.new()
  // Collect non-skip tokens
  for token_def in spec.tokens {
    if not(token_def.skip) {
      tokens.add(token_def.name)
    }
  }
  let ast : Map[String, Node] = Map::new()
  // Parse all rule expressions
  for name, rule_def in spec.rules {
    let node = parse_expr(rule_def.expr)
    ast.set(name, node)
  }
  { tokens, ast, attrs: spec.attrs }
}
