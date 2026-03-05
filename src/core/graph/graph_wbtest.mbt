// Tests for the code graph module.

///|
test "CodeGraph::new creates empty graph" {
  let graph = CodeGraph::new()
  assert_eq(graph.module_count(), 0)
  assert_eq(graph.symbol_count(), 0)
  assert_eq(graph.edge_count(), 0)
}

///|
test "get_or_add_module adds new module" {
  let graph = CodeGraph::new()
  let mod1 = graph.get_or_add_module("pkg/foo", file=Some("foo.mbt"))
  assert_eq(mod1.id, "pkg/foo")
  assert_eq(mod1.file, Some("foo.mbt"))
  assert_eq(graph.module_count(), 1)
}

///|
test "get_or_add_module returns existing module" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_module("pkg/foo", file=Some("foo.mbt"))
  let mod2 = graph.get_or_add_module("pkg/foo", file=Some("other.mbt"))
  // Should return existing module, not update file
  assert_eq(mod2.file, Some("foo.mbt"))
  assert_eq(graph.module_count(), 1)
}

///|
test "get_or_add_module updates file when previously None" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_module("pkg/bar")
  let mod2 = graph.get_or_add_module("pkg/bar", file=Some("bar.mbt"))
  assert_eq(mod2.file, Some("bar.mbt"))
  assert_eq(graph.module_count(), 1)
}

///|
test "get_or_add_symbol adds new symbol" {
  let graph = CodeGraph::new()
  let sym = graph.get_or_add_symbol(
    "pkg/foo#MyFunc",
    name="MyFunc",
    kind="function",
    ns="foo",
    module_id="pkg/foo",
  )
  assert_eq(sym.id, "pkg/foo#MyFunc")
  assert_eq(sym.name, "MyFunc")
  assert_eq(sym.kind, "function")
  assert_eq(sym.ns, "foo")
  assert_eq(sym.module_id, "pkg/foo")
  assert_eq(graph.symbol_count(), 1)
}

///|
test "get_or_add_symbol returns existing symbol" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_symbol(
    "pkg/foo#MyFunc",
    name="MyFunc",
    kind="function",
    ns="foo",
    module_id="pkg/foo",
  )
  let sym2 = graph.get_or_add_symbol(
    "pkg/foo#MyFunc",
    name="OtherName",
    kind="type",
    ns="bar",
    module_id="pkg/bar",
  )
  // Should return existing, not update
  assert_eq(sym2.name, "MyFunc")
  assert_eq(sym2.kind, "function")
  assert_eq(graph.symbol_count(), 1)
}

///|
test "add_edge creates edge" {
  let graph = CodeGraph::new()
  graph.add_edge(Declares, "pkg/foo", "pkg/foo#MyFunc")
  assert_eq(graph.edge_count(), 1)
  let edges = graph.get_edges()
  assert_eq(edges[0].kind, Declares)
  assert_eq(edges[0].from, "pkg/foo")
  assert_eq(edges[0].to, "pkg/foo#MyFunc")
}

///|
test "add_edge with attributes" {
  let graph = CodeGraph::new()
  let attrs : Map[String, String] = Map::new()
  attrs.set("line", "42")
  attrs.set("col", "10")
  graph.add_edge(Calls, "pkg/foo#caller", "pkg/bar#callee", attrs~)
  let edges = graph.get_edges()
  assert_eq(edges[0].attrs.get("line"), Some("42"))
  assert_eq(edges[0].attrs.get("col"), Some("10"))
}

///|
test "edges_from filters correctly" {
  let graph = CodeGraph::new()
  graph.add_edge(Declares, "mod_a", "sym_1")
  graph.add_edge(Declares, "mod_a", "sym_2")
  graph.add_edge(Declares, "mod_b", "sym_3")
  let from_a = graph.edges_from("mod_a")
  assert_eq(from_a.length(), 2)
  let from_b = graph.edges_from("mod_b")
  assert_eq(from_b.length(), 1)
}

