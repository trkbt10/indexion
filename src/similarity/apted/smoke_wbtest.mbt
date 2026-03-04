// Smoke tests: diagnose algorithm behavior on various tree structures.

///|
test "smoke: raw distance for 2-child nested tree with renames" {
  // Fn(Args(A,B), Body(Ret(Var(x)))) vs Fn(Args(A,B), Body(Ret(Var(z))))
  // Only x→z should differ: expected distance = 1
  let t1 = TreeNode::node("Fn", [
    TreeNode::node("Args", [TreeNode::leaf("A"), TreeNode::leaf("B")]),
    TreeNode::node("Body", [
      TreeNode::node("Ret", [TreeNode::node("Var", [TreeNode::leaf("x")])]),
    ]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::node("Args", [TreeNode::leaf("A"), TreeNode::leaf("B")]),
    TreeNode::node("Body", [
      TreeNode::node("Ret", [TreeNode::node("Var", [TreeNode::leaf("z")])]),
    ]),
  ])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(
    dist,
    content=(
      #|1
    ),
  )
}

///|
test "smoke: raw distance for multi-branch rename" {
  // Mod(Fn(A,B), Fn(C,D)) vs Mod(Fn(A,X), Fn(Y,D))
  // B→X, C→Y: expected distance = 2
  let t1 = TreeNode::node("Mod", [
    TreeNode::node("Fn", [TreeNode::leaf("A"), TreeNode::leaf("B")]),
    TreeNode::node("Fn", [TreeNode::leaf("C"), TreeNode::leaf("D")]),
  ])
  let t2 = TreeNode::node("Mod", [
    TreeNode::node("Fn", [TreeNode::leaf("A"), TreeNode::leaf("X")]),
    TreeNode::node("Fn", [TreeNode::leaf("Y"), TreeNode::leaf("D")]),
  ])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(
    dist,
    content=(
      #|2
    ),
  )
}

///|
test "smoke: raw distance for deep nested 2-branch rename" {
  // A(B(D,E), C(F)) vs A(B(D,X), C(Y))
  // E→X, F→Y: expected distance = 2
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("E")]),
    TreeNode::node("C", [TreeNode::leaf("F")]),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("X")]),
    TreeNode::node("C", [TreeNode::leaf("Y")]),
  ])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(
    dist,
    content=(
      #|2
    ),
  )
}

///|
test "smoke: identical 2-branch nested trees" {
  let t = TreeNode::node("Mod", [
    TreeNode::node("Fn", [
      TreeNode::node("Args", [TreeNode::leaf("A")]),
      TreeNode::node("Body", [TreeNode::leaf("B")]),
    ]),
    TreeNode::node("Fn", [
      TreeNode::node("Args", [TreeNode::leaf("C")]),
      TreeNode::node("Body", [TreeNode::leaf("D")]),
    ]),
  ])
  let dist = compute_tree_edit_distance(t, t, CostConfig::default())
  inspect(dist, content="0")
}

///|
test "smoke: TSED vs old on moderate trees with known difference" {
  // A(B(D,E), C(F,G)) vs A(B(D,X), C(F,Y))
  // E→X, G→Y: 2 renames out of 7 nodes each
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("E")]),
    TreeNode::node("C", [TreeNode::leaf("F"), TreeNode::leaf("G")]),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("X")]),
    TreeNode::node("C", [TreeNode::leaf("F"), TreeNode::leaf("Y")]),
  ])
  let raw = compute_tree_edit_distance(t1, t2, CostConfig::default())
  let old_sim = tree_similarity(t1, t2, CostConfig::default())
  let tsed_sim = calculate_tsed(t1, t2, {
    cost_config: CostConfig::default(),
    finalize_labels: false,
  })
  let tsed_full = calculate_tsed(t1, t2, TSEDConfig::default())
  // raw=2, old_sim=1-2/14≈0.857, tsed_sim=1-2/7≈0.714, tsed_full(finalized)=1-2/7≈0.714
  inspect(
    (raw, old_sim, tsed_sim, tsed_full),
    content=(
      #|(2, 0.8571428571428572, 0.7142857142857143, 0.7142857142857143)
    ),
  )
}
