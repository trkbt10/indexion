// Tests for diagram module.

///|
test "generate_dep_diagram: creates valid mermaid" {
  let deps = [
    @query.ModuleDep::new("src/main.ts", "src/utils.ts"),
    @query.ModuleDep::new("src/main.ts", "src/config.ts"),
  ]
  let diagram = generate_dep_diagram(deps)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph LR"))
  assert_true(diagram.contains("-->"))
  assert_true(diagram.contains("```"))
}

///|
test "generate_dep_diagram: empty deps returns empty string" {
  let deps : Array[@query.ModuleDep] = []
  let diagram = generate_dep_diagram(deps)
  assert_eq(diagram, "")
}

///|
test "generate_dep_diagram: shortens module names" {
  let deps = [
    @query.ModuleDep::new("src/components/button.ts", "src/utils/helpers.ts"),
  ]
  let diagram = generate_dep_diagram(deps)
  assert_true(diagram.contains("button.ts"))
  assert_true(diagram.contains("helpers.ts"))
}

///|
test "generate_call_diagram: creates valid mermaid" {
  let calls = [
    @query.CallInfo::new("main::init", "utils::setup", "main.ts"),
    @query.CallInfo::new("main::init", "utils::run", "main.ts"),
  ]
  let diagram = generate_call_diagram(calls)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph TD"))
  assert_true(diagram.contains("-->"))
}

///|
test "generate_call_diagram: filters by focus" {
  let calls = [
    @query.CallInfo::new("a", "b", "file"),
    @query.CallInfo::new("b", "c", "file"),
    @query.CallInfo::new("x", "y", "file"),
  ]
  let diagram = generate_call_diagram(calls, focus=Some("b"))
  // Should include a->b and b->c but not x->y
  assert_true(diagram.contains("-->"))
}

///|
test "generate_call_diagram: empty calls returns empty string" {
  let calls : Array[@query.CallInfo] = []
  let diagram = generate_call_diagram(calls)
  assert_eq(diagram, "")
}

///|
test "generate_hierarchy_diagram: creates classDiagram" {
  let rels = [
    @query.TypeRelation::new("Dog", "Animal", "extends"),
    @query.TypeRelation::new("Cat", "Animal", "extends"),
    @query.TypeRelation::new("Dog", "Walkable", "implements"),
  ]
  let diagram = generate_hierarchy_diagram(rels)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("classDiagram"))
  assert_true(diagram.contains("<|--")) // extends arrow
  assert_true(diagram.contains("<|..")) // implements arrow
}

///|
test "generate_hierarchy_diagram: empty returns empty string" {
  let rels : Array[@query.TypeRelation] = []
  let diagram = generate_hierarchy_diagram(rels)
  assert_eq(diagram, "")
}

///|
test "shorten_module_name: extracts last segment" {
  assert_eq(shorten_module_name("src/components/Button.tsx"), "Button.tsx")
  assert_eq(shorten_module_name("utils"), "utils")
}

///|
test "shorten_symbol_name: extracts after ::" {
  assert_eq(shorten_symbol_name("file.ts::MyClass"), "MyClass")
  assert_eq(shorten_symbol_name("pkg::module::func"), "func")
  assert_eq(shorten_symbol_name("simple"), "simple")
}

///|
test "escape_mermaid: handles special chars" {
  let escaped = escape_mermaid("Hello[World]")
  assert_false(escaped.contains("["))
  assert_false(escaped.contains("]"))
}

///|
test "sanitize_class_name: keeps alphanumeric and underscore" {
  assert_eq(sanitize_class_name("MyClass_123"), "MyClass_123")
  assert_eq(sanitize_class_name("pkg::Type"), "pkgType")
}

///|
test "generate_folded_diagram: creates valid mermaid" {
  let nodes : Map[String, @fold.FoldedNode] = {}
  nodes.set("main.ts", @fold.FoldedNode::Single("main.ts", 0.9))
  nodes.set("utils.ts", @fold.FoldedNode::Single("utils.ts", 0.8))
  nodes.set(
    "cluster_other",
    @fold.FoldedNode::Cluster("helpers", 5, ["a", "b", "c", "d", "e"]),
  )
  let edges = [
    @fold.FoldedEdge::new("main.ts", "utils.ts", 1),
    @fold.FoldedEdge::new("main.ts", "cluster_other", 3),
  ]
  let folded = @fold.FoldedGraph::new(nodes, edges, 1)
  let diagram = generate_folded_diagram(folded)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph LR"))
  assert_true(diagram.contains("main.ts"))
  assert_true(diagram.contains("utils.ts"))
  assert_true(diagram.contains("5 nodes"))
  assert_true(diagram.contains("-->"))
  assert_true(diagram.contains("stroke-dasharray"))
}

///|
test "generate_folded_diagram: empty graph returns empty" {
  let nodes : Map[String, @fold.FoldedNode] = {}
  let edges : Array[@fold.FoldedEdge] = []
  let folded = @fold.FoldedGraph::new(nodes, edges, 0)
  let diagram = generate_folded_diagram(folded)
  assert_eq(diagram, "")
}

///|
test "generate_folded_diagram: weighted edges show count" {
  let nodes : Map[String, @fold.FoldedNode] = {}
  nodes.set("a", @fold.FoldedNode::Single("a", 1.0))
  nodes.set("b", @fold.FoldedNode::Single("b", 0.5))
  let edges = [@fold.FoldedEdge::new("a", "b", 3)]
  let folded = @fold.FoldedGraph::new(nodes, edges, 0)
  let diagram = generate_folded_diagram(folded)
  // Weight > 1 should show label
  assert_true(diagram.contains("3"))
}
