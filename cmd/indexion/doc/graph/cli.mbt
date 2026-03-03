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
/// # Save to file
/// indexion doc graph --output=deps.md src/
/// ```

///|
/// CLI configuration for graph command.
struct GraphConfig {
  graph_type : String
  output_file : String
  specs_dir : String
  focus : String?
  title : String?
  no_fence : Bool
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
    input_paths: [],
    show_help: false,
  }
}

///|
fn get_arg_value(arg : String, start : Int) -> String {
  let chars = arg.to_array()
  if start >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
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
    } else if arg.has_prefix("--type=") {
      let value = get_arg_value(arg, 7)
      config = { ..config, graph_type: value }
    } else if arg.has_prefix("--output=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, output_file: value }
    } else if arg.has_prefix("--specs=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, specs_dir: value }
    } else if arg.has_prefix("--focus=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, focus: Some(value) }
    } else if arg.has_prefix("--title=") {
      let value = get_arg_value(arg, 8)
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
  println(
    "  --specs=DIR                  KGF specs directory (default: kgfs)",
  )
  println("  --focus=SYMBOL               Focus on a specific symbol (call graphs)")
  println("  --title=TITLE                Custom diagram title")
  println("  --no-fence                   Omit markdown code fence (raw mermaid)")
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
  println("  indexion doc graph --output=deps.md src/")
}

///|
/// Load all KGF specs from a directory.
fn load_specs(specs_dir : String) -> Map[String, @kgf_types.KGFSpec] {
  let specs : Map[String, @kgf_types.KGFSpec] = {}
  try {
    if not(@fs.is_dir(specs_dir)) {
      println("Warning: Specs directory not found: " + specs_dir)
      return specs
    }
    let entries = @fs.read_dir(specs_dir)
    for entry in entries {
      if entry.has_suffix(".kgf") {
        let path = specs_dir + "/" + entry
        let content = @fs.read_file_to_string(path)
        match @parser.parse_kgf(content) {
          Some(spec) => {
            let lang = spec.get_language()
            specs.set(lang, spec)
          }
          None => println("Warning: Failed to parse spec: " + path)
        }
      }
    }
  } catch {
    e => println("Warning: Could not load specs: " + e.to_string())
  }
  specs
}

///|
/// Collect files from a path (file or directory).
fn collect_files(path : String, files : Array[(String, String)]) -> Unit {
  let clean_path = trim_trailing_slash(path)
  try {
    if @fs.is_dir(clean_path) {
      let entries = @fs.read_dir(clean_path)
      for entry in entries {
        let full_path = clean_path + "/" + entry
        collect_files(full_path, files)
      }
    } else if @fs.is_file(clean_path) {
      if is_supported_file(clean_path) {
        let content = @fs.read_file_to_string(clean_path)
        files.push((clean_path, content))
      }
    }
  } catch {
    e =>
      println(
        "Warning: Could not read " + clean_path + ": " + e.to_string(),
      )
  }
}

///|
fn trim_trailing_slash(path : String) -> String {
  if path.length() > 0 && path.has_suffix("/") {
    let chars = path.to_array()
    let result : Array[Char] = []
    for i = 0; i < chars.length() - 1; i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    path
  }
}

///|
fn is_supported_file(path : String) -> Bool {
  let extensions = [
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".mbt", ".py", ".go", ".rs", ".sql",
    ".html", ".css", ".md",
  ]
  for ext in extensions {
    if path.has_suffix(ext) {
      return true
    }
  }
  false
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
  join_lines(result)
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
fn join_lines(lines : Array[String]) -> String {
  if lines.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, line in lines {
    if i > 0 {
      result.push('\n')
    }
    for c in line {
      result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// Build a CodeGraph from files using KGF analysis.
fn build_graph(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
) -> @graph.CodeGraph {
  @build.build_graph(files, specs)
}

///|
/// Generate mermaid diagrams from a CodeGraph based on the requested type.
fn generate_mermaid(
  graph : @graph.CodeGraph,
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
      sections.push(
        if no_fence { strip_fence(diagram) } else { diagram },
      )
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
      focus=focus,
    )
    if diagram.length() > 0 {
      sections.push(
        if no_fence { strip_fence(diagram) } else { diagram },
      )
    }
  }
  if graph_type == "hierarchy" || graph_type == "all" {
    let hierarchy = @query.extract_type_hierarchy(graph)
    let hier_title = match title {
      Some(t) =>
        if graph_type == "hierarchy" { t } else { "Type Hierarchy" }
      None => "Type Hierarchy"
    }
    let diagram = @diagram.generate_hierarchy_diagram(
      hierarchy,
      title=hier_title,
    )
    if diagram.length() > 0 {
      sections.push(
        if no_fence { strip_fence(diagram) } else { diagram },
      )
    }
  }
  if graph_type == "overview" || graph_type == "all" {
    let deps = @query.extract_module_deps(graph)
    let decls = @query.extract_declarations(graph)
    let diagram = @diagram.generate_overview_diagram(deps, decls)
    if diagram.length() > 0 {
      sections.push(
        if no_fence { strip_fence(diagram) } else { diagram },
      )
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
/// Write string to file.
fn write_output(path : String, content : String) -> Bool {
  try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    e => {
      println("Write error: " + e.to_string())
      false
    }
  }
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
  let specs = load_specs(config.specs_dir)
  if specs.length() == 0 {
    println("Warning: No KGF specs loaded from " + config.specs_dir)
  }
  // Collect input files
  let files : Array[(String, String)] = []
  if config.input_paths.length() > 0 {
    for path in config.input_paths {
      collect_files(path, files)
    }
  }
  if files.length() == 0 {
    println("Error: No input files found. Specify files or directories to analyze.")
    return
  }
  // Build graph via KGF pipeline
  let graph = build_graph(files, specs)
  // Generate mermaid output
  let mermaid = generate_mermaid(
    graph,
    config.graph_type,
    config.focus,
    config.title,
    config.no_fence,
  )
  if mermaid.length() == 0 {
    println("No graph data found. The analyzed files may not contain dependency information.")
    return
  }
  // Output
  if config.output_file.length() > 0 {
    if write_output(config.output_file, mermaid) {
      println("Written to: " + config.output_file)
    }
  } else {
    println(mermaid)
  }
}
