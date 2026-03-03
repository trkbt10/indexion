// Tests for build pipeline.

// Helper to create EdgeKind from string
///|
fn edge_kind(s : String) -> @graph.EdgeKind {
  @graph.EdgeKind::from_string(s)
}

///|
test "merge_graphs: merges multiple graphs" {
  let g1 = @graph.CodeGraph::new()
  let _ = g1.get_or_add_module("a.ts", file=Some("a.ts"))
  g1.add_edge(edge_kind("declares"), "a.ts", "a.ts::foo")
  let g2 = @graph.CodeGraph::new()
  let _ = g2.get_or_add_module("b.ts", file=Some("b.ts"))
  g2.add_edge(edge_kind("declares"), "b.ts", "b.ts::bar")
  let merged = merge_graphs([g1, g2])
  assert_eq(merged.module_count(), 2)
  assert_eq(merged.edge_count(), 2)
}

///|
test "merge_graphs: empty array returns empty graph" {
  let merged = merge_graphs([])
  assert_eq(merged.module_count(), 0)
}

///|
test "merge_graphs: single graph returns same graph" {
  let g = @graph.CodeGraph::new()
  let _ = g.get_or_add_module("a.ts")
  let merged = merge_graphs([g])
  assert_eq(merged.module_count(), 1)
}

///|
test "group_by_kind: groups symbols correctly" {
  let symbols = [
    @analyze.DocSymbol::new("a", "A", "Class", "f"),
    @analyze.DocSymbol::new("b", "B", "Function", "f"),
    @analyze.DocSymbol::new("c", "C", "Class", "f"),
  ]
  let grouped = group_by_kind(symbols)
  assert_eq(grouped.get("Class").unwrap().length(), 2)
  assert_eq(grouped.get("Function").unwrap().length(), 1)
}

///|
test "group_by_file: groups symbols correctly" {
  let symbols = [
    @analyze.DocSymbol::new("a", "A", "Class", "file1.ts"),
    @analyze.DocSymbol::new("b", "B", "Function", "file2.ts"),
    @analyze.DocSymbol::new("c", "C", "Class", "file1.ts"),
  ]
  let grouped = group_by_file(symbols)
  assert_eq(grouped.get("file1.ts").unwrap().length(), 2)
  assert_eq(grouped.get("file2.ts").unwrap().length(), 1)
}

///|
test "DocConfig::new: creates config with defaults" {
  let files : Array[(String, String)] = []
  let specs : Map[String, @kgf_types.KGFSpec] = {}
  let config = DocConfig::new(files, specs)
  assert_eq(config.get_root_path(), "")
  assert_true(config.get_options().include_diagrams)
}

///|
test "generate_markdown: produces output from AnalysisResult" {
  let result = @analyze.AnalysisResult::new()
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("name", "Foo")
  attrs.set("kind", "Class")
  graph.add_edge(edge_kind("declares"), "test.ts", "test.ts::Foo", attrs~)
  result.set_graph(graph)
  let md = generate_markdown(result)
  assert_true(md.length() > 0)
}
