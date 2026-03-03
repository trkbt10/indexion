///|
/// # indexion doc graph
///
/// Output dependency graphs in Mermaid format using KGF-based analysis.
///
/// ## Overview
///
/// Analyzes source code using KGF specifications and outputs the dependency
/// structure as Mermaid diagrams. Supports module dependencies, call graphs,
/// type hierarchies, and combined overview diagrams.
///
/// ## Usage
///
/// ```bash
/// indexion doc graph [options] [files...]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--type=TYPE` | Graph type: `deps`, `calls`, `hierarchy`, `overview`, `all` | all |
/// | `--output=FILE` | Output file (omit for stdout) | (stdout) |
/// | `--specs=DIR` | KGF specs directory | kgfs |
/// | `--focus=SYMBOL` | Focus on a specific symbol (for call graphs) | (none) |
/// | `--title=TITLE` | Custom diagram title | (auto) |
/// | `--no-fence` | Omit markdown code fence (raw mermaid) | false |
/// | `--simplify` | Fold low-importance nodes using TF-IDF scoring | false |
/// | `--max-nodes=N` | Target max nodes when simplifying | 15 |
///
/// ## Examples
///
/// ```bash
/// # Output all graphs for a directory
/// indexion doc graph src/
///
/// # Module dependencies only
/// indexion doc graph --type=deps src/
///
/// # Call graph focused on a function
/// indexion doc graph --type=calls --focus=main src/
///
/// # Simplified graph (fold low-importance nodes)
/// indexion doc graph --simplify --max-nodes=10 src/
///
/// # Save to file
/// indexion doc graph --output=deps.md src/
/// ```

///|
/// CLI configuration for graph command.
priv struct GraphConfig {
  graph_type : String
  output_file : String
  specs_dir : String
  focus : String?
  title : String?
  no_fence : Bool
  simplify : Bool
  max_nodes : Int
  input_paths : Array[String]
  show_help : Bool
}

///|
fn GraphConfig::default() -> GraphConfig {
  {
    graph_type: "all",
    output_file: "",
    specs_dir: "kgfs",
    focus: None,
    title: None,
    no_fence: false,
    simplify: false,
    max_nodes: 15,
    input_paths: [],
    show_help: false,
  }
}

///|
fn parse_graph_args(args : Array[String], start_idx : Int) -> GraphConfig {
  let mut config = GraphConfig::default()
  let paths : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--no-fence" {
      config = { ..config, no_fence: true }
    } else if arg == "--simplify" {
      config = { ..config, simplify: true }
    } else if arg.has_prefix("--max-nodes=") {
      let value = @common.get_arg_value(arg, 12)
      let n = parse_int(value)
      if n > 0 {
        config = { ..config, max_nodes: n }
      }
    } else if arg.has_prefix("--type=") {
      let value = @common.get_arg_value(arg, 7)
      config = { ..config, graph_type: value }
    } else if arg.has_prefix("--output=") {
      let value = @common.get_arg_value(arg, 9)
      config = { ..config, output_file: value }
    } else if arg.has_prefix("--specs=") {
      let value = @common.get_arg_value(arg, 8)
      config = { ..config, specs_dir: value }
    } else if arg.has_prefix("--focus=") {
      let value = @common.get_arg_value(arg, 8)
      config = { ..config, focus: Some(value) }
    } else if arg.has_prefix("--title=") {
      let value = @common.get_arg_value(arg, 8)
      config = { ..config, title: Some(value) }
    } else if not(arg.has_prefix("-")) {
      paths.push(arg)
    }
  }
  { ..config, input_paths: paths }
}

///|
pub fn show_help() -> Unit {
  println("indexion doc graph - Output dependency graphs in Mermaid format")
  println("")
  println("Usage:")
  println("  indexion doc graph [options] [files...]")
  println("")
  println("Options:")
  println(
    "  --type=deps|calls|hierarchy|overview|all  Graph type (default: all)",
  )
  println("  --output=FILE                Output file (default: stdout)")
  println("  --specs=DIR                  KGF specs directory (default: kgfs)")
  println(
    "  --focus=SYMBOL               Focus on a specific symbol (call graphs)",
  )
  println("  --title=TITLE                Custom diagram title")
  println(
    "  --no-fence                   Omit markdown code fence (raw mermaid)",
  )
  println(
    "  --simplify                   Fold low-importance nodes (TF-IDF + centrality)",
  )
  println(
    "  --max-nodes=N                Target max nodes when simplifying (default: 15)",
  )
  println("  --help                       Show this help message")
  println("")
  println("Graph Types:")
  println("  deps        Module dependency graph (graph LR)")
  println("  calls       Function call graph (graph TD)")
  println("  hierarchy   Type hierarchy diagram (classDiagram)")
  println("  overview    Combined overview with subgraphs (graph TB)")
  println("  all         All of the above (default)")
  println("")
  println("Examples:")
  println("  indexion doc graph src/")
  println("  indexion doc graph --type=deps src/")
  println("  indexion doc graph --type=calls --focus=main src/")
  println("  indexion doc graph --simplify --max-nodes=10 src/")
  println("  indexion doc graph --output=deps.md src/")
}

