// Type definitions for APTED (All Path Tree Edit Distance) algorithm.

///|
/// Generic tree node representation for tree edit distance computation.
pub struct TreeNode {
  /// Label identifying this node type/value.
  label : String
  /// Child nodes (ordered).
  children : Array[TreeNode]
} derive(Eq, Show)

///|
/// Create a leaf node with no children.
pub fn TreeNode::leaf(label : String) -> TreeNode {
  { label, children: [] }
}

///|
/// Create a node with children.
pub fn TreeNode::node(label : String, children : Array[TreeNode]) -> TreeNode {
  { label, children }
}

///|
/// Get the label.
pub fn TreeNode::get_label(self : TreeNode) -> String {
  self.label
}

///|
/// Get the children.
pub fn TreeNode::get_children(self : TreeNode) -> Array[TreeNode] {
  self.children
}

///|
/// Check if this is a leaf node.
pub fn TreeNode::is_leaf(self : TreeNode) -> Bool {
  self.children.length() == 0
}

///|
/// Calculate the size of the tree (total number of nodes).
pub fn TreeNode::size(self : TreeNode) -> Int {
  let mut total = 1
  for child in self.children {
    total = total + child.size()
  }
  total
}

///|
/// Calculate the height of the tree.
pub fn TreeNode::height(self : TreeNode) -> Int {
  if self.children.length() == 0 {
    return 1
  }
  let mut max_child_height = 0
  for child in self.children {
    let h = child.height()
    if h > max_child_height {
      max_child_height = h
    }
  }
  1 + max_child_height
}

///|
/// Node information for APTED algorithm indexing.
/// Computed during tree preprocessing.
pub struct NodeInfo {
  /// The node reference.
  node : TreeNode
  /// Preorder index (0-based).
  id : Int
  /// Parent's preorder index (-1 for root).
  parent : Int
  /// Index of leftmost leaf descendant.
  left_most_leaf : Int
  /// Size of subtree rooted at this node.
  subtree_size : Int
} derive(Eq, Show)

///|
/// Create a new NodeInfo.
pub fn NodeInfo::new(
  node : TreeNode,
  id : Int,
  parent : Int,
  left_most_leaf : Int,
  subtree_size : Int,
) -> NodeInfo {
  { node, id, parent, left_most_leaf, subtree_size }
}

///|
/// Get the node.
pub fn NodeInfo::get_node(self : NodeInfo) -> TreeNode {
  self.node
}

///|
/// Get the preorder id.
pub fn NodeInfo::get_id(self : NodeInfo) -> Int {
  self.id
}

///|
/// Get the parent index.
pub fn NodeInfo::get_parent(self : NodeInfo) -> Int {
  self.parent
}

///|
/// Get the leftmost leaf index.
pub fn NodeInfo::get_left_most_leaf(self : NodeInfo) -> Int {
  self.left_most_leaf
}

///|
/// Get the subtree size.
pub fn NodeInfo::get_subtree_size(self : NodeInfo) -> Int {
  self.subtree_size
}

///|
/// Cost configuration for tree edit operations.
pub struct CostConfig {
  /// Cost to insert a node.
  insert_cost : Double
  /// Cost to delete a node.
  delete_cost : Double
  /// Cost to rename a node (when labels differ).
  rename_cost : Double
} derive(Eq, Show)

///|
/// Create default cost config (all operations cost 1.0).
pub fn CostConfig::default() -> CostConfig {
  { insert_cost: 1.0, delete_cost: 1.0, rename_cost: 1.0 }
}

///|
/// Create custom cost config.
pub fn CostConfig::create(
  insert_cost : Double,
  delete_cost : Double,
  rename_cost : Double,
) -> CostConfig {
  { insert_cost, delete_cost, rename_cost }
}

///|
/// Get the insert cost.
pub fn CostConfig::get_insert_cost(self : CostConfig) -> Double {
  self.insert_cost
}

///|
/// Get the delete cost.
pub fn CostConfig::get_delete_cost(self : CostConfig) -> Double {
  self.delete_cost
}

///|
/// Get the rename cost.
pub fn CostConfig::get_rename_cost(self : CostConfig) -> Double {
  self.rename_cost
}

///|
/// Calculate the cost to transform one label to another.
pub fn CostConfig::label_cost(
  self : CostConfig,
  label1 : String,
  label2 : String,
) -> Double {
  if label1 == label2 {
    0.0
  } else {
    self.rename_cost
  }
}

///|
/// Configuration for TSED (Tree Structure Edit Distance) calculation.
pub struct TSEDConfig {
  /// Base cost configuration for edit operations.
  cost_config : CostConfig
  /// Append child count to non-leaf labels (e.g., "Seq" → "Seq_3").
  finalize_labels : Bool
} derive(Eq, Show)

///|
/// Create default TSED configuration.
pub fn TSEDConfig::default() -> TSEDConfig {
  { cost_config: CostConfig::default(), finalize_labels: true }
}

///|
/// Create a new tree with finalized labels.
/// Non-leaf nodes get child count appended: "Seq" → "Seq_3" (if 3 children).
/// Leaf nodes are unchanged. The original tree is not modified.
pub fn TreeNode::with_finalized_labels(self : TreeNode) -> TreeNode {
  if self.is_leaf() {
    TreeNode::leaf(self.label)
  } else {
    let new_children : Array[TreeNode] = []
    for child in self.children {
      new_children.push(child.with_finalized_labels())
    }
    let new_label = self.label + "_" + self.children.length().to_string()
    TreeNode::node(new_label, new_children)
  }
}