///|
test "edges_to filters correctly" {
  let graph = CodeGraph::new()
  graph.add_edge(References, "sym_1", "sym_x")
  graph.add_edge(Calls, "sym_2", "sym_x")
  graph.add_edge(Calls, "sym_3", "sym_y")
  let to_x = graph.edges_to("sym_x")
  assert_eq(to_x.length(), 2)
  let to_y = graph.edges_to("sym_y")
  assert_eq(to_y.length(), 1)
}

///|
test "EdgeKind::to_string and from_string roundtrip" {
  let kinds : Array[EdgeKind] = [
    Declares,
    References,
    ModuleDependsOn,
    Imports,
    Calls,
    Extends,
    Implements,
    Custom("my_custom"),
  ]
  for kind in kinds {
    let s = kind.to_string()
    let parsed = EdgeKind::from_string(s)
    assert_eq(parsed, kind)
  }
}

///|
test "get_module returns module or None" {
  let graph = CodeGraph::new()
  assert_eq(graph.get_module("nonexistent"), None)
  let _ = graph.get_or_add_module("pkg/foo")
  assert_true(graph.get_module("pkg/foo").is_some())
}

///|
test "get_symbol returns symbol or None" {
  let graph = CodeGraph::new()
  assert_eq(graph.get_symbol("nonexistent"), None)
  let _ = graph.get_or_add_symbol(
    "pkg/foo#Sym",
    name="Sym",
    kind="type",
    ns="foo",
    module_id="pkg/foo",
  )
  assert_true(graph.get_symbol("pkg/foo#Sym").is_some())
}

///|
test "complete graph building scenario" {
  let graph = CodeGraph::new()

  // Add modules
  let _ = graph.get_or_add_module("app/main", file=Some("main.mbt"))
  let _ = graph.get_or_add_module("lib/utils", file=Some("utils.mbt"))

  // Add symbols
  let _ = graph.get_or_add_symbol(
    "app/main#main",
    name="main",
    kind="function",
    ns="main",
    module_id="app/main",
  )
  let _ = graph.get_or_add_symbol(
    "lib/utils#helper",
    name="helper",
    kind="function",
    ns="utils",
    module_id="lib/utils",
  )

  // Add edges
  graph.add_edge(Declares, "app/main", "app/main#main")
  graph.add_edge(Declares, "lib/utils", "lib/utils#helper")
  graph.add_edge(ModuleDependsOn, "app/main", "lib/utils")
  graph.add_edge(Calls, "app/main#main", "lib/utils#helper")

  // Verify
  assert_eq(graph.module_count(), 2)
  assert_eq(graph.symbol_count(), 2)
  assert_eq(graph.edge_count(), 4)
}

///|
test "to_json_string serializes empty graph" {
  let graph = CodeGraph::new()
  let json_str = graph.to_json_string()
  // Should contain the three top-level keys
  assert_true(json_str.contains("\"modules\""))
  assert_true(json_str.contains("\"symbols\""))
  assert_true(json_str.contains("\"edges\""))
}

///|
test "to_json_string serializes graph with data" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_module("pkg/foo", file=Some("foo.mbt"))
  let _ = graph.get_or_add_symbol(
    "pkg/foo#func",
    name="func",
    kind="function",
    ns="foo",
    module_id="pkg/foo",
  )
  graph.add_edge(Declares, "pkg/foo", "pkg/foo#func")

  let json_str = graph.to_json_string()

  // Check modules
  assert_true(json_str.contains("\"pkg/foo\""))
  assert_true(json_str.contains("\"foo.mbt\""))

  // Check symbols
  assert_true(json_str.contains("\"func\""))
  assert_true(json_str.contains("\"function\""))

  // Check edges
  assert_true(json_str.contains("\"declares\""))
}

///|
test "from_json_string parses valid JSON" {
  let json_str =
    #|{"modules":{"mod1":{"file":"test.mbt"}},"symbols":{"mod1#sym":{"name":"sym","kind":"function","ns":"test","module":"mod1"}},"edges":[{"kind":"declares","from":"mod1","to":"mod1#sym"}]}
  let result = CodeGraph::from_json_string(json_str)
  assert_true(result is Some(_))
  guard result is Some(graph) else { return }

  assert_eq(graph.module_count(), 1)
  assert_eq(graph.symbol_count(), 1)
  assert_eq(graph.edge_count(), 1)

  guard graph.get_module("mod1") is Some(m) else { return }
  assert_eq(m.file, Some("test.mbt"))

  guard graph.get_symbol("mod1#sym") is Some(s) else { return }
  assert_eq(s.name, "sym")
  assert_eq(s.kind, "function")
}

