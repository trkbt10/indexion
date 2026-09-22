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
pub impl Show for Node with fn output(self, logger) {
  logger.write_object(Repr(self))
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
  /// The *definition* node of a rule: the one node that stands for a rule
  /// instance in the parse, and therefore the one that emits the rule's
  /// event. `fast_rule_ids[name]` points here.
  FRuleRef(Int, String) // body_node_id, rule_name (name needed for callback)
  /// A *reference* to a rule from inside another rule's body. Pure
  /// indirection: it re-dispatches to the rule's definition node, which is
  /// what emits. Emitting here as well would report every rule instance
  /// twice, once per hop.
  FRuleCall(Int) // rule definition node id
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
