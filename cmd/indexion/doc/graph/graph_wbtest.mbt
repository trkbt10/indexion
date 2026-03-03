// Tests for graph CLI command.

// --- Argument parsing tests ---

///|
test "parse_graph_args: default config" {
  let config = parse_graph_args([], 0)
  assert_eq(config.graph_type, "all")
  assert_eq(config.output_file, "")
  assert_eq(config.specs_dir, "kgfs")
  assert_eq(config.focus, None)
  assert_eq(config.title, None)
  assert_false(config.no_fence)
  assert_false(config.simplify)
  assert_eq(config.max_nodes, 15)
  assert_false(config.show_help)
}

///|
test "parse_graph_args: type option" {
  let config = parse_graph_args(["--type=deps"], 0)
  assert_eq(config.graph_type, "deps")
}

///|
test "parse_graph_args: output option" {
  let config = parse_graph_args(["--output=out.md"], 0)
  assert_eq(config.output_file, "out.md")
}

///|
test "parse_graph_args: specs option" {
  let config = parse_graph_args(["--specs=my-kgfs"], 0)
  assert_eq(config.specs_dir, "my-kgfs")
}

///|
test "parse_graph_args: focus option" {
  let config = parse_graph_args(["--focus=main"], 0)
  assert_eq(config.focus, Some("main"))
}

///|
test "parse_graph_args: title option" {
  let config = parse_graph_args(["--title=My Graph"], 0)
  assert_eq(config.title, Some("My Graph"))
}

///|
test "parse_graph_args: no-fence flag" {
  let config = parse_graph_args(["--no-fence"], 0)
  assert_true(config.no_fence)
}

///|
test "parse_graph_args: simplify flag" {
  let config = parse_graph_args(["--simplify"], 0)
  assert_true(config.simplify)
}

///|
test "parse_graph_args: max-nodes option" {
  let config = parse_graph_args(["--max-nodes=10"], 0)
  assert_eq(config.max_nodes, 10)
}

///|
test "parse_graph_args: help flag" {
  let config = parse_graph_args(["--help"], 0)
  assert_true(config.show_help)
}

///|
test "parse_graph_args: short help flag" {
  let config = parse_graph_args(["-h"], 0)
  assert_true(config.show_help)
}

///|
test "parse_graph_args: collects input paths" {
  let config = parse_graph_args(["src/", "lib/"], 0)
  assert_eq(config.input_paths.length(), 2)
  assert_eq(config.input_paths[0], "src/")
  assert_eq(config.input_paths[1], "lib/")
}

///|
test "parse_graph_args: mixed options and paths" {
  let config = parse_graph_args(
    ["--type=deps", "src/", "--simplify", "lib/"],
    0,
  )
  assert_eq(config.graph_type, "deps")
  assert_true(config.simplify)
  assert_eq(config.input_paths.length(), 2)
}

///|
test "parse_graph_args: start_idx skips args" {
  let config = parse_graph_args(["doc", "graph", "--type=calls"], 2)
  assert_eq(config.graph_type, "calls")
}

///|
test "parse_graph_args: invalid max-nodes stays default" {
  let config = parse_graph_args(["--max-nodes=0"], 0)
  assert_eq(config.max_nodes, 15) // 0 is not > 0, so default kept
}

// --- parse_int tests ---

///|
test "parse_int: basic numbers" {
  assert_eq(parse_int("42"), 42)
  assert_eq(parse_int("0"), 0)
  assert_eq(parse_int("100"), 100)
}

///|
test "parse_int: stops at non-digit" {
  assert_eq(parse_int("12abc"), 12)
  assert_eq(parse_int("5.5"), 5)
}

///|
test "parse_int: empty returns 0" {
  assert_eq(parse_int(""), 0)
}

///|
test "parse_int: non-digit returns 0" {
  assert_eq(parse_int("abc"), 0)
}

// --- strip_fence tests ---

///|
test "strip_fence: removes mermaid code fences" {
  let input = "```mermaid\ngraph LR\nA --> B\n```"
  let result = strip_fence(input)
  assert_true(result.contains("graph LR"))
  assert_true(result.contains("A --> B"))
  assert_false(result.contains("```mermaid"))
  assert_false(result.contains("```"))
}

///|
test "strip_fence: no fence returns content as-is" {
  let input = "graph LR\nA --> B"
  let result = strip_fence(input)
  assert_eq(result, input)
}

// --- split_lines tests ---

///|
test "split_lines: splits on newline" {
  let lines = split_lines("a\nb\nc")
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
  assert_eq(lines[2], "c")
}

///|
test "split_lines: single line" {
  let lines = split_lines("hello")
  assert_eq(lines.length(), 1)
  assert_eq(lines[0], "hello")
}

