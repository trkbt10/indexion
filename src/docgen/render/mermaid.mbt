// Mermaid rendering for dependency graph output.

///|
/// Mermaid output options.
pub struct MermaidOptions {
  /// Which graph types to include.
  include_deps : Bool
  include_calls : Bool
  include_hierarchy : Bool
  include_overview : Bool
  /// Optional focus symbol for call graphs.
  focus : String?
  /// Maximum symbols per module in overview diagrams.
  max_symbols_per_module : Int
}

///|
pub fn MermaidOptions::default() -> MermaidOptions {
  {
    include_deps: true,
    include_calls: true,
    include_hierarchy: true,
    include_overview: true,
    focus: None,
    max_symbols_per_module: 5,
  }
}

///|
/// Create options for a specific graph type.
pub fn MermaidOptions::for_type(graph_type : String) -> MermaidOptions {
  {
    include_deps: graph_type == "deps" || graph_type == "all",
    include_calls: graph_type == "calls" || graph_type == "all",
    include_hierarchy: graph_type == "hierarchy" || graph_type == "all",
    include_overview: graph_type == "overview" || graph_type == "all",
    focus: None,
    max_symbols_per_module: 5,
  }
}

///|
/// Render a CodeGraph as Mermaid diagrams.
/// Returns all requested diagram types concatenated with double newlines.
pub fn render_mermaid(
  graph : @graph.CodeGraph,
  options : MermaidOptions,
) -> String {
  let sections : Array[String] = []
  if options.include_deps {
    let deps = @query.extract_module_deps(graph)
    let diagram = @diagram.generate_dep_diagram(deps)
    if diagram.length() > 0 {
      sections.push(diagram)
    }
  }
  if options.include_calls {
    let calls = @query.extract_call_graph(graph)
    let diagram = @diagram.generate_call_diagram(calls, focus=options.focus)
    if diagram.length() > 0 {
      sections.push(diagram)
    }
  }
  if options.include_hierarchy {
    let hierarchy = @query.extract_type_hierarchy(graph)
    let diagram = @diagram.generate_hierarchy_diagram(hierarchy)
    if diagram.length() > 0 {
      sections.push(diagram)
    }
  }
  if options.include_overview {
    let deps = @query.extract_module_deps(graph)
    let decls = @query.extract_declarations(graph)
    let diagram = @diagram.generate_overview_diagram(
      deps,
      decls,
      max_symbols_per_module=options.max_symbols_per_module,
    )
    if diagram.length() > 0 {
      sections.push(diagram)
    }
  }
  join_mermaid_sections(sections)
}

///|
fn join_mermaid_sections(sections : Array[String]) -> String {
  if sections.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, section in sections {
    if i > 0 {
      result.push('\n')
      result.push('\n')
    }
    for c in section {
      result.push(c)
    }
  }
  String::from_array(result)
}
