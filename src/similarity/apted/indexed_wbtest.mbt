///|
using @test {assert_eq}

// Whitebox tests for indexed tree helpers and size-based upper bounds.

// ============================================================
// from_tree_with_size / index_tree_with_size tests
// ============================================================

///|
test "from_tree_with_size matches from_tree" {
  let d = TreeNode::leaf("D")
  let e = TreeNode::leaf("E")
  let b = TreeNode::node("B", [d, e])
  let c = TreeNode::leaf("C")
  let a = TreeNode::node("A", [b, c])
  let via_from_tree = IndexedTree::from_tree(a)
  let size = a.size()
  let via_with_size = IndexedTree::from_tree_with_size(a, size)
  assert_eq(via_from_tree.size, via_with_size.size)
  assert_eq(via_from_tree.labels, via_with_size.labels)
  assert_eq(via_from_tree.leftmost_leaf, via_with_size.leftmost_leaf)
  assert_eq(via_from_tree.keyroots, via_with_size.keyroots)
  assert_eq(via_from_tree.children_count, via_with_size.children_count)
}

///|
test "index_tree_with_size returns correct size" {
  let tree = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::node("C", [TreeNode::leaf("D")]),
  ])
  let (indexed, size) = index_tree_with_size(tree)
  assert_eq(size, 4)
  assert_eq(indexed.size, 4)
}

// ============================================================
// indexed distance/similarity matches raw tree versions
// ============================================================

///|
test "compute_tree_edit_distance_indexed matches raw" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("D")])
  let config = CostConfig::default()
  let raw = compute_tree_edit_distance(t1, t2, config)
  let (idx1, s1) = index_tree_with_size(t1)
  let (idx2, s2) = index_tree_with_size(t2)
  let indexed = compute_tree_edit_distance_indexed(idx1, s1, idx2, s2, config)
  assert_eq(raw, indexed)
}

///|
test "tree_similarity_indexed matches raw" {
  let t1 = TreeNode::node("Fn", [
    TreeNode::leaf("x"),
    TreeNode::node("Body", [TreeNode::leaf("ret")]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("y"),
    TreeNode::node("Body", [TreeNode::leaf("ret")]),
  ])
  let config = CostConfig::default()
  let raw = tree_similarity(t1, t2, config)
  let (idx1, s1) = index_tree_with_size(t1)
  let (idx2, s2) = index_tree_with_size(t2)
  let indexed = tree_similarity_indexed(idx1, s1, idx2, s2, config)
  assert_eq(raw, indexed)
}

///|
test "normalized_tree_edit_distance_indexed matches raw" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  let config = CostConfig::default()
  let raw = normalized_tree_edit_distance(t1, t2, config)
  let (idx1, s1) = index_tree_with_size(t1)
  let (idx2, s2) = index_tree_with_size(t2)
  let indexed = normalized_tree_edit_distance_indexed(
    idx1, s1, idx2, s2, config,
  )
  assert_eq(raw, indexed)
}

// ============================================================
// indexed TSED matches raw
// ============================================================

///|
test "calculate_tsed_indexed matches raw" {
  let t1 = TreeNode::node("Fn", [
    TreeNode::leaf("a"),
    TreeNode::node("Body", [TreeNode::leaf("x"), TreeNode::leaf("y")]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("b"),
    TreeNode::node("Body", [TreeNode::leaf("x"), TreeNode::leaf("z")]),
  ])
  let config = TSEDConfig::default()
  let raw = calculate_tsed(t1, t2, config)
  let (idx1, s1) = prepare_tsed_tree(t1, config)
  let (idx2, s2) = prepare_tsed_tree(t2, config)
  let indexed = calculate_tsed_indexed(idx1, s1, idx2, s2, config)
  assert_eq(raw, indexed)
}

// ============================================================
// unit_cost_tree_similarity_upper_bound tests
// ============================================================

///|
test "upper bound: identical sizes" {
  // Two trees of equal size → upper bound = 1.0
  let ub = unit_cost_tree_similarity_upper_bound(10, 10)
  assert_eq(ub, 1.0)
}

///|
test "upper bound: one empty" {
  // One empty tree → upper bound = 0.0
  let ub = unit_cost_tree_similarity_upper_bound(5, 0)
  assert_eq(ub, 0.0)
}

///|
test "upper bound: both empty" {
  let ub = unit_cost_tree_similarity_upper_bound(0, 0)
  assert_eq(ub, 1.0)
}

///|
test "upper bound: size 3 vs 7" {
  // 1 - |3-7|/(3+7) = 1 - 4/10 = 0.6
  let ub = unit_cost_tree_similarity_upper_bound(3, 7)
  assert_eq(ub, 0.6)
}

///|
test "upper bound: always >= actual similarity" {
  let t1 = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
  ])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  let config = CostConfig::default()
  let actual = tree_similarity(t1, t2, config)
  let ub = unit_cost_tree_similarity_upper_bound(t1.size(), t2.size())
  assert_true(ub >= actual)
}

// ============================================================
// tsed_similarity_upper_bound tests
// ============================================================

///|
test "tsed upper bound: identical sizes" {
  let ub = tsed_similarity_upper_bound(10, 10)
  assert_eq(ub, 1.0)
}

///|
test "tsed upper bound: both empty" {
  let ub = tsed_similarity_upper_bound(0, 0)
  assert_eq(ub, 1.0)
}

///|
test "tsed upper bound: one empty" {
  let ub = tsed_similarity_upper_bound(5, 0)
  assert_eq(ub, 0.0)
}

///|
test "tsed upper bound: size 3 vs 6" {
  // min/max = 3/6 = 0.5
  let ub = tsed_similarity_upper_bound(3, 6)
  assert_eq(ub, 0.5)
}

///|
test "tsed upper bound: always >= actual tsed" {
  let t1 = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
  ])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  let config = TSEDConfig::default()
  let actual = calculate_tsed(t1, t2, config)
  let ub = tsed_similarity_upper_bound(t1.size(), t2.size())
  assert_true(ub >= actual)
}

// ============================================================
// Trivial cases for indexed functions
// ============================================================

///|
test "indexed distance: both empty" {
  let empty = TreeNode::leaf("")
  let (idx, _) = index_tree_with_size(empty)
  // Size-0 trees can't really exist with TreeNode (min size=1),
  // but test the 0-size code path directly:
  let dist = compute_tree_edit_distance_indexed(
    idx,
    0,
    idx,
    0,
    CostConfig::default(),
  )
  assert_eq(dist, 0.0)
}

///|
test "indexed distance: one empty" {
  let tree = TreeNode::node("A", [TreeNode::leaf("B")])
  let empty = TreeNode::leaf("")
  let (idx_t, _) = index_tree_with_size(tree)
  let (idx_e, _) = index_tree_with_size(empty)
  let config = CostConfig::default()
  let dist = compute_tree_edit_distance_indexed(idx_t, 0, idx_e, 1, config)
  // size1=0 → size2 * insert_cost = 1.0
  assert_eq(dist, 1.0)
}
