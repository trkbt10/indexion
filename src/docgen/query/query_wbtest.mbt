// Tests for query module.

// Helper to create EdgeKind from string

///|
fn edge_kind(s : String) -> @graph.EdgeKind {
  @graph.EdgeKind::from_string(s)
}

///|
test "extract_module_deps: extracts ModuleDependsOn edges" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("via", "./utils")
  attrs.set("dep_kind", "value")
  graph.add_edge(
    edge_kind("module_depends_on"),
    "src/main.ts",
    "src/utils.ts",
    attrs~,
  )
  graph.add_edge(edge_kind("declares"), "src/main.ts", "src/main.ts::foo")
  let deps = extract_module_deps(graph)
  assert_eq(deps.length(), 1)
  assert_eq(deps[0].from, "src/main.ts")
  assert_eq(deps[0].to, "src/utils.ts")
  assert_eq(deps[0].via, Some("./utils"))
  assert_eq(deps[0].dep_kind, Some("value"))
}

///|
test "get_direct_deps: filters by module" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "c.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "d.ts")
  let deps = get_direct_deps(graph, "a.ts")
  assert_eq(deps.length(), 2)
}

///|
test "get_dependents: finds reverse deps" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "shared.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "shared.ts")
  graph.add_edge(edge_kind("module_depends_on"), "c.ts", "other.ts")
  let deps = get_dependents(graph, "shared.ts")
  assert_eq(deps.length(), 2)
}

///|
test "get_transitive_deps: follows dependency chain" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "c.ts")
  graph.add_edge(edge_kind("module_depends_on"), "c.ts", "d.ts")
  let deps = get_transitive_deps(graph, "a.ts")
  assert_eq(deps.length(), 3)
  assert_true(deps.contains("b.ts"))
  assert_true(deps.contains("c.ts"))
  assert_true(deps.contains("d.ts"))
}

///|
test "extract_call_graph: extracts Calls edges" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("file", "main.ts")
  graph.add_edge(edge_kind("calls"), "main::init", "utils::helper", attrs~)
  let calls = extract_call_graph(graph)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].caller, "main::init")
  assert_eq(calls[0].callee, "utils::helper")
  assert_eq(calls[0].file, "main.ts")
}

///|
test "get_callees: finds called functions" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("calls"), "foo", "bar")
  graph.add_edge(edge_kind("calls"), "foo", "baz")
  graph.add_edge(edge_kind("calls"), "other", "qux")
  let callees = get_callees(graph, "foo")
  assert_eq(callees.length(), 2)
}

///|
test "get_callers: finds calling functions" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("calls"), "a", "shared")
  graph.add_edge(edge_kind("calls"), "b", "shared")
  graph.add_edge(edge_kind("calls"), "c", "other")
  let callers = get_callers(graph, "shared")
  assert_eq(callers.length(), 2)
}

///|
test "extract_type_hierarchy: extracts Extends and Implements" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("extends"), "Dog", "Animal")
  graph.add_edge(edge_kind("implements"), "Dog", "Walkable")
  graph.add_edge(edge_kind("declares"), "file", "Dog")
  let rels = extract_type_hierarchy(graph)
  assert_eq(rels.length(), 2)
  let extends_rel = rels.iter().find_first(fn(r) { r.relation == "extends" })
  assert_true(extends_rel is Some(_))
  assert_eq(extends_rel.unwrap().child, "Dog")
  assert_eq(extends_rel.unwrap().parent, "Animal")
}

///|
test "get_parents: finds base types" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("extends"), "Cat", "Animal")
  graph.add_edge(edge_kind("implements"), "Cat", "Meowable")
  let parents = get_parents(graph, "Cat")
  assert_eq(parents.length(), 2)
}

///|
test "get_children: finds derived types" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("extends"), "Dog", "Animal")
  graph.add_edge(edge_kind("extends"), "Cat", "Animal")
  graph.add_edge(edge_kind("extends"), "Bird", "Creature")
  let children = get_children(graph, "Animal")
  assert_eq(children.length(), 2)
}

///|
test "extract_references: extracts References edges" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("ns", "value")
  graph.add_edge(edge_kind("references"), "main.ts:10", "utils::helper", attrs~)
  let refs = extract_references(graph)
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].symbol, "utils::helper")
  assert_eq(refs[0].ref_site, "main.ts:10")
  assert_eq(refs[0].ref_kind, "value")
}

///|
test "extract_declarations: extracts Declares edges with attrs" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("name", "MyClass")
  attrs.set("kind", "Class")
  attrs.set("doc", "A sample class")
  graph.add_edge(edge_kind("declares"), "file.ts", "file.ts::MyClass", attrs~)
  let decls = extract_declarations(graph)
  assert_eq(decls.length(), 1)
  assert_eq(decls[0].id, "file.ts::MyClass")
  assert_eq(decls[0].name, "MyClass")
  assert_eq(decls[0].kind, "Class")
  assert_eq(decls[0].doc, Some("A sample class"))
}

///|
test "count_references: counts refs per symbol" {
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("references"), "a:1", "shared")
  graph.add_edge(edge_kind("references"), "a:2", "shared")
  graph.add_edge(edge_kind("references"), "b:1", "shared")
  graph.add_edge(edge_kind("references"), "c:1", "other")
  let counts = count_references(graph)
  assert_eq(counts.get("shared"), Some(3))
  assert_eq(counts.get("other"), Some(1))
}

///|
test "extract_circular_deps: extracts CircularDependency edges" {
  let graph = @graph.CodeGraph::new()
  // Normal dependencies
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "c.ts")
  // Circular dependency
  graph.add_edge(edge_kind("circular_dependency"), "c.ts", "a.ts")
  let circulars = extract_circular_deps(graph)
  assert_eq(circulars.length(), 1)
  assert_eq(circulars[0].from, "c.ts")
  assert_eq(circulars[0].to, "a.ts")
}

///|
test "has_circular_deps: detects circular deps" {
  let graph_with = @graph.CodeGraph::new()
  graph_with.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph_with.add_edge(edge_kind("circular_dependency"), "b.ts", "a.ts")
  assert_true(has_circular_deps(graph_with))
  let graph_without = @graph.CodeGraph::new()
  graph_without.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph_without.add_edge(edge_kind("module_depends_on"), "b.ts", "c.ts")
  assert_false(has_circular_deps(graph_without))
}

///|
test "get_transitive_deps: handles cycles safely" {
  // Ensure get_transitive_deps doesn't infinite loop on cycles
  let graph = @graph.CodeGraph::new()
  graph.add_edge(edge_kind("module_depends_on"), "a.ts", "b.ts")
  graph.add_edge(edge_kind("module_depends_on"), "b.ts", "c.ts")
  graph.add_edge(edge_kind("module_depends_on"), "c.ts", "a.ts") // cycle!
  // This should complete without hanging
  let deps = get_transitive_deps(graph, "a.ts")
  // All nodes in the cycle should be included
  assert_true(deps.contains("b.ts"))
  assert_true(deps.contains("c.ts"))
}
