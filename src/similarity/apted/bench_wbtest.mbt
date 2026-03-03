// Benchmark comparison: old tree_similarity vs new calculate_tsed.

// Helper: build a chain tree A→B→C→...

///|
fn build_chain(labels : Array[String]) -> TreeNode {
  if labels.length() == 0 {
    return TreeNode::leaf("Empty")
  }
  if labels.length() == 1 {
    return TreeNode::leaf(labels[0])
  }
  let mut current = TreeNode::leaf(labels[labels.length() - 1])
  let mut i = labels.length() - 2
  while i >= 0 {
    current = TreeNode::node(labels[i], [current])
    i = i - 1
  }
  current
}

// Helper: build a flat tree Root(A, B, C, ...)

///|
fn build_flat(root_label : String, child_labels : Array[String]) -> TreeNode {
  let children : Array[TreeNode] = []
  for label in child_labels {
    children.push(TreeNode::leaf(label))
  }
  TreeNode::node(root_label, children)
}

// ============================================================
// 1. Chain vs flat — finalize_labels の効果
// ============================================================

///|
test "bench: chain vs flat - finalize_labels distinguishes structure" {
  let chain = build_chain(["Seq", "Seq", "Seq", "A"])
  let flat = build_flat("Seq", ["A", "B", "C"])
  let old_sim = tree_similarity(chain, flat, CostConfig::default())
  let tsed_no_finalize = calculate_tsed(chain, flat, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  let tsed_with_finalize = calculate_tsed(chain, flat, {
    cost_config: CostConfig::default(),
    finalize_labels: true,
  })
  // finalize_labels should make TSED distinguish chain from flat better
  inspect(
    (old_sim, tsed_no_finalize, tsed_with_finalize),
    content="(0.5, 0, 0)",
  )
}

// ============================================================
// 2. New normalization: identical small trees → 1.0
// ============================================================

///|
test "bench: identical small trees get full score" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B")])
  let old_sim = tree_similarity(t1, t2, CostConfig::default())
  let tsed_sim = calculate_tsed(t1, t2, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  // Both should return 1.0 for identical trees (no penalties)
  assert_eq(old_sim, 1.0)
  assert_eq(tsed_sim, 1.0)
}

// ============================================================
// 3. New normalization: size mismatch gives lower similarity
// ============================================================

///|
test "bench: size mismatch with max-based normalization" {
  let small = TreeNode::leaf("A")
  let large = build_flat("Root", ["A", "B", "C", "D", "E"])
  let old_sim = tree_similarity(small, large, CostConfig::default())
  let tsed_sim = calculate_tsed(small, large, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  // old: 1 - raw_dist/max_dist, tsed: 1 - raw_dist/max(1,6)
  // tsed gives lower score for size mismatch (0.167 vs 0.286)
  inspect(
    (old_sim, tsed_sim),
    content="(0.2857142857142857, 0.16666666666666663)",
  )
}

// ============================================================
// 4. Normalization comparison
// ============================================================

///|
test "bench: normalization comparison for partially similar trees" {
  let t1 = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::leaf("X"),
    TreeNode::leaf("Y"),
  ])
  let old_sim = tree_similarity(t1, t2, CostConfig::default())
  let tsed_sim = calculate_tsed(t1, t2, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  // distance=2 (rename C→X, D→Y), size=4 each
  // old: 1 - 2/8 = 0.75, tsed: 1 - 2/4 = 0.5
  inspect((old_sim, tsed_sim), content="(0.75, 0.5)")
}

// ============================================================
// 5. Early pruning — should_compare_trees (max-based upper bound)
// ============================================================

///|
test "bench: early pruning effectiveness" {
  let small = TreeNode::leaf("A")
  let large_children : Array[TreeNode] = []
  let labels = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
    "Q", "R", "S", "T",
  ]
  for label in labels {
    large_children.push(TreeNode::leaf(label))
  }
  let large = TreeNode::node("Root", large_children)
  // size1=1, size2=21, upper_bound = 1/21 ≈ 0.048
  let should_skip_high = should_compare_trees(small, large, 0.5)
  let should_skip_low = should_compare_trees(small, large, 0.04)
  assert_true(not(should_skip_high)) // Should skip at threshold 0.5
  assert_true(should_skip_low) // Should not skip at threshold 0.04
}

// ============================================================
// 6. PEG-like AST comparison
// ============================================================

///|
test "bench: PEG-style AST comparison" {
  let fn_ab = TreeNode::node("Seq", [
    TreeNode::leaf("Sym:fn"),
    TreeNode::node("Seq", [TreeNode::leaf("Sym:a"), TreeNode::leaf("Sym:b")]),
  ])
  let fn_ac = TreeNode::node("Seq", [
    TreeNode::leaf("Sym:fn"),
    TreeNode::node("Seq", [TreeNode::leaf("Sym:a"), TreeNode::leaf("Sym:c")]),
  ])
  let old_sim = tree_similarity(fn_ab, fn_ac, CostConfig::default())
  let tsed_sim = calculate_tsed(fn_ab, fn_ac, TSEDConfig::default())
  let tsed_no_finalize = calculate_tsed(fn_ab, fn_ac, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  // 5 nodes, 1 rename (Sym:b→Sym:c), dist=1
  // old: 1-1/10=0.9, tsed(finalize): 1-1/5=0.8, tsed(no finalize): 1-1/5=0.8
  inspect((old_sim, tsed_sim, tsed_no_finalize), content="(0.9, 0.8, 0.8)")
}

// ============================================================
// 7. All labels different same size → 0.0
// ============================================================

///|
test "bench: all labels different same structure returns 0.0" {
  let t1 = TreeNode::node("A", [
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
  ])
  let t2 = TreeNode::node("X", [
    TreeNode::leaf("Y"),
    TreeNode::leaf("Z"),
    TreeNode::leaf("W"),
  ])
  let tsed_sim = calculate_tsed(t1, t2, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  // dist=4 (all renames), max(4,4)=4, sim=1-4/4=0.0
  assert_eq(tsed_sim, 0.0)
}
