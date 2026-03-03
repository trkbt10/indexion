// Tree indexing for Zhang-Shasha algorithm.
// Implements postorder traversal and leftmost leaf descendant computation.

///|
/// Indexed node information for Zhang-Shasha algorithm.
/// Uses postorder numbering (1-indexed for algorithm convenience).
pub struct IndexedTree {
  /// Number of nodes in the tree.
  size : Int
  /// Labels of nodes in postorder (index 1..size).
  labels : Array[String]
  /// Leftmost leaf descendant for each node in postorder (index 1..size).
  /// l[i] is the postorder number of the leftmost leaf of subtree rooted at node i.
  leftmost_leaf : Array[Int]
  /// Keyroots: nodes where l(i) != l(parent(i)), plus the root.
  /// Sorted by their leftmost leaf descendant.
  keyroots : Array[Int]
  /// Children count for each node (used for tree reconstruction).
  children_count : Array[Int]
} derive(Show)

///|
/// Create an IndexedTree from a TreeNode.
pub fn IndexedTree::from_tree(root : TreeNode) -> IndexedTree {
  let size = root.size()
  // Arrays are 1-indexed, so allocate size+1
  let labels : Array[String] = Array::make(size + 1, "")
  let leftmost_leaf : Array[Int] = Array::make(size + 1, 0)
  let children_count : Array[Int] = Array::make(size + 1, 0)
  // Postorder traversal to fill arrays
  let postorder_counter : PostorderCounter = { val: 0 }
  ignore(
    fill_postorder(
      root, labels, leftmost_leaf, children_count, postorder_counter,
    ),
  )
  // Compute keyroots
  // A node i is a keyroot if it's the root OR l(i) != l(parent(i))
  let keyroots = compute_keyroots(size, leftmost_leaf)
  { size, labels, leftmost_leaf, keyroots, children_count }
}

///|
/// Mutable counter for postorder traversal.
priv struct PostorderCounter {
  mut val : Int
}

///|
/// Fill arrays using postorder traversal.
/// Returns the postorder number of this node.
fn fill_postorder(
  node : TreeNode,
  labels : Array[String],
  leftmost_leaf : Array[Int],
  children_count : Array[Int],
  counter : PostorderCounter,
) -> Int {
  let children = node.get_children()
  // Process children first (postorder)
  let mut my_leftmost = 0
  if children.length() == 0 {
    // Leaf node: leftmost leaf is itself
    counter.val = counter.val + 1
    let my_postorder = counter.val
    labels[my_postorder] = node.get_label()
    leftmost_leaf[my_postorder] = my_postorder
    children_count[my_postorder] = 0
    return my_postorder
  }
  // Non-leaf: process children
  for i = 0; i < children.length(); i = i + 1 {
    let child = children[i]
    let child_postorder = fill_postorder(
      child, labels, leftmost_leaf, children_count, counter,
    )
    if i == 0 {
      my_leftmost = leftmost_leaf[child_postorder]
    }
  }
  // Now assign postorder to this node
  counter.val = counter.val + 1
  let my_postorder = counter.val
  labels[my_postorder] = node.get_label()
  leftmost_leaf[my_postorder] = my_leftmost
  children_count[my_postorder] = children.length()
  my_postorder
}

///|
/// Compute keyroots from leftmost_leaf array.
fn compute_keyroots(size : Int, leftmost_leaf : Array[Int]) -> Array[Int] {
  // For Zhang-Shasha, keyroots are nodes where:
  // - The node is the root, OR
  // - l(i) != l(parent(i))
  //
  // Alternative definition: for each distinct l value, the rightmost node with that l value
  // is a keyroot.
  //
  // We use the second definition which is easier to compute.
  let visited_l : Array[Bool] = Array::make(size + 1, false)
  let keyroots : Array[Int] = []
  // Traverse in reverse postorder (from root to leaves)
  for i = size; i >= 1; i = i - 1 {
    let l = leftmost_leaf[i]
    if not(visited_l[l]) {
      visited_l[l] = true
      keyroots.push(i)
    }
  }
  // Sort keyroots by postorder number (ascending).
  // This ensures inner subtrees are processed before outer subtrees,
  // so tree_dist[x][y] is available when needed in the else branch
  // of compute_forest_dist.
  sort_keyroots_by_postorder(keyroots)
  keyroots
}

