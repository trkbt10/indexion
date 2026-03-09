///|
/// PEG AST Node types representing the parsed grammar expression.
/// Conforms to Bryan Ford's PEG specification (POPL 2004).
pub enum Node {
  Empty
  Sym(String)
  Seq(Array[Node])
  Choice(Array[Node])
  Star(Node)
  Plus(Node)
  Optional(Node)
  Label(String, Node)
  And(Node) // &e - positive lookahead (PEG predicate)
  Not(Node) // !e - negative lookahead (PEG predicate)
} derive(Show, Eq, Hash)

///|
/// CompiledNode is an ID-based representation for evaluation hot paths.
/// Note: This is legacy code superseded by FastCompiledNode but kept for API compatibility.
pub enum CompiledNode {
  CEmpty
  CSym(String)
  CSeq(Array[Int])
  CChoice(Array[Int])
  CStar(Int)
  CPlus(Int)
  COptional(Int)
  CLabel(String, Int)
  CAnd(Int) // positive lookahead
  CNot(Int) // negative lookahead
}

///|
/// FastCompiledNode separates tokens and rules for O(1) matching.
/// Token IDs and rule node IDs are pre-computed at compile time.
enum FastCompiledNode {
  FEmpty
  FToken(Int) // token_id only
  FRuleRef(Int, String) // rule_node_id, rule_name (name needed for callback)
  FSeq(Array[Int])
  FChoice(Array[Int])
  FStar(Int)
  FPlus(Int)
  FOptional(Int)
  FLabel(String, Int) // label_name, child (name needed for label propagation)
  FAnd(Int) // child node id - positive lookahead
  FNot(Int) // child node id - negative lookahead
}

///|
/// Returns true if this node is Empty.
pub fn Node::is_empty(self : Node) -> Bool {
  match self {
    Empty => true
    _ => false
  }
}

///|
/// Returns true if this node is a Symbol.
pub fn Node::is_sym(self : Node) -> Bool {
  match self {
    Sym(_) => true
    _ => false
  }
}

///|
/// Gets the symbol name if this is a Sym node.
pub fn Node::get_sym(self : Node) -> String? {
  match self {
    Sym(name) => Some(name)
    _ => None
  }
}

///|
/// Returns true if this node is a Sequence.
pub fn Node::is_seq(self : Node) -> Bool {
  match self {
    Seq(_) => true
    _ => false
  }
}

///|
/// Gets the sequence elements if this is a Seq node.
pub fn Node::get_seq(self : Node) -> Array[Node]? {
  match self {
    Seq(elems) => Some(elems)
    _ => None
  }
}

///|
/// Returns true if this node is a Choice.
pub fn Node::is_choice(self : Node) -> Bool {
  match self {
    Choice(_) => true
    _ => false
  }
}

///|
/// Gets the choice alternatives if this is a Choice node.
pub fn Node::get_choice(self : Node) -> Array[Node]? {
  match self {
    Choice(alts) => Some(alts)
    _ => None
  }
}

///|
/// Returns true if this node is a Star (zero or more).
pub fn Node::is_star(self : Node) -> Bool {
  match self {
    Star(_) => true
    _ => false
  }
}

///|
/// Gets the inner node if this is a Star node.
pub fn Node::get_star(self : Node) -> Node? {
  match self {
    Star(inner) => Some(inner)
    _ => None
  }
}

///|
/// Returns true if this node is a Plus (one or more).
pub fn Node::is_plus(self : Node) -> Bool {
  match self {
    Plus(_) => true
    _ => false
  }
}

///|
/// Gets the inner node if this is a Plus node.
pub fn Node::get_plus(self : Node) -> Node? {
  match self {
    Plus(inner) => Some(inner)
    _ => None
  }
}

///|
/// Returns true if this node is Optional (zero or one).
pub fn Node::is_optional(self : Node) -> Bool {
  match self {
    Optional(_) => true
    _ => false
  }
}

///|
/// Gets the inner node if this is an Optional node.
pub fn Node::get_optional(self : Node) -> Node? {
  match self {
    Optional(inner) => Some(inner)
    _ => None
  }
}

///|
/// Returns true if this node is a Label.
pub fn Node::is_label(self : Node) -> Bool {
  match self {
    Label(_, _) => true
    _ => false
  }
}

///|
/// Gets the label name and inner node if this is a Label node.
pub fn Node::get_label(self : Node) -> (String, Node)? {
  match self {
    Label(name, inner) => Some((name, inner))
    _ => None
  }
}

///|
/// Returns true if this node is an And predicate (positive lookahead).
pub fn Node::is_and(self : Node) -> Bool {
  match self {
    And(_) => true
    _ => false
  }
}

///|
/// Gets the inner node if this is an And node.
pub fn Node::get_and(self : Node) -> Node? {
  match self {
    And(inner) => Some(inner)
    _ => None
  }
}

///|
/// Returns true if this node is a Not predicate (negative lookahead).
pub fn Node::is_not(self : Node) -> Bool {
  match self {
    Not(_) => true
    _ => false
  }
}

///|
/// Gets the inner node if this is a Not node.
pub fn Node::get_not(self : Node) -> Node? {
  match self {
    Not(inner) => Some(inner)
    _ => None
  }
}
