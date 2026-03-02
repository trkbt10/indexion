///|
/// RuleDef represents a grammar rule definition.
/// Contains the rule name and its expression.
pub struct RuleDef {
  name : String
  expr : String
}

///|
/// Creates a new RuleDef with the specified parameters.
pub fn RuleDef::new(name : String, expr : String) -> RuleDef {
  { name, expr }
}

///|
/// Returns the name of the rule.
pub fn RuleDef::get_name(self : RuleDef) -> String {
  self.name
}

///|
/// Returns the expression of the rule.
pub fn RuleDef::get_expr(self : RuleDef) -> String {
  self.expr
}

///|
/// AttrAction represents an attribute action in the grammar.
/// Kind can be: "def", "ref", "call", "argref", "import", "reexport",
/// "scope", "arg_begin", "arg_end", "call_end", etc.
pub struct AttrAction {
  kind : String
  params : Map[String, String]
}

///|
/// Creates a new AttrAction with the specified parameters.
pub fn AttrAction::new(
  kind : String,
  params? : Map[String, String] = Map::new(),
) -> AttrAction {
  { kind, params }
}

///|
/// Returns the kind of the attribute action.
pub fn AttrAction::get_kind(self : AttrAction) -> String {
  self.kind
}

///|
/// Returns the params of the attribute action.
pub fn AttrAction::get_params(self : AttrAction) -> Map[String, String] {
  self.params
}

///|
/// Returns a specific parameter value by key.
pub fn AttrAction::get_param(self : AttrAction, key : String) -> String? {
  self.params.get(key)
}
