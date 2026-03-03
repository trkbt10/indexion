// Heuristic comparison: Zhang-Shasha (tree_similarity) vs TSED (calculate_tsed).
// Goal: determine which gives more meaningful similarity values.

///|
fn zs_sim(t1 : TreeNode, t2 : TreeNode) -> Double {
  tree_similarity(t1, t2, CostConfig::default())
}

///|
fn tsed_sim(t1 : TreeNode, t2 : TreeNode) -> Double {
  calculate_tsed(t1, t2, TSEDConfig::default())
}

///|
fn both(t1 : TreeNode, t2 : TreeNode) -> (Double, Double) {
  (zs_sim(t1, t2), tsed_sim(t1, t2))
}

// ============================================================
// Category A: 同一性の基本保証
// ============================================================

///|
test "A1: identical leaf" {
  let t = TreeNode::leaf("X")
  inspect(both(t, t), content="(1, 1)")
}

///|
test "A2: identical 3-node" {
  let t = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  inspect(both(t, t), content="(1, 1)")
}

///|
test "A3: identical deep tree" {
  let t = TreeNode::node("Fn", [
    TreeNode::node("Args", [TreeNode::leaf("x"), TreeNode::leaf("y")]),
    TreeNode::node("Body", [
      TreeNode::node("Return", [TreeNode::leaf("x")]),
    ]),
  ])
  inspect(both(t, t), content="(1, 1)")
}

// ============================================================
// Category B: 全ラベル異なる同構造 → 理想は 0
//   ZS は 1 - dist/(s1+s2) なので 0.5 になってしまう
// ============================================================

///|
test "B1: all-different labels, 3 nodes" {
  let t1 = TreeNode::node("A", [TreeNode::leaf("B"), TreeNode::leaf("C")])
  let t2 = TreeNode::node("X", [TreeNode::leaf("Y"), TreeNode::leaf("Z")])
  // ZS: renames only, dist=3, max_dist=6, 1-3/6=0.5
  // TSED: dist=3, max(3,3)=3, 1-3/3=0.0
  inspect(both(t1, t2), content=(
    #|(0.5, 0)
  ))
}

///|
test "B2: all-different labels, 7 nodes" {
  let t1 = TreeNode::node("A", [
    TreeNode::node("B", [TreeNode::leaf("C"), TreeNode::leaf("D")]),
    TreeNode::node("E", [TreeNode::leaf("F"), TreeNode::leaf("G")]),
  ])
  let t2 = TreeNode::node("P", [
    TreeNode::node("Q", [TreeNode::leaf("R"), TreeNode::leaf("S")]),
    TreeNode::node("T", [TreeNode::leaf("U"), TreeNode::leaf("V")]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.5, 0)
  ))
}

// ============================================================
// Category C: コードリファクタリングの典型パターン
// ============================================================

// C1: 関数のリネーム (1ラベルだけ違う)
///|
test "C1: function rename - Fn(foo,Args(x,y)) vs Fn(bar,Args(x,y))" {
  let t1 = TreeNode::node("Fn", [
    TreeNode::leaf("foo"),
    TreeNode::node("Args", [TreeNode::leaf("x"), TreeNode::leaf("y")]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("bar"),
    TreeNode::node("Args", [TreeNode::leaf("x"), TreeNode::leaf("y")]),
  ])
  // 5 nodes, 1 rename → dist=1
  inspect(both(t1, t2), content=(
    #|(0.9, 0.8)
  ))
}

// C2: 引数追加 (構造変化)
///|
test "C2: argument added - Args(x,y) vs Args(x,y,z)" {
  let t1 = TreeNode::node("Fn", [
    TreeNode::leaf("f"),
    TreeNode::node("Args", [TreeNode::leaf("x"), TreeNode::leaf("y")]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("f"),
    TreeNode::node("Args", [
      TreeNode::leaf("x"),
      TreeNode::leaf("y"),
      TreeNode::leaf("z"),
    ]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.9090909090909091, 0.6666666666666667)
  ))
}

// C3: if→match 変換 (構造大きく変化、子ノードは共通)
///|
test "C3: if to match refactor" {
  let t1 = TreeNode::node("If", [
    TreeNode::node("Cond", [TreeNode::leaf("x")]),
    TreeNode::node("Then", [TreeNode::leaf("a")]),
    TreeNode::node("Else", [TreeNode::leaf("b")]),
  ])
  let t2 = TreeNode::node("Match", [
    TreeNode::node("Expr", [TreeNode::leaf("x")]),
    TreeNode::node("Arm", [TreeNode::leaf("a")]),
    TreeNode::node("Arm", [TreeNode::leaf("b")]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.7142857142857143, 0.4285714285714286)
  ))
}

// C4: 本体だけ変更 (大きな関数の一部)
///|
test "C4: body change in large function" {
  let t1 = TreeNode::node("Fn", [
    TreeNode::leaf("process"),
    TreeNode::node("Args", [
      TreeNode::leaf("a"),
      TreeNode::leaf("b"),
      TreeNode::leaf("c"),
    ]),
    TreeNode::node("Body", [
      TreeNode::node("Let", [TreeNode::leaf("x"), TreeNode::leaf("1")]),
      TreeNode::node("Let", [TreeNode::leaf("y"), TreeNode::leaf("2")]),
      TreeNode::node("Return", [TreeNode::leaf("x")]),
    ]),
  ])
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("process"),
    TreeNode::node("Args", [
      TreeNode::leaf("a"),
      TreeNode::leaf("b"),
      TreeNode::leaf("c"),
    ]),
    TreeNode::node("Body", [
      TreeNode::node("Let", [TreeNode::leaf("x"), TreeNode::leaf("1")]),
      TreeNode::node("Let", [TreeNode::leaf("y"), TreeNode::leaf("2")]),
      TreeNode::node("Return", [TreeNode::leaf("y")]),
    ]),
  ])
  // 14 nodes, 1 rename (x→y in Return)
  inspect(both(t1, t2), content=(
    #|(0.9666666666666667, 0.9333333333333333)
  ))
}

