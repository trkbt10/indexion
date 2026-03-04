// Whitebox tests for TSED (Tree Structure Edit Distance).

// ============================================================
// with_finalized_labels tests
// ============================================================

///|
test "with_finalized_labels: leaf node unchanged" {
  let leaf = TreeNode::leaf("A")
  let result = leaf.with_finalized_labels()
  assert_eq(result.get_label(), "A")
  assert_true(result.is_leaf())
}

///|
test "with_finalized_labels: node gets child count appended" {
  let node = TreeNode::node("Seq", [
    TreeNode::leaf("A"),
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
  ])
  let result = node.with_finalized_labels()
  assert_eq(result.get_label(), "Seq_3")
  assert_eq(result.get_children().length(), 3)
}

///|
test "with_finalized_labels: nested tree" {
  let inner = TreeNode::node("Seq", [TreeNode::leaf("X"), TreeNode::leaf("Y")])
  let outer = TreeNode::node("Choice", [inner, TreeNode::leaf("Z")])
  let result = outer.with_finalized_labels()
  assert_eq(result.get_label(), "Choice_2")
  assert_eq(result.get_children()[0].get_label(), "Seq_2")
  assert_eq(result.get_children()[1].get_label(), "Z")
}

///|
test "with_finalized_labels: original tree not modified" {
  let node = TreeNode::node("Seq", [TreeNode::leaf("A"), TreeNode::leaf("B")])
  let _ = node.with_finalized_labels()
  assert_eq(node.get_label(), "Seq")
}

// ============================================================
// TSEDConfig::default tests
// ============================================================

///|
test "TSEDConfig::default fields" {
  let config = TSEDConfig::default()
  assert_eq(config.cost_config, CostConfig::default())
  assert_eq(config.finalize_labels, true)
}

// ============================================================
// calculate_tsed: identical trees → 1.0
// ============================================================

///|
test "calculate_tsed: identical small tree returns 1.0" {
  let tree = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let sim = calculate_tsed(tree, tree, config)
  assert_eq(sim, 1.0)
}

///|
test "calculate_tsed: identical large tree returns 1.0" {
  // 7-node tree: Root(A(X,Y), B(P,Q))
  let tree = TreeNode::node("Root", [
    TreeNode::node("A", [TreeNode::leaf("X"), TreeNode::leaf("Y")]),
    TreeNode::node("B", [TreeNode::leaf("P"), TreeNode::leaf("Q")]),
  ])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  assert_eq(calculate_tsed(tree, tree, config), 1.0)
}

// ============================================================
// calculate_tsed: all labels different, same structure → 0.0
// ============================================================

///|
test "calculate_tsed: all labels different same size returns 0.0" {
  // Same structure, all labels different
  // dist = 3 (rename all 3 nodes), max(3,3) = 3
  // sim = 1 - 3/3 = 0.0
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  assert_eq(calculate_tsed(t1, t2, config), 0.0)
}

///|
test "calculate_tsed: single different leaves returns 0.0" {
  let t1 = TreeNode::leaf("A")
  let t2 = TreeNode::leaf("B")
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  // dist=1, max(1,1)=1, sim=1-1/1=0.0
  assert_eq(calculate_tsed(t1, t2, config), 0.0)
}

// ============================================================
// calculate_tsed: partial difference
// ============================================================

///|
test "calculate_tsed: 1 of 7 nodes different" {
  // A(B(X,Y), C(P,Q)) vs A(B(X,Y), C(P,Z))
  // 7 nodes, 1 rename (Q→Z), dist=1
  // sim = 1 - 1/7 ≈ 0.857
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("X"), TreeNode::leaf("Y")]),
    TreeNode::node("C", [TreeNode::leaf("P"), TreeNode::leaf("Q")]),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("X"), TreeNode::leaf("Y")]),
    TreeNode::node("C", [TreeNode::leaf("P"), TreeNode::leaf("Z")]),
  ])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let sim = calculate_tsed(t1, t2, config)
  // 1 - 1/7 ≈ 0.8571
  assert_true(sim > 0.85)
  assert_true(sim < 0.86)
}

