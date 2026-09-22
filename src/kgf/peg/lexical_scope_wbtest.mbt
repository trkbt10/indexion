// End-to-end test for lexical scoping (`scope push` / `scope pop`) in the
// `=== semantics` DSL: spec -> lexer -> peg -> semantics -> graph.
//
// The spec is INLINE on purpose: it exercises the engine feature, not any
// particular language spec under kgfs/.

///|
/// A toy class-based language whose semantics use `scope push` / `scope pop`
/// to attribute members to their *enclosing* class.
///
/// The grammar splits the class header (`class Outer`) from the class body so
/// that the header rule completes — and therefore fires — before any member.
/// Events fire bottom-up, so the order for `class Outer { class Inner { fn a } fn b }` is:
///   ClassHeader(Outer), ClassHeader(Inner), FnDecl(a), ClassDecl(Inner),
///   FnDecl(b), ClassDecl(Outer)
/// which is exactly the push / bind / read / emit / pop interleaving the
/// feature is designed for.
fn nested_class_spec() -> String {
  let text =
    #|kgf 0.5
    #|language: toyclass
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN KW_class /class/
    #|TOKEN KW_fn /fn/
    #|TOKEN Ident /[A-Za-z_][A-Za-z0-9_]*/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|
    #|=== grammar
    #|Module -> ( ClassDecl | FnDecl )*
    #|ClassDecl -> ClassHeader LBRACE ( ClassDecl | FnDecl )* RBRACE
    #|ClassHeader -> KW_class cname:Ident
    #|FnDecl -> KW_fn fname:Ident LPAREN RPAREN
    #|
    #|=== semantics
    #|on ClassHeader when $scope("value", "current_class") {
    #|  let qualified = concat($scope("value", "current_class"), ".", $cname)
    #|  scope push
    #|  bind ns "value" name "current_class" to qualified
    #|} else {
    #|  scope push
    #|  bind ns "value" name "current_class" to $cname
    #|}
    #|on ClassDecl when $scope("value", "current_class") {
    #|  edge declares from $file to $scope("value", "current_class") attrs obj("name", $cname, "kind", "Class")
    #|  scope pop
    #|}
    #|on FnDecl when $scope("value", "current_class") {
    #|  edge declares from $scope("value", "current_class") to concat($scope("value", "current_class"), "::", $fname) attrs obj("name", $fname, "kind", "Method")
    #|} else {
    #|  edge declares from $file to concat($file, "::", $fname) attrs obj("name", $fname, "kind", "Function")
    #|}
    #|
  text
}

///|
/// Returns the `declares` edges of the graph as (from, to) pairs.
fn declares_pairs(graph : @graph.CodeGraph) -> Array[(String, String)] {
  let pairs : Array[(String, String)] = []
  for e in graph.get_edges() {
    if e.kind == @graph.EdgeKind::from_string("declares") {
      pairs.push((e.from, e.to))
    }
  }
  pairs
}

///|
/// True when a (from, to) `declares` edge exists.
fn has_declares(graph : @graph.CodeGraph, from : String, to : String) -> Bool {
  declares_pairs(graph).iter().any(fn(p) { p.0 == from && p.1 == to })
}

///|
test "lexical scope: nested classes attribute members to their own class" {
  let source =
    #|class Outer {
    #|  class Inner {
    #|    fn a()
    #|  }
    #|  fn b()
    #|}
    #|fn c()
  let file = "src/nested.toy"
  let graph = run_full_pipeline(nested_class_spec(), source, file)
  // Both classes are declared by the file, with Inner qualified under Outer.
  assert_true(has_declares(graph, file, "Outer"))
  assert_true(has_declares(graph, file, "Outer.Inner"))
  // `a` is inside Inner's frame.
  assert_true(has_declares(graph, "Outer.Inner", "Outer.Inner::a"))
  // `b` follows Inner's ClassDecl, whose `scope pop` restored Outer — this is
  // the regression the flat scope map could not express: before lexical
  // frames, `b` attached to Inner.
  assert_true(has_declares(graph, "Outer", "Outer::b"))
  assert_true(!has_declares(graph, "Outer.Inner", "Outer.Inner::b"))
  // A top-level fn after the class is attributed to no class at all: Outer's
  // ClassDecl popped back to the root frame, where nothing is bound.
  assert_true(has_declares(graph, file, file + "::c"))
  assert_true(!has_declares(graph, "Outer", "Outer::c"))
  // Exactly the five declares edges above, nothing stray.
  assert_eq(declares_pairs(graph).length(), 5)
}

///|
test "lexical scope: sibling classes do not leak into each other" {
  let source =
    #|class A {
    #|  fn x()
    #|}
    #|class B {
    #|  fn y()
    #|}
  let file = "src/siblings.toy"
  let graph = run_full_pipeline(nested_class_spec(), source, file)
  assert_true(has_declares(graph, "A", "A::x"))
  assert_true(has_declares(graph, "B", "B::y"))
  // B is a top-level class, not nested under A: A's frame was popped first.
  assert_true(has_declares(graph, file, "B"))
  assert_true(!has_declares(graph, file, "A.B"))
  assert_eq(declares_pairs(graph).length(), 4)
}

///|
test "lexical scope: three levels of nesting unwind in order" {
  let source =
    #|class L1 {
    #|  class L2 {
    #|    class L3 {
    #|      fn deep()
    #|    }
    #|    fn mid()
    #|  }
    #|  fn top()
    #|}
  let file = "src/deep.toy"
  let graph = run_full_pipeline(nested_class_spec(), source, file)
  assert_true(has_declares(graph, "L1.L2.L3", "L1.L2.L3::deep"))
  assert_true(has_declares(graph, "L1.L2", "L1.L2::mid"))
  assert_true(has_declares(graph, "L1", "L1::top"))
}