// ============================================================
// Category D: 偽陽性に弱いケース
// ============================================================

// D1: 無関係な小さい木どうし
///|
test "D1: unrelated small trees" {
  let t1 = TreeNode::node("Print", [TreeNode::leaf("hello")])
  let t2 = TreeNode::node("Return", [TreeNode::leaf("42")])
  inspect(both(t1, t2), content=(
    #|(0.5, 0)
  ))
}

// D2: 大小差のある木
///|
test "D2: tiny vs large tree" {
  let t1 = TreeNode::leaf("x")
  let t2 = TreeNode::node("Fn", [
    TreeNode::leaf("process"),
    TreeNode::node("Args", [TreeNode::leaf("a"), TreeNode::leaf("b")]),
    TreeNode::node("Body", [
      TreeNode::node("Return", [TreeNode::leaf("a")]),
    ]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.11111111111111116, 0)
  ))
}

// D3: 同じ葉を持つが構造が全く異なる木
///|
test "D3: same leaves, different structure" {
  // flat: Root(a,b,c,d)
  let t1 = TreeNode::node("Root", [
    TreeNode::leaf("a"),
    TreeNode::leaf("b"),
    TreeNode::leaf("c"),
    TreeNode::leaf("d"),
  ])
  // nested: Root(X(a,b),Y(c,d))
  let t2 = TreeNode::node("Root", [
    TreeNode::node("X", [TreeNode::leaf("a"), TreeNode::leaf("b")]),
    TreeNode::node("Y", [TreeNode::leaf("c"), TreeNode::leaf("d")]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.8333333333333334, 0.5714285714285714)
  ))
}

// ============================================================
// Category E: PEG 文法の比較 (実ユースケース)
// ============================================================

// E1: ほぼ同じ文法ルール
///|
test "E1: PEG similar rules - only terminal differs" {
  // rule1: Seq(Label:name, Star(Choice(Sym:alpha, Sym:digit)))
  let t1 = TreeNode::node("Seq", [
    TreeNode::node("Label:name", [TreeNode::leaf("Sym:alpha")]),
    TreeNode::node("Star", [
      TreeNode::node("Choice", [
        TreeNode::leaf("Sym:alpha"),
        TreeNode::leaf("Sym:digit"),
      ]),
    ]),
  ])
  // rule2: Seq(Label:name, Star(Choice(Sym:alpha, Sym:underscore)))
  let t2 = TreeNode::node("Seq", [
    TreeNode::node("Label:name", [TreeNode::leaf("Sym:alpha")]),
    TreeNode::node("Star", [
      TreeNode::node("Choice", [
        TreeNode::leaf("Sym:alpha"),
        TreeNode::leaf("Sym:underscore"),
      ]),
    ]),
  ])
  // 8 nodes, 1 rename
  inspect(both(t1, t2), content=(
    #|(0.9285714285714286, 0.8571428571428572)
  ))
}

// E2: 構造的に異なる文法ルール
///|
test "E2: PEG structurally different rules" {
  // rule1: Seq(Sym:a, Sym:b)
  let t1 = TreeNode::node("Seq", [
    TreeNode::leaf("Sym:a"),
    TreeNode::leaf("Sym:b"),
  ])
  // rule2: Choice(Sym:a, Sym:b, Sym:c)
  let t2 = TreeNode::node("Choice", [
    TreeNode::leaf("Sym:a"),
    TreeNode::leaf("Sym:b"),
    TreeNode::leaf("Sym:c"),
  ])
  inspect(both(t1, t2), content=(
    #|(0.7142857142857143, 0.5)
  ))
}

// E3: Optional 追加
///|
test "E3: PEG added Optional wrapper" {
  // rule1: Seq(Sym:a, Sym:b)
  let t1 = TreeNode::node("Seq", [
    TreeNode::leaf("Sym:a"),
    TreeNode::leaf("Sym:b"),
  ])
  // rule2: Seq(Sym:a, Optional(Sym:b))
  let t2 = TreeNode::node("Seq", [
    TreeNode::leaf("Sym:a"),
    TreeNode::node("Optional", [TreeNode::leaf("Sym:b")]),
  ])
  inspect(both(t1, t2), content=(
    #|(0.8571428571428572, 0.75)
  ))
}
