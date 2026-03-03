// Verification tests for Zhang-Shasha algorithm correctness.
// These tests use manually calculated expected values.

// ============================================================
// Test Case 1: Simple rename
// Tree1: A    Tree2: B
// Expected: 1 (rename A to B)
// ============================================================

///|
test "verify: single node rename" {
  let t1 = TreeNode::leaf("A")
  let t2 = TreeNode::leaf("B")
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 2: Single insertion
// Tree1: A       Tree2: A
//                     |
//                     B
// Expected: 1 (insert B)
// ============================================================

///|
test "verify: single insertion" {
  let t1 = TreeNode::leaf("A")
  let t2 = TreeNode::node("A", [TreeNode::leaf("B")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 3: Single deletion
// Tree1: A       Tree2: A
//        |
//        B
// Expected: 1 (delete B)
// ============================================================

///|
test "verify: single deletion" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::leaf("A")
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 4: Two insertions
// Tree1: A       Tree2: A
//                    / \
//                   B   C
// Expected: 2 (insert B, insert C)
// ============================================================

///|
test "verify: two insertions" {
  let t1 = TreeNode::leaf("A")
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="2")
}

// ============================================================
// Test Case 5: Rename child
// Tree1: A       Tree2: A
//        |              |
//        B              C
// Expected: 1 (rename B to C)
// ============================================================

///|
test "verify: rename child" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("C")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 6: Zhang-Shasha paper example (simplified)
// Tree1: A       Tree2: A
//       / \           / \
//      B   C         B   D
// Expected: 1 (rename C to D)
// ============================================================

///|
test "verify: rename one of two children" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("D")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 7: Different structure - delete and insert
// Tree1: A       Tree2: A
//        |            / \
//        B           C   D
// Expected: 3 (delete B, insert C, insert D)
// ============================================================

///|
test "verify: restructure tree" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::node("A", [TreeNode::leaf("C"), TreeNode::leaf("D")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  // Could be: delete B (1) + insert C (1) + insert D (1) = 3
  // Or: rename B->C (1) + insert D (1) = 2
  inspect(dist, content="2")
}

// ============================================================
// Test Case 8: Nested structure
// Tree1: A       Tree2: A
//        |              |
//        B              B
//        |              |
//        C              D
// Expected: 1 (rename C to D)
// ============================================================

///|
test "verify: nested rename" {
  let t1 = TreeNode::node("A", [TreeNode::node("B", [TreeNode::leaf("C")])])
  let t2 = TreeNode::node("A", [TreeNode::node("B", [TreeNode::leaf("D")])])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 9: Add nested node
// Tree1: A       Tree2: A
//        |              |
//        B              B
//                       |
//                       C
// Expected: 1 (insert C)
// ============================================================

///|
test "verify: add nested child" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B")])
  let t2 = TreeNode::node("A", [TreeNode::node("B", [TreeNode::leaf("C")])])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="1")
}

// ============================================================
// Test Case 10: Complete tree replacement
// Tree1: A       Tree2: X
//       / \           / \
//      B   C         Y   Z
// Expected: 3 (rename A->X, rename B->Y, rename C->Z)
// ============================================================

///|
test "verify: complete relabeling" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="3")
}

// ============================================================
// Test Case 11: Identical trees
// ============================================================

///|
test "verify: identical complex tree" {
  let t = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("E")]),
    TreeNode::leaf("C"),
  ])
  let dist = compute_tree_edit_distance(t, t, CostConfig::default())
  inspect(dist, content="0")
}

// ============================================================
// Test Case 12: Debug IndexedTree postorder
// Tree:   A
//        / \
//       B   C
// Postorder: B(1), C(2), A(3)
// l(B)=1, l(C)=2, l(A)=1
// ============================================================

///|
test "verify: IndexedTree postorder numbering" {
  let t = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let indexed = IndexedTree::from_tree(t)
  // Check size
  inspect(indexed.get_size(), content="3")
  // Check postorder labels: B=1, C=2, A=3
  inspect(indexed.get_label(1), content="B")
  inspect(indexed.get_label(2), content="C")
  inspect(indexed.get_label(3), content="A")
  // Check leftmost leaves: l(B)=1, l(C)=2, l(A)=1
  inspect(indexed.get_l(1), content="1")
  inspect(indexed.get_l(2), content="2")
  inspect(indexed.get_l(3), content="1")
}

