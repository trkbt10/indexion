// TSED (Tree Structure Edit Distance) - Tree similarity using
// normalized edit distance with max-based normalization.
// No magic number penalties.

///|
/// Calculate TSED similarity between two trees.
/// Returns a value in [0, 1] where 1 = identical trees.
///
/// Normalization: max(1 - dist / max(size1, size2), 0)
///
/// This normalization ensures:
/// - Identical trees → 1.0 (regardless of size)
/// - All labels different, same structure → 0.0
/// - No magic number penalties
pub fn calculate_tsed(
  tree1 : TreeNode,
  tree2 : TreeNode,
  config : TSEDConfig,
) -> Double {
  let t1 = if config.finalize_labels {
    tree1.with_finalized_labels()
  } else {
    tree1
  }
  let t2 = if config.finalize_labels {
    tree2.with_finalized_labels()
  } else {
    tree2
  }
  let size1 = t1.size().to_double()
  let size2 = t2.size().to_double()
  let max_size = if size1 > size2 { size1 } else { size2 }
  if max_size <= 0.0 {
    return 1.0
  }
  let distance = compute_tree_edit_distance(t1, t2, config.cost_config)
  let similarity = 1.0 - distance / max_size
  if similarity < 0.0 {
    0.0
  } else if similarity > 1.0 {
    1.0
  } else {
    similarity
  }
}

///|
/// Calculate TSED distance between two trees.
/// Returns 1 - similarity, a value in [0, 1] where 0 = identical trees.
pub fn calculate_tsed_distance(
  tree1 : TreeNode,
  tree2 : TreeNode,
  config : TSEDConfig,
) -> Double {
  1.0 - calculate_tsed(tree1, tree2, config)
}

///|
/// Early pruning: determine if two trees are worth comparing.
/// Uses size ratio to estimate an upper bound on similarity.
/// Returns true if comparison should proceed.
pub fn should_compare_trees(
  tree1 : TreeNode,
  tree2 : TreeNode,
  threshold : Double,
) -> Bool {
  let size1 = tree1.size().to_double()
  let size2 = tree2.size().to_double()
  if size1 <= 0.0 || size2 <= 0.0 {
    return false
  }
  let min_size = if size1 < size2 { size1 } else { size2 }
  let max_size = if size1 > size2 { size1 } else { size2 }
  // Upper bound on similarity with max-based normalization:
  // best case is dist = max_size - min_size (delete surplus nodes only),
  // so upper_bound = 1 - (max_size - min_size) / max_size = min_size / max_size
  let upper_bound = min_size / max_size
  upper_bound >= threshold
}
