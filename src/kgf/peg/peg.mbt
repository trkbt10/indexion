///|
/// PEG represents a compiled PEG grammar with parsed rule ASTs.
pub struct PEG {
  tokens : @hashset.HashSet[String]
  ast : Map[String, Node]
  attrs : Map[String, Array[@types.AttrAction]]
  compiled_nodes : Array[CompiledNode]
  rule_node_ids : Map[String, Int]
  // Fast evaluation support
  token_ids : Map[String, Int] // token name -> integer ID
  fast_nodes : Array[FastCompiledNode] // pre-compiled with IDs
  fast_rule_ids : Map[String, Int] // rule name -> fast node ID (FRuleRef)
  fast_rule_body_ids : Map[String, Int] // rule name -> body node ID (direct)
}

///|
/// Creates a new empty PEG.
pub fn PEG::new() -> PEG {
  {
    tokens: @hashset.new(),
    ast: Map::new(),
    attrs: Map::new(),
    compiled_nodes: [],
    rule_node_ids: Map::new(),
    token_ids: Map::new(),
    fast_nodes: [],
    fast_rule_ids: Map::new(),
    fast_rule_body_ids: Map::new(),
  }
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
/// Gets the token ID for a token name.
fn PEG::get_token_id(self : PEG, name : String) -> Int? {
  self.token_ids.get(name)
}

///|
/// Gets the body node id for a rule (without FRuleRef wrapper).
fn PEG::get_fast_rule_body_id(self : PEG, name : String) -> Int? {
  self.fast_rule_body_ids.get(name)
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
  let token_ids : Map[String, Int] = Map::new()
  // Collect non-skip tokens and assign IDs
  let mut token_id_counter = 0
  for token_def in spec.tokens {
    if not(token_def.skip) {
      tokens.add(token_def.name)
      token_ids.set(token_def.name, token_id_counter)
      token_id_counter = token_id_counter + 1
    }
  }
  let ast : Map[String, Node] = Map::new()
  let compiled_nodes : Array[CompiledNode] = []
  let rule_node_ids : Map[String, Int] = Map::new()
  // Parse all rule expressions (original compiled nodes)
  for name, rule_def in spec.rules {
    let node = parse_expr(rule_def.expr)
    ast.set(name, node)
    let node_id = compile_node(node, compiled_nodes)
    rule_node_ids.set(name, node_id)
  }
  // Build fast nodes with pre-computed IDs (two-pass)
  let fast_nodes : Array[FastCompiledNode] = []
  let fast_rule_ids : Map[String, Int] = Map::new()
  let fast_rule_body_ids : Map[String, Int] = Map::new()
  // First pass: reserve IDs for rule body placeholders
  for name, _ in spec.rules {
    fast_rule_ids.set(name, fast_nodes.length())
    fast_nodes.push(FEmpty) // placeholder
  }
  // Second pass: compile rule bodies with rule IDs already known
  for name, rule_def in spec.rules {
    let node = parse_expr(rule_def.expr)
    let body_node_id = compile_fast_node(
      node, fast_nodes, tokens, token_ids, fast_rule_ids,
    )
    // Update placeholder to point to body
    let rule_id = fast_rule_ids.get(name).unwrap()
    fast_nodes[rule_id] = FRuleRef(body_node_id, name)
    // Also track body ID for direct access
    fast_rule_body_ids.set(name, body_node_id)
  }
  {
    tokens,
    ast,
    attrs: spec.attrs,
    compiled_nodes,
    rule_node_ids,
    token_ids,
    fast_nodes,
    fast_rule_ids,
    fast_rule_body_ids,
  }
}

///|
/// Compiles an AST node into fast ID-based node table.
fn compile_fast_node(
  node : Node,
  out : Array[FastCompiledNode],
  tokens : @hashset.HashSet[String],
  token_ids : Map[String, Int],
  rule_ids : Map[String, Int],
) -> Int {
  let compiled = match node {
    Empty => FEmpty
    Sym(name) =>
      if tokens.contains(name) {
        // Token reference - use pre-computed token ID
        let tid = token_ids.get(name).unwrap_or(0)
        FToken(tid)
      } else {
        // Rule reference - use pre-computed rule node ID
        let rid = rule_ids.get(name).unwrap_or(0)
        FRuleRef(rid, name)
      }
    Seq(nodes) => {
      let children : Array[Int] = []
      for child in nodes {
        children.push(
          compile_fast_node(child, out, tokens, token_ids, rule_ids),
        )
      }
      FSeq(children)
    }
    Choice(nodes) => {
      let children : Array[Int] = []
      for child in nodes {
        children.push(
          compile_fast_node(child, out, tokens, token_ids, rule_ids),
        )
      }
      FChoice(children)
    }
    Star(child) =>
      FStar(compile_fast_node(child, out, tokens, token_ids, rule_ids))
    Plus(child) =>
      FPlus(compile_fast_node(child, out, tokens, token_ids, rule_ids))
    Optional(child) =>
      FOptional(compile_fast_node(child, out, tokens, token_ids, rule_ids))
    Label(name, child) =>
      FLabel(name, compile_fast_node(child, out, tokens, token_ids, rule_ids))
    And(child) =>
      FAnd(compile_fast_node(child, out, tokens, token_ids, rule_ids))
    Not(child) =>
      FNot(compile_fast_node(child, out, tokens, token_ids, rule_ids))
  }
  let id = out.length()
  out.push(compiled)
  id
}

///|
/// Compiles an AST node into ID-based node table for faster evaluation.
fn compile_node(node : Node, out : Array[CompiledNode]) -> Int {
  let compiled = match node {
    Empty => CEmpty
    Sym(name) => CSym(name)
    Seq(nodes) => {
      let children : Array[Int] = []
      for child in nodes {
        children.push(compile_node(child, out))
      }
      CSeq(children)
    }
    Choice(nodes) => {
      let children : Array[Int] = []
      for child in nodes {
        children.push(compile_node(child, out))
      }
      CChoice(children)
    }
    Star(child) => CStar(compile_node(child, out))
    Plus(child) => CPlus(compile_node(child, out))
    Optional(child) => COptional(compile_node(child, out))
    Label(name, child) => CLabel(name, compile_node(child, out))
    And(child) => CAnd(compile_node(child, out))
    Not(child) => CNot(compile_node(child, out))
  }
  let id = out.length()
  out.push(compiled)
  id
}

///|
/// Collects rules that can affect semantic output.
/// This is used to suppress unnecessary parse events for pure grammar rules.
pub fn collect_active_rules(spec : @types.KGFSpec) -> @hashset.HashSet[String] {
  let active : @hashset.HashSet[String] = @hashset.new()
  for entry in spec.get_attrs() {
    active.add(entry.0)
  }
  match spec.get_semantics() {
    Some(semantics) =>
      for entry in semantics {
        active.add(entry.0)
      }
    None => ()
  }
  active
}