///|
test "split_lines: empty string returns empty" {
  let lines = split_lines("")
  assert_eq(lines.length(), 0)
}

///|
test "split_lines: trailing newline creates empty last" {
  let lines = split_lines("a\nb\n")
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
}

// --- join_sections tests ---

///|
test "join_sections: joins with double newlines" {
  let sections = ["section1", "section2"]
  let result = join_sections(sections)
  assert_true(result.contains("section1"))
  assert_true(result.contains("\n\n"))
  assert_true(result.contains("section2"))
}

///|
test "join_sections: empty returns empty" {
  let sections : Array[String] = []
  assert_eq(join_sections(sections), "")
}

///|
test "join_sections: single section no separator" {
  let sections = ["only"]
  assert_eq(join_sections(sections), "only")
}

// --- generate_mermaid tests ---

///|
test "generate_mermaid: deps type with data" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let result = generate_mermaid(graph, "deps", None, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("graph LR"))
  assert_true(result.contains("-->"))
}

///|
test "generate_mermaid: calls type with data" {
  let graph = @code_graph.CodeGraph::new()
  let attrs : Map[String, String] = {}
  attrs.set("file", "main.ts")
  graph.add_edge(
    @code_graph.EdgeKind::from_string("calls"),
    "main::init",
    "utils::setup",
    attrs~,
  )
  let result = generate_mermaid(graph, "calls", None, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("graph TD"))
}

///|
test "generate_mermaid: hierarchy type with data" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("extends"),
    "Dog",
    "Animal",
  )
  let result = generate_mermaid(graph, "hierarchy", None, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("classDiagram"))
  assert_true(result.contains("<|--"))
}

///|
test "generate_mermaid: overview type with data" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let attrs : Map[String, String] = {}
  attrs.set("name", "MyClass")
  attrs.set("kind", "Class")
  graph.add_edge(
    @code_graph.EdgeKind::from_string("declares"),
    "main.ts",
    "main.ts::MyClass",
    attrs~,
  )
  let result = generate_mermaid(graph, "overview", None, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("graph TB"))
}

///|
test "generate_mermaid: all type combines diagrams" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  graph.add_edge(
    @code_graph.EdgeKind::from_string("extends"),
    "Dog",
    "Animal",
  )
  let result = generate_mermaid(graph, "all", None, None, false)
  assert_true(result.contains("graph LR"))
  assert_true(result.contains("classDiagram"))
}

///|
test "generate_mermaid: no-fence strips code fences" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let result = generate_mermaid(graph, "deps", None, None, true)
  assert_false(result.contains("```mermaid"))
  assert_false(result.contains("```"))
  assert_true(result.contains("graph LR"))
}

///|
test "generate_mermaid: custom title" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let result = generate_mermaid(
    graph,
    "deps",
    None,
    Some("My Custom Title"),
    false,
  )
  assert_true(result.contains("My Custom Title"))
}

///|
test "generate_mermaid: empty graph returns empty" {
  let graph = @code_graph.CodeGraph::new()
  let result = generate_mermaid(graph, "deps", None, None, false)
  assert_eq(result, "")
}

// --- generate_simplified_mermaid tests ---

///|
test "generate_simplified_mermaid: deps type with data" {
  let graph = @code_graph.CodeGraph::new()
  let _ = graph.get_or_add_module("main.ts", file=Some("main.ts"))
  let _ = graph.get_or_add_module("utils.ts", file=Some("utils.ts"))
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let result = generate_simplified_mermaid(graph, "deps", 15, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("graph LR"))
}

///|
test "generate_simplified_mermaid: overview fallback works" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("module_depends_on"),
    "main.ts",
    "utils.ts",
  )
  let attrs : Map[String, String] = {}
  attrs.set("name", "Foo")
  attrs.set("kind", "Class")
  graph.add_edge(
    @code_graph.EdgeKind::from_string("declares"),
    "main.ts",
    "main.ts::Foo",
    attrs~,
  )
  let result = generate_simplified_mermaid(graph, "overview", 15, None, false)
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("graph TB"))
}

///|
test "generate_simplified_mermaid: hierarchy fallback works" {
  let graph = @code_graph.CodeGraph::new()
  graph.add_edge(
    @code_graph.EdgeKind::from_string("extends"),
    "Dog",
    "Animal",
  )
  let result = generate_simplified_mermaid(
    graph,
    "hierarchy",
    15,
    None,
    false,
  )
  assert_true(result.contains("```mermaid"))
  assert_true(result.contains("classDiagram"))
}

///|
test "generate_simplified_mermaid: empty graph returns empty" {
  let graph = @code_graph.CodeGraph::new()
  let result = generate_simplified_mermaid(graph, "deps", 15, None, false)
  assert_eq(result, "")
}
