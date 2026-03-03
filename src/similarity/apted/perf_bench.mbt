// Performance benchmarks: old TSED vs new TSED speed comparison.

// ============================================================
// Old TSED implementation (inlined for benchmark comparison)
// ============================================================

///|
fn old_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x == 1.0 {
    return 1.0
  }
  let mut guess = x / 2.0
  for i = 0; i < 50; i = i + 1 {
    let next = (guess + x / guess) / 2.0
    let diff = next - guess
    let abs_diff = if diff < 0.0 { -diff } else { diff }
    if abs_diff < 0.0000001 {
      break
    }
    guess = next
  }
  guess
}

///|
fn old_calculate_tsed(
  tree1 : TreeNode,
  tree2 : TreeNode,
  cost_config : CostConfig,
  size_penalty : Bool,
  finalize_labels : Bool,
) -> Double {
  let t1 = if finalize_labels {
    tree1.with_finalized_labels()
  } else {
    tree1
  }
  let t2 = if finalize_labels {
    tree2.with_finalized_labels()
  } else {
    tree2
  }
  let size1 = t1.size().to_double()
  let size2 = t2.size().to_double()
  let total_size = size1 + size2
  if total_size <= 0.0 {
    return 1.0
  }
  let distance = compute_tree_edit_distance(t1, t2, cost_config)
  let mut similarity = 1.0 - 2.0 * distance / total_size
  if similarity < 0.0 {
    similarity = 0.0
  }
  if size_penalty {
    let min_size = if size1 < size2 { size1 } else { size2 }
    let max_size = if size1 > size2 { size1 } else { size2 }
    if min_size < 10.0 {
      similarity = similarity * 0.7
    }
    if max_size > 50.0 {
      let distance_ratio = distance / total_size
      similarity = similarity * (1.0 - distance_ratio * 0.3)
    }
    if max_size > 0.0 {
      let size_ratio = min_size / max_size
      if size_ratio < 0.5 {
        similarity = similarity * old_sqrt(size_ratio)
      }
    }
  }
  if similarity < 0.0 {
    0.0
  } else if similarity > 1.0 {
    1.0
  } else {
    similarity
  }
}

// ============================================================
// Helpers
// ============================================================

///|
fn build_balanced(label : String, depth : Int) -> TreeNode {
  if depth <= 0 {
    return TreeNode::leaf(label)
  }
  TreeNode::node(label, [
    build_balanced(label + "L", depth - 1),
    build_balanced(label + "R", depth - 1),
  ])
}

///|
fn build_wide(root : String, n : Int) -> TreeNode {
  let children : Array[TreeNode] = []
  for i in 0..<n {
    children.push(TreeNode::leaf(root + i.to_string()))
  }
  TreeNode::node(root, children)
}

// ============================================================
// Small trees (3 nodes)
// ============================================================

///|
test "small 3-node" (b : @bench.T) {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("D")])
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t1, t2, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t1, t2, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t1,
          t2,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}

// ============================================================
// Medium trees (7 nodes)
// ============================================================

///|
test "medium 7-node" (b : @bench.T) {
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("E")]),
    TreeNode::node("C", [TreeNode::leaf("F"), TreeNode::leaf("G")]),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("X")]),
    TreeNode::node("C", [TreeNode::leaf("F"), TreeNode::leaf("Y")]),
  ])
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t1, t2, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t1, t2, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t1,
          t2,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}

// ============================================================
// Large balanced trees (depth=4, 31 nodes)
// ============================================================

///|
test "large 31-node balanced" (b : @bench.T) {
  let t1 = build_balanced("N", 4)
  let t2 = build_balanced("M", 4)
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t1, t2, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t1, t2, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t1,
          t2,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}

// ============================================================
// Wide tree (1 root + 20 children = 21 nodes)
// ============================================================

///|
test "wide 21-node" (b : @bench.T) {
  let t1 = build_wide("A", 20)
  let t2 = build_wide("B", 20)
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t1, t2, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t1, t2, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t1,
          t2,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}

// ============================================================
// Identical trees (15 nodes)
// ============================================================

///|
test "identical 15-node" (b : @bench.T) {
  let t = build_balanced("N", 3)
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t, t, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t, t, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t,
          t,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}

// ============================================================
// Large identical (depth=5, 63 nodes) — penalty分岐の影響を見る
// ============================================================

///|
test "large identical 63-node" (b : @bench.T) {
  let t = build_balanced("N", 5)
  let cc = CostConfig::default()
  b.bench(
    name="old_tsed",
    fn() { b.keep(old_calculate_tsed(t, t, cc, true, true)) },
  )
  b.bench(
    name="new_tsed",
    fn() { b.keep(calculate_tsed(t, t, TSEDConfig::default())) },
  )
  b.bench(
    name="new_tsed_no_fin",
    fn() {
      b.keep(
        calculate_tsed(
          t,
          t,
          { cost_config: cc, finalize_labels: false },
        ),
      )
    },
  )
}