///|
/// Sort keyroots by their postorder number (ascending).
fn sort_keyroots_by_postorder(keyroots : Array[Int]) -> Unit {
  // Insertion sort
  for i = 1; i < keyroots.length(); i = i + 1 {
    let key = keyroots[i]
    let mut j = i - 1
    while j >= 0 && keyroots[j] > key {
      keyroots[j + 1] = keyroots[j]
      j = j - 1
    }
    keyroots[j + 1] = key
  }
}

///|
/// Get the tree size.
pub fn IndexedTree::get_size(self : IndexedTree) -> Int {
  self.size
}

///|
/// Get label at postorder index i (1-indexed).
pub fn IndexedTree::get_label(self : IndexedTree, i : Int) -> String {
  self.labels[i]
}

///|
/// Get leftmost leaf at postorder index i (1-indexed).
pub fn IndexedTree::get_l(self : IndexedTree, i : Int) -> Int {
  self.leftmost_leaf[i]
}

///|
/// Get keyroots array.
pub fn IndexedTree::get_keyroots(self : IndexedTree) -> Array[Int] {
  self.keyroots
}

// Legacy functions for backward compatibility

///|
/// Index a tree (legacy wrapper).
pub fn index_tree(root : TreeNode) -> Array[NodeInfo] {
  let infos : Array[NodeInfo] = []
  ignore(index_recursive(root, -1, infos))
  infos
}

///|
fn index_recursive(
  node : TreeNode,
  parent : Int,
  infos : Array[NodeInfo],
) -> Int {
  let id = infos.length()
  let mut left_most_leaf = id
  let subtree_size = node.size()
  let info = NodeInfo::new(node, id, parent, left_most_leaf, subtree_size)
  infos.push(info)
  if node.children.length() > 0 {
    left_most_leaf = index_recursive(node.children[0], id, infos)
    for i = 1; i < node.children.length(); i = i + 1 {
      ignore(index_recursive(node.children[i], id, infos))
    }
    infos[id] = NodeInfo::new(node, id, parent, left_most_leaf, subtree_size)
  }
  left_most_leaf
}

///|
/// Get keyroots (legacy wrapper).
pub fn get_keyroots(infos : Array[NodeInfo]) -> Array[Int] {
  if infos.length() == 0 {
    return []
  }
  let is_leftmost_child : Array[Bool] = Array::make(infos.length(), false)
  for i = 0; i < infos.length(); i = i + 1 {
    let info = infos[i]
    let parent_idx = info.get_parent()
    if parent_idx >= 0 {
      let parent = infos[parent_idx]
      let parent_node = parent.get_node()
      if parent_node.children.length() > 0 {
        let first_child_id = parent_idx + 1
        if info.get_id() == first_child_id {
          is_leftmost_child[i] = true
        }
      }
    }
  }
  let keyroots : Array[Int] = []
  for i = 0; i < infos.length(); i = i + 1 {
    if not(is_leftmost_child[i]) {
      keyroots.push(i)
    }
  }
  sort_by_lml(keyroots, infos)
  keyroots
}

///|
fn sort_by_lml(keyroots : Array[Int], infos : Array[NodeInfo]) -> Unit {
  for i = 1; i < keyroots.length(); i = i + 1 {
    let key = keyroots[i]
    let key_lml = infos[key].get_left_most_leaf()
    let mut j = i - 1
    while j >= 0 && infos[keyroots[j]].get_left_most_leaf() > key_lml {
      keyroots[j + 1] = keyroots[j]
      j = j - 1
    }
    keyroots[j + 1] = key
  }
}
