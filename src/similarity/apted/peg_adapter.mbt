// Adapter for converting PEG AST nodes to TreeNode for APTED computation.

///|
/// Convert a PEG Node to a TreeNode for APTED computation.
pub fn peg_node_to_tree_node(node : @peg.Node) -> TreeNode {
  match node {
    @peg.Node::Empty => TreeNode::leaf("Empty")
    @peg.Node::Sym(name) => TreeNode::leaf("Sym:" + name)
    @peg.Node::Seq(elems) => {
      let children : Array[TreeNode] = []
      for elem in elems {
        children.push(peg_node_to_tree_node(elem))
      }
      TreeNode::node("Seq", children)
    }
    @peg.Node::Choice(alts) => {
      let children : Array[TreeNode] = []
      for alt in alts {
        children.push(peg_node_to_tree_node(alt))
      }
      TreeNode::node("Choice", children)
    }
    @peg.Node::Star(inner) =>
      TreeNode::node("Star", [peg_node_to_tree_node(inner)])
    @peg.Node::Plus(inner) =>
      TreeNode::node("Plus", [peg_node_to_tree_node(inner)])
    @peg.Node::Optional(inner) =>
      TreeNode::node("Optional", [peg_node_to_tree_node(inner)])
    @peg.Node::Label(name, inner) =>
      TreeNode::node("Label:" + name, [peg_node_to_tree_node(inner)])
  }
}

///|
/// Calculate the size of a PEG node tree.
pub fn peg_node_size(node : @peg.Node) -> Int {
  match node {
    @peg.Node::Empty => 1
    @peg.Node::Sym(_) => 1
    @peg.Node::Seq(elems) => {
      let mut total = 1
      for elem in elems {
        total = total + peg_node_size(elem)
      }
      total
    }
    @peg.Node::Choice(alts) => {
      let mut total = 1
      for alt in alts {
        total = total + peg_node_size(alt)
      }
      total
    }
    @peg.Node::Star(inner) => 1 + peg_node_size(inner)
    @peg.Node::Plus(inner) => 1 + peg_node_size(inner)
    @peg.Node::Optional(inner) => 1 + peg_node_size(inner)
    @peg.Node::Label(_, inner) => 1 + peg_node_size(inner)
  }
}

///|
/// Compute tree edit distance between two PEG nodes.
pub fn peg_tree_edit_distance(
  node1 : @peg.Node,
  node2 : @peg.Node,
  config : CostConfig,
) -> Double {
  let tree1 = peg_node_to_tree_node(node1)
  let tree2 = peg_node_to_tree_node(node2)
  compute_tree_edit_distance(tree1, tree2, config)
}

///|
/// Compute normalized tree edit distance between two PEG nodes.
/// Returns a value in [0, 1] where 0 = identical trees.
pub fn peg_normalized_distance(
  node1 : @peg.Node,
  node2 : @peg.Node,
  config : CostConfig,
) -> Double {
  let tree1 = peg_node_to_tree_node(node1)
  let tree2 = peg_node_to_tree_node(node2)
  normalized_tree_edit_distance(tree1, tree2, config)
}

///|
/// Compute similarity between two PEG nodes.
/// Returns a value in [0, 1] where 1 = identical trees.
pub fn peg_similarity(
  node1 : @peg.Node,
  node2 : @peg.Node,
  config : CostConfig,
) -> Double {
  1.0 - peg_normalized_distance(node1, node2, config)
}

///|
/// Cost configuration optimized for PEG AST comparison.
/// Uses lower cost for renaming between similar node types.
pub fn peg_cost_config() -> CostConfig {
  // For PEG ASTs, we use standard unit costs.
  // In future, could implement more sophisticated cost models
  // that consider node type similarity (e.g., Star vs Plus are similar).
  CostConfig::default()
}

///|
/// Default TSED configuration for PEG AST comparison.
pub fn peg_tsed_config() -> TSEDConfig {
  TSEDConfig::default()
}

///|
/// Compute TSED similarity between two PEG nodes.
/// Returns a value in [0, 1] where 1 = identical trees.
pub fn peg_tsed_similarity(
  node1 : @peg.Node,
  node2 : @peg.Node,
  config : TSEDConfig,
) -> Double {
  let tree1 = peg_node_to_tree_node(node1)
  let tree2 = peg_node_to_tree_node(node2)
  calculate_tsed(tree1, tree2, config)
}

///|
/// Compute TSED distance between two PEG nodes.
/// Returns a value in [0, 1] where 0 = identical trees.
pub fn peg_tsed_distance(
  node1 : @peg.Node,
  node2 : @peg.Node,
  config : TSEDConfig,
) -> Double {
  let tree1 = peg_node_to_tree_node(node1)
  let tree2 = peg_node_to_tree_node(node2)
  calculate_tsed_distance(tree1, tree2, config)
}
