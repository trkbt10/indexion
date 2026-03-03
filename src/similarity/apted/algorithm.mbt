// Zhang-Shasha algorithm for tree edit distance computation.
// Reference: "Simple Fast Algorithms for the Editing Distance between Trees and Related Problems"
// by K. Zhang and D. Shasha (1989)
//
// Time complexity: O(n^2 * m^2) where n, m are tree sizes
// Space complexity: O(n * m)

///|
/// Compute tree edit distance between two trees using Zhang-Shasha algorithm.
/// Returns the minimum cost to transform tree1 into tree2.
pub fn compute_tree_edit_distance(
  tree1 : TreeNode,
  tree2 : TreeNode,
  config : CostConfig,
) -> Double {
  // Handle trivial cases
  let size1 = tree1.size()
  let size2 = tree2.size()
  if size1 == 0 && size2 == 0 {
    return 0.0
  }
  if size1 == 0 {
    return size2.to_double() * config.insert_cost
  }
  if size2 == 0 {
    return size1.to_double() * config.delete_cost
  }
  // Index both trees
  let t1 = IndexedTree::from_tree(tree1)
  let t2 = IndexedTree::from_tree(tree2)
  // Run Zhang-Shasha algorithm
  zhang_shasha(t1, t2, config)
}

///|
/// Zhang-Shasha algorithm implementation.
fn zhang_shasha(
  t1 : IndexedTree,
  t2 : IndexedTree,
  config : CostConfig,
) -> Double {
  let n1 = t1.get_size()
  let n2 = t2.get_size()
  // tree_dist[i][j] = distance between subtree rooted at postorder i in t1
  //                   and subtree rooted at postorder j in t2
  // Using 0-indexed arrays but algorithm uses 1-indexed postorder numbers
  // So we allocate n+1 size and use indices 1..n
  let tree_dist : Array[Array[Double]] = []
  for i = 0; i <= n1; i = i + 1 {
    tree_dist.push(Array::make(n2 + 1, 0.0))
  }
  // forest_dist is reused for each keyroot pair
  // forest_dist[i][j] = distance between forests
  let forest_dist : Array[Array[Double]] = []
  for i = 0; i <= n1; i = i + 1 {
    forest_dist.push(Array::make(n2 + 1, 0.0))
  }
  // Process each pair of keyroots
  let keyroots1 = t1.get_keyroots()
  let keyroots2 = t2.get_keyroots()
  for ki = 0; ki < keyroots1.length(); ki = ki + 1 {
    let i = keyroots1[ki]
    for kj = 0; kj < keyroots2.length(); kj = kj + 1 {
      let j = keyroots2[kj]
      compute_forest_dist(t1, t2, i, j, tree_dist, forest_dist, config)
    }
  }
  // The answer is the distance between the full trees (at root postorder numbers)
  tree_dist[n1][n2]
}

///|
/// Compute forest distances for a pair of keyroots.
/// This fills in tree_dist entries for all nodes in the subtrees rooted at i and j.
fn compute_forest_dist(
  t1 : IndexedTree,
  t2 : IndexedTree,
  i : Int,
  j : Int,
  tree_dist : Array[Array[Double]],
  forest_dist : Array[Array[Double]],
  config : CostConfig,
) -> Unit {
  let l1 = t1.get_l(i) // leftmost leaf of subtree rooted at i
  let l2 = t2.get_l(j) // leftmost leaf of subtree rooted at j
  // Initialize base case: empty forest to empty forest
  forest_dist[l1 - 1][l2 - 1] = 0.0
  // Initialize first column: deleting nodes from t1
  // forest_dist[x][l2-1] = cost to transform forest t1[l1..x] to empty
  for x = l1; x <= i; x = x + 1 {
    forest_dist[x][l2 - 1] = forest_dist[x - 1][l2 - 1] + config.delete_cost
  }
  // Initialize first row: inserting nodes into t2
  // forest_dist[l1-1][y] = cost to transform empty to forest t2[l2..y]
  for y = l2; y <= j; y = y + 1 {
    forest_dist[l1 - 1][y] = forest_dist[l1 - 1][y - 1] + config.insert_cost
  }
  // Fill the DP table
  for x = l1; x <= i; x = x + 1 {
    for y = l2; y <= j; y = y + 1 {
      let lx = t1.get_l(x) // leftmost leaf of subtree rooted at x
      let ly = t2.get_l(y) // leftmost leaf of subtree rooted at y
      // Cost options
      let delete_cost = forest_dist[x - 1][y] + config.delete_cost
      let insert_cost = forest_dist[x][y - 1] + config.insert_cost
      // Rename/match cost depends on whether x and y have the same leftmost leaf
      // as i and j respectively
      let rename_cost = if lx == l1 && ly == l2 {
        // x and y are the roots of their respective subtrees within this keyroot pair
        // So we're comparing full subtrees, not forests
        let label_cost = config.label_cost(t1.get_label(x), t2.get_label(y))
        forest_dist[x - 1][y - 1] + label_cost
      } else {
        // We're comparing forests, need to use previously computed tree distances.
        // tree_dist[x][y] already includes the full subtree transformation cost.
        forest_dist[lx - 1][ly - 1] + tree_dist[x][y]
      }
      // Take minimum
      let min_del_ins = if delete_cost < insert_cost {
        delete_cost
      } else {
        insert_cost
      }
      forest_dist[x][y] = if min_del_ins < rename_cost {
        min_del_ins
      } else {
        rename_cost
      }
      // If both x and y have the same leftmost leaf as their keyroots,
      // store the result in tree_dist
      if lx == l1 && ly == l2 {
        tree_dist[x][y] = forest_dist[x][y]
      }
    }
  }
}

///|
/// Compute normalized tree edit distance.
/// Returns a value in [0, 1] where 0 = identical trees.
pub fn normalized_tree_edit_distance(
  tree1 : TreeNode,
  tree2 : TreeNode,
  config : CostConfig,
) -> Double {
  let raw_dist = compute_tree_edit_distance(tree1, tree2, config)
  let size1 = tree1.size()
  let size2 = tree2.size()
  // Maximum possible distance: delete all from tree1 + insert all to tree2
  let max_dist = size1.to_double() * config.delete_cost +
    size2.to_double() * config.insert_cost
  if max_dist <= 0.0 {
    return 0.0
  }
  let normalized = raw_dist / max_dist
  // Clamp to [0, 1]
  if normalized < 0.0 {
    0.0
  } else if normalized > 1.0 {
    1.0
  } else {
    normalized
  }
}

///|
/// Compute tree similarity (1 - normalized distance).
/// Returns a value in [0, 1] where 1 = identical trees.
pub fn tree_similarity(
  tree1 : TreeNode,
  tree2 : TreeNode,
  config : CostConfig,
) -> Double {
  1.0 - normalized_tree_edit_distance(tree1, tree2, config)
}