///|
test "calculate_tsed: 1 of 3 nodes different" {
  // A(B,C) vs A(B,D)  — 3 nodes, dist=1
  // sim = 1 - 1/3 ≈ 0.6667
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("D")])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let sim = calculate_tsed(t1, t2, config)
  assert_true(sim > 0.66)
  assert_true(sim < 0.67)
}

// ============================================================
// calculate_tsed: size mismatch
// ============================================================

///|
test "calculate_tsed: size mismatch 1 vs 6" {
  // t1: single leaf "A" (size=1)
  // t2: X(A,B,C,D,E) (size=6)
  // dist = 5 (delete X,B,C,D,E or insert them), max(1,6)=6
  // sim = 1 - 5/6 ≈ 0.167
  let t1 = TreeNode::leaf("A")
  let t2 = TreeNode::node("X", [
    TreeNode::leaf("A"),
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
    TreeNode::leaf("E"),
  ])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let sim = calculate_tsed(t1, t2, config)
  assert_true(sim > 0.16)
  assert_true(sim < 0.17)
}

// ============================================================
// finalize_labels effect tests
// ============================================================

///|
test "finalize_labels: distinguishes trees with different child counts" {
  // Same labels but different number of children
  let t1 = TreeNode::node("Seq", [TreeNode::leaf("A"), TreeNode::leaf("B")])
  let t2 = TreeNode::node("Seq", [
    TreeNode::leaf("A"),
    TreeNode::leaf("B"),
    TreeNode::leaf("C"),
  ])
  let no_finalize : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let with_finalize : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: true,
  }
  let sim_no = calculate_tsed(t1, t2, no_finalize)
  let sim_with = calculate_tsed(t1, t2, with_finalize)
  // With finalize_labels, "Seq_2" vs "Seq_3" creates extra rename cost
  assert_true(sim_with < sim_no)
}

// ============================================================
// should_compare_trees tests
// ============================================================

///|
test "should_compare_trees: same size trees allowed" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  // upper_bound = min(3,3)/max(3,3) = 1.0 >= 0.5
  assert_true(should_compare_trees(t1, t2, 0.5))
}

///|
test "should_compare_trees: very different sizes rejected" {
  let t1 = TreeNode::leaf("A")
  let children : Array[TreeNode] = []
  let labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
  for label in labels {
    children.push(TreeNode::leaf(label))
  }
  let t2 = TreeNode::node("X", children)
  // size1=1, size2=11, upper_bound = 1/11 ≈ 0.091
  assert_true(not(should_compare_trees(t1, t2, 0.5)))
}

///|
test "should_compare_trees: low threshold allows comparison" {
  let t1 = TreeNode::leaf("A")
  let children : Array[TreeNode] = []
  let labels = ["A", "B", "C", "D", "E"]
  for label in labels {
    children.push(TreeNode::leaf(label))
  }
  let t2 = TreeNode::node("X", children)
  // size1=1, size2=6, upper_bound = 1/6 ≈ 0.167
  assert_true(should_compare_trees(t1, t2, 0.1))
}

// ============================================================
// calculate_tsed_distance: complement of similarity
// ============================================================

///|
test "calculate_tsed_distance: similarity + distance = 1.0" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("D")])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  let sim = calculate_tsed(t1, t2, config)
  let dist = calculate_tsed_distance(t1, t2, config)
  let sum = sim + dist
  let diff = sum - 1.0
  let abs_diff = if diff < 0.0 { -diff } else { diff }
  assert_true(abs_diff < 0.0001)
}

///|
test "calculate_tsed_distance: identical trees → 0.0" {
  let tree = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let config : TSEDConfig = {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  }
  assert_eq(calculate_tsed_distance(tree, tree, config), 0.0)
}