///|
/// Strip markdown code fences from a mermaid diagram string.
fn strip_fence(diagram : String) -> String {
  let lines = split_lines(diagram)
  let result : Array[String] = []
  for line in lines {
    if line == "```mermaid" || line == "```" {
      continue
    }
    result.push(line)
  }
  @common.join_lines(result)
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
/// Generate mermaid diagrams from a CodeGraph based on the requested type.
fn generate_mermaid(
  graph : @code_graph.CodeGraph,
  graph_type : String,
  focus : String?,
  title : String?,
  no_fence : Bool,
) -> String {
  let sections : Array[String] = []
  if graph_type == "deps" || graph_type == "all" {
    let deps = @query.extract_module_deps(graph)
    let dep_title = match title {
      Some(t) => if graph_type == "deps" { t } else { "Module Dependencies" }
      None => "Module Dependencies"
    }
    let diagram = @diagram.generate_dep_diagram(deps, title=dep_title)
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  if graph_type == "calls" || graph_type == "all" {
    let calls = @query.extract_call_graph(graph)
    let call_title = match title {
      Some(t) => if graph_type == "calls" { t } else { "Call Graph" }
      None => "Call Graph"
    }
    let diagram = @diagram.generate_call_diagram(
      calls,
      title=call_title,
      focus~,
    )
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  if graph_type == "hierarchy" || graph_type == "all" {
    let hierarchy = @query.extract_type_hierarchy(graph)
    let hier_title = match title {
      Some(t) => if graph_type == "hierarchy" { t } else { "Type Hierarchy" }
      None => "Type Hierarchy"
    }
    let diagram = @diagram.generate_hierarchy_diagram(
      hierarchy,
      title=hier_title,
    )
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  if graph_type == "overview" || graph_type == "all" {
    let deps = @query.extract_module_deps(graph)
    let decls = @query.extract_declarations(graph)
    let diagram = @diagram.generate_overview_diagram(deps, decls)
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  join_sections(sections)
}

///|
fn join_sections(sections : Array[String]) -> String {
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

///|
/// Generate a simplified mermaid diagram by folding low-importance nodes.
fn generate_simplified_mermaid(
  graph : @code_graph.CodeGraph,
  graph_type : String,
  max_nodes : Int,
  title : String?,
  no_fence : Bool,
) -> String {
  let fold_config = @fold.FoldConfig::with_max_nodes(max_nodes)
  let sections : Array[String] = []
  if graph_type == "deps" || graph_type == "all" {
    let folded = @fold.fold_graph(graph, fold_config)
    let dep_title = match title {
      Some(t) =>
        if graph_type == "deps" {
          t
        } else {
          "Module Dependencies (simplified)"
        }
      None => "Module Dependencies (simplified)"
    }
    let diagram = @diagram.generate_folded_diagram(folded, title=dep_title)
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  if graph_type == "calls" || graph_type == "all" {
    let folded = @fold.fold_graph_symbols(graph, fold_config)
    let call_title = match title {
      Some(t) =>
        if graph_type == "calls" {
          t
        } else {
          "Call Graph (simplified)"
        }
      None => "Call Graph (simplified)"
    }
    let diagram = @diagram.generate_folded_diagram(folded, title=call_title)
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  // Hierarchy, overview: use standard diagrams (folding doesn't apply well)
  if graph_type == "overview" || graph_type == "all" {
    let deps = @query.extract_module_deps(graph)
    let decls = @query.extract_declarations(graph)
    let diagram = @diagram.generate_overview_diagram(deps, decls)
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  if graph_type == "hierarchy" || graph_type == "all" {
    let hierarchy = @query.extract_type_hierarchy(graph)
    let hier_title = match title {
      Some(t) => if graph_type == "hierarchy" { t } else { "Type Hierarchy" }
      None => "Type Hierarchy"
    }
    let diagram = @diagram.generate_hierarchy_diagram(
      hierarchy,
      title=hier_title,
    )
    if diagram.length() > 0 {
      sections.push(if no_fence { strip_fence(diagram) } else { diagram })
    }
  }
  join_sections(sections)
}

///|
fn parse_int(s : String) -> Int {
  let chars = s.to_array()
  let mut result = 0
  for c in chars {
    let code = c.to_int()
    if code >= 0x30 && code <= 0x39 {
      result = result * 10 + (code - 0x30)
    } else {
      break
    }
  }
  result
}

///|
/// Run the graph command.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_graph_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  // Validate graph type
  let valid_types = ["deps", "calls", "hierarchy", "overview", "all"]
  let mut type_valid = false
  for t in valid_types {
    if config.graph_type == t {
      type_valid = true
      break
    }
  }
  if not(type_valid) {
    println(
      "Error: Unknown graph type: " +
      config.graph_type +
      ". Use deps, calls, hierarchy, overview, or all.",
    )
    return
  }
  // Load KGF specs
  let specs = @common.load_specs(config.specs_dir)
  if specs.length() == 0 {
    println("Warning: No KGF specs loaded from " + config.specs_dir)
  }
  // Collect input files
  let files : Array[(String, String)] = []
  if config.input_paths.length() > 0 {
    for path in config.input_paths {
      @common.collect_files(path, files)
    }
  }
  if files.length() == 0 {
    println(
      "Error: No input files found. Specify files or directories to analyze.",
    )
    return
  }
  // Build graph via KGF pipeline
  let graph = @build.build_graph(files, specs)
  // Generate mermaid output
  let mermaid = if config.simplify {
    generate_simplified_mermaid(
      graph,
      config.graph_type,
      config.max_nodes,
      config.title,
      config.no_fence,
    )
  } else {
    generate_mermaid(
      graph,
      config.graph_type,
      config.focus,
      config.title,
      config.no_fence,
    )
  }
  if mermaid.length() == 0 {
    println(
      "No graph data found. The analyzed files may not contain dependency information.",
    )
    return
  }
  // Output
  if config.output_file.length() > 0 {
    if @common.write_output(config.output_file, mermaid) {
      println("Written to: " + config.output_file)
    }
  } else {
    println(mermaid)
  }
}
