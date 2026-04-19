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
} derive(Debug, Eq, Hash)

///|
pub impl Show for Node with output(self, logger) {
  to_repr(self).output(logger)
}

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
  FFail // Always fails to match (used for undefined symbol references)
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

// Node variants are destructured directly via `match`/`is` at every consumer;
// the `is_*` / `get_*` mirror APIs previously exposed here are therefore
// removed. Restore a specific pair only when an external caller needs a
// boolean-returning form that the pattern-match sugar cannot express.