///|
test "from_json_string returns None for invalid JSON" {
  let result = CodeGraph::from_json_string("not valid json")
  assert_true(result is None)
}

///|
test "from_json_string returns None for missing fields" {
  let result = CodeGraph::from_json_string("{\"modules\":{}}")
  assert_true(result is None)
}

///|
test "JSON roundtrip produces equivalent graph" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_module("app/main", file=Some("main.mbt"))
  let _ = graph.get_or_add_module("lib/utils", file=Some("utils.mbt"))
  let _ = graph.get_or_add_symbol(
    "app/main#main",
    name="main",
    kind="function",
    ns="main",
    module_id="app/main",
  )
  let _ = graph.get_or_add_symbol(
    "lib/utils#helper",
    name="helper",
    kind="function",
    ns="utils",
    module_id="lib/utils",
  )
  graph.add_edge(Declares, "app/main", "app/main#main")
  graph.add_edge(Calls, "app/main#main", "lib/utils#helper")

  // Serialize and deserialize
  let json_str = graph.to_json_string()
  let result = CodeGraph::from_json_string(json_str)
  guard result is Some(restored) else { return }

  // Compare counts
  assert_eq(restored.module_count(), graph.module_count())
  assert_eq(restored.symbol_count(), graph.symbol_count())
  assert_eq(restored.edge_count(), graph.edge_count())

  // Check specific data
  guard restored.get_module("app/main") is Some(m) else { return }
  assert_eq(m.file, Some("main.mbt"))

  guard restored.get_symbol("app/main#main") is Some(s) else { return }
  assert_eq(s.name, "main")
  assert_eq(s.kind, "function")
}

///|
test "JSON roundtrip with edge attributes" {
  let graph = CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("line", "42")
  attrs.set("col", "10")
  graph.add_edge(Calls, "src", "dst", attrs~)

  let json_str = graph.to_json_string()
  let result = CodeGraph::from_json_string(json_str)
  guard result is Some(restored) else { return }

  let edges = restored.get_edges()
  assert_eq(edges.length(), 1)
  assert_eq(edges[0].attrs.get("line"), Some("42"))
  assert_eq(edges[0].attrs.get("col"), Some("10"))
}

///|
test "JSON handles module with null file" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_module("mod_no_file")

  let json_str = graph.to_json_string()
  let result = CodeGraph::from_json_string(json_str)
  guard result is Some(restored) else { return }

  guard restored.get_module("mod_no_file") is Some(m) else { return }
  assert_eq(m.file, None)
}

///|
test "JSON roundtrip with symbol doc field" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_symbol(
    "pkg/foo#read_file",
    name="read_file",
    kind="function",
    ns="foo",
    module_id="pkg/foo",
    doc=Some("Read a file from disk and return its contents."),
  )

  let json_str = graph.to_json_string()
  assert_true(json_str.contains("\"doc\""))
  assert_true(json_str.contains("Read a file from disk"))

  let result = CodeGraph::from_json_string(json_str)
  guard result is Some(restored) else { return }

  guard restored.get_symbol("pkg/foo#read_file") is Some(s) else { return }
  assert_eq(s.doc, Some("Read a file from disk and return its contents."))
}

///|
test "JSON handles symbol without doc" {
  let graph = CodeGraph::new()
  let _ = graph.get_or_add_symbol(
    "pkg/foo#bar",
    name="bar",
    kind="function",
    ns="foo",
    module_id="pkg/foo",
  )

  let json_str = graph.to_json_string()
  // doc field should not appear when None
  assert_false(json_str.contains("\"doc\""))

  let result = CodeGraph::from_json_string(json_str)
  guard result is Some(restored) else { return }

  guard restored.get_symbol("pkg/foo#bar") is Some(s) else { return }
  assert_eq(s.doc, None)
}
