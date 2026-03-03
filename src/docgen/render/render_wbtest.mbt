// Tests for render module.

// Helper to create EdgeKind from string
///|
fn edge_kind(s : String) -> @graph.EdgeKind {
  @graph.EdgeKind::from_string(s)
}

///|
test "RenderOptions::default: has sensible defaults" {
  let opts = RenderOptions::default()
  assert_true(opts.include_diagrams)
  assert_true(opts.include_deps)
  assert_eq(opts.max_diagram_nodes, 50)
}

///|
test "DocOutput::to_markdown: combines sections" {
  let output = DocOutput::new(
    "# API\nContent here",
    dependency_diagram=Some("```mermaid\ngraph LR\n```"),
    call_graph=Some("```mermaid\ngraph TD\n```"),
  )
  let md = output.to_markdown()
  assert_true(md.contains("# API"))
  assert_true(md.contains("Module Dependencies"))
  assert_true(md.contains("Call Graph"))
}

///|
test "render_api_reference: groups by kind" {
  let decls = [
    @query.SymbolDecl::new("f::Foo", "Foo", "Class", "f"),
    @query.SymbolDecl::new("f::bar", "bar", "Function", "f"),
    @query.SymbolDecl::new("f::Baz", "Baz", "Class", "f"),
  ]
  let counts : Map[String, Int] = {}
  let md = render_api_reference(decls, counts)
  assert_true(md.contains("## Classes"))
  assert_true(md.contains("## Functions"))
  assert_true(md.contains("### Foo"))
  assert_true(md.contains("### bar"))
}

///|
test "render_api_reference: shows reference counts" {
  let decls = [@query.SymbolDecl::new("f::Foo", "Foo", "Class", "f")]
  let counts : Map[String, Int] = {}
  counts.set("f::Foo", 5)
  let md = render_api_reference(decls, counts)
  assert_true(md.contains("**References:** 5"))
}

///|
test "render_api_reference: empty returns empty" {
  let decls : Array[@query.SymbolDecl] = []
  let counts : Map[String, Int] = {}
  let md = render_api_reference(decls, counts)
  assert_eq(md, "")
}

///|
test "render_cross_references: creates table" {
  let decls = [
    @query.SymbolDecl::new("a", "A", "Class", "f"),
    @query.SymbolDecl::new("b", "B", "Class", "f"),
  ]
  let counts : Map[String, Int] = {}
  counts.set("a", 10)
  counts.set("b", 5)
  let table = render_cross_references(decls, counts)
  assert_true(table.contains("| Symbol | Kind | References |"))
  assert_true(table.contains("| `A` | Class | 10 |"))
  assert_true(table.contains("| `B` | Class | 5 |"))
}

///|
test "render_cross_references: sorts by count descending" {
  let decls = [
    @query.SymbolDecl::new("a", "A", "Class", "f"),
    @query.SymbolDecl::new("b", "B", "Class", "f"),
  ]
  let counts : Map[String, Int] = {}
  counts.set("a", 5)
  counts.set("b", 10)
  let table = render_cross_references(decls, counts)
  // B should come before A
  let pos_b = find_string(table, "| `B`")
  let pos_a = find_string(table, "| `A`")
  assert_true(pos_b < pos_a)
}

///|
test "clean_doc: removes JSDoc markers" {
  let doc = "/** This is a doc comment */"
  let cleaned = clean_doc(doc)
  assert_false(cleaned.contains("/**"))
  assert_false(cleaned.contains("*/"))
  assert_true(cleaned.contains("This is a doc comment"))
}

///|
test "clean_doc: removes MoonBit markers" {
  let doc = "///| This is a doc"
  let cleaned = clean_doc(doc)
  assert_false(cleaned.contains("///|"))
  assert_true(cleaned.contains("This is a doc"))
}

///|
test "render_json: produces valid JSON structure" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("name", "Foo")
  attrs.set("kind", "Class")
  graph.add_edge(edge_kind("declares"), "file.ts", "file.ts::Foo", attrs~)
  let json = render_json(graph)
  assert_true(json.contains("\"modules\""))
  assert_true(json.contains("\"symbols\""))
  assert_true(json.contains("\"dependencies\""))
  assert_true(json.contains("\"calls\""))
  assert_true(json.contains("\"hierarchy\""))
  assert_true(json.contains("\"references\""))
}

///|
test "render_markdown: generates complete output" {
  let graph = @graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("name", "MyClass")
  attrs.set("kind", "Class")
  attrs.set("doc", "A test class")
  graph.add_edge(edge_kind("declares"), "test.ts", "test.ts::MyClass", attrs~)
  graph.add_edge(edge_kind("module_depends_on"), "test.ts", "utils.ts")
  let opts = RenderOptions::default()
  let output = render_markdown(graph, opts)
  assert_true(output.api_reference.contains("MyClass"))
  assert_true(output.dependency_diagram is Some(_))
}

// Helper function

///|
fn find_string(haystack : String, needle : String) -> Int {
  let h_chars = haystack.to_array()
  let n_chars = needle.to_array()
  let h_len = h_chars.length()
  let n_len = n_chars.length()
  for i = 0; i <= h_len - n_len; i = i + 1 {
    let mut match_ = true
    for j = 0; j < n_len; j = j + 1 {
      if h_chars[i + j] != n_chars[j] {
        match_ = false
        break
      }
    }
    if match_ {
      return i
    }
  }
  -1
}