// ============================================================
// Test Case 13: Keyroots calculation
// Tree:   A
//        / \
//       B   C
// Keyroots should be: C(2), A(3) - because l(B)=l(A)=1
// ============================================================

///|
test "verify: keyroots calculation" {
  let t = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let indexed = IndexedTree::from_tree(t)
  let keyroots = indexed.get_keyroots()
  // Tree: A(B, C). Postorder: B(1), C(2), A(3).
  // l values: l(B)=1, l(C)=2, l(A)=1.
  // Keyroots (rightmost for each distinct l):
  //   l=1: A(3), l=2: C(2).
  // Sorted by postorder ascending: [C(2), A(3)]
  inspect(keyroots.length(), content="2")
  // First keyroot should have smaller postorder number
  assert_true(keyroots[0] <= keyroots[1])
}

// ============================================================
// Test Case 14: More complex tree for validation
// Tree:     A
//          /|\
//         B C D
//        /|
//       E F
// Size = 6
// Postorder: E(1), F(2), B(3), C(4), D(5), A(6)
// l: E=1, F=2, B=1, C=4, D=5, A=1
// ============================================================

///|
test "verify: complex tree indexing" {
  let t = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("E"), TreeNode::leaf("F")]),
    TreeNode::leaf("C"),
    TreeNode::leaf("D"),
  ])
  let indexed = IndexedTree::from_tree(t)
  inspect(indexed.get_size(), content="6")
  // Postorder labels
  inspect(indexed.get_label(1), content="E")
  inspect(indexed.get_label(2), content="F")
  inspect(indexed.get_label(3), content="B")
  inspect(indexed.get_label(4), content="C")
  inspect(indexed.get_label(5), content="D")
  inspect(indexed.get_label(6), content="A")
  // Leftmost leaves
  inspect(indexed.get_l(1), content="1") // E is leaf
  inspect(indexed.get_l(2), content="2") // F is leaf
  inspect(indexed.get_l(3), content="1") // B's leftmost is E
  inspect(indexed.get_l(4), content="4") // C is leaf
  inspect(indexed.get_l(5), content="5") // D is leaf
  inspect(indexed.get_l(6), content="1") // A's leftmost is E
}

// ============================================================
// Test Case 15: Multi-branch tree edit distance (regression)
// Previously, multi-branch trees with renames returned distance=0
// due to keyroots being processed in wrong order (l-ascending
// instead of postorder-ascending), causing tree_dist[x][y] to be
// read before it was computed.
// ============================================================

///|
test "verify: multi-branch rename distance" {
  // Mod(Fn(A,B), Fn(C,D)) vs Mod(Fn(A,X), Fn(Y,D))
  // Expected: 2 renames (B→X, C→Y)
  let t1 = TreeNode::node("Mod", [
    TreeNode::node("Fn", [TreeNode::leaf("A"), TreeNode::leaf("B")]),
    TreeNode::node("Fn", [TreeNode::leaf("C"), TreeNode::leaf("D")]),
  ])
  let t2 = TreeNode::node("Mod", [
    TreeNode::node("Fn", [TreeNode::leaf("A"), TreeNode::leaf("X")]),
    TreeNode::node("Fn", [TreeNode::leaf("Y"), TreeNode::leaf("D")]),
  ])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="2")
}

///|
test "verify: nested multi-branch rename distance" {
  // A(B(D,E), C(F)) vs A(B(D,X), C(Y))
  // Expected: 2 renames (E→X, F→Y)
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("E")]),
    TreeNode::node("C", [TreeNode::leaf("F")]),
  ])
  let t2 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("D"), TreeNode::leaf("X")]),
    TreeNode::node("C", [TreeNode::leaf("Y")]),
  ])
  let dist = compute_tree_edit_distance(t1, t2, CostConfig::default())
  inspect(dist, content="2")
}

///|
test "verify: deep nested rename distance" {
  // Fn(Args(A,B), Body(Ret(Var(x)))) vs Fn(Args(A,B), Body(Ret(Var(z))))
  // Expected: 1 rename (x→z)
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
  inspect(dist, content="1")
}
