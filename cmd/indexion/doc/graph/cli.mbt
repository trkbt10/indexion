///|
/// # indexion doc graph
///
/// Generate dependency graph in Mermaid format from source files.
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
/// | `--output=FILE` | Output file (- for stdout) | - |
/// | `--specs=DIR` | KGF specs directory | kgfs |
/// | `--title=TEXT` | Diagram title | Module Dependencies |
/// | `--format=FORMAT` | Output format: mermaid, json, dot, d2, text | mermaid |
///
/// ## Examples
///
/// ```bash
/// # Output to stdout
/// indexion doc graph src/
///
/// # Save to file
/// indexion doc graph --output=deps.md src/
///
/// # With custom title
/// indexion doc graph --title="My Project Dependencies" src/
/// ```

///|
/// CLI configuration for graph command.
pub struct GraphConfig {
  output : String
  specs_dir : String
  title : String
  format : String
  input_paths : Array[String]
  show_help : Bool
}

///|
/// Create default configuration.
pub fn GraphConfig::default() -> GraphConfig {
  {
    output: "-",
    specs_dir: "kgfs",
    title: "Module Dependencies",
    format: "mermaid",
    input_paths: [],
    show_help: false,
  }
}

///|
/// Extract value after '=' in argument.
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
/// Parse command line arguments.
pub fn parse_args(args : Array[String], start_idx : Int) -> GraphConfig {
  let mut config = GraphConfig::default()
  let paths : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--output=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, output: value }
    } else if arg.has_prefix("--specs=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, specs_dir: value }
    } else if arg.has_prefix("--title=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, title: value }
    } else if arg.has_prefix("--format=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if not(arg.has_prefix("-")) {
      paths.push(arg)
    }
  }
  { ..config, input_paths: paths }
}

///|
/// Show help message.
pub fn show_help() -> Unit {
  println("indexion doc graph - Generate dependency graph in Mermaid format")
  println("")
  println("Usage:")
  println("  indexion doc graph [options] [files...]")
  println("")
  println("Options:")
  println("  --output=FILE    Output file (- for stdout, default: -)")
  println("  --specs=DIR      KGF specs directory (default: kgfs)")
  println("  --title=TEXT     Diagram title (default: Module Dependencies)")
  println(
    "  --format=FORMAT  Output format: mermaid, json, dot, d2, text (default: mermaid)",
  )
  println("  --help           Show this help message")
  println("")
  println("Examples:")
  println("  indexion doc graph src/")
  println("  indexion doc graph --output=deps.md src/")
  println("  indexion doc graph --title=\"API Dependencies\" src/api/")
}

///|
/// Write output to file or stdout.
fn write_output(output : String, content : String) -> Unit {
  if output == "-" {
    println(content)
  } else {
    try {
      @fs.write_string_to_file(output, content)
      println("Written to: " + output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  }
}

///|
/// Generate JSON output with dependencies and circular references.
fn generate_json_output(
  deps : Array[@query.ModuleDep],
  circulars : Array[@query.CircularDep],
) -> String {
  let obj : Map[String, Json] = {}
  // Add dependencies
  let deps_arr : Array[Json] = []
  for dep in deps {
    let dep_obj : Map[String, Json] = {}
    dep_obj.set("from", dep.from.to_json())
    dep_obj.set("to", dep.to.to_json())
    match dep.via {
      Some(v) => dep_obj.set("via", v.to_json())
      None => ()
    }
    match dep.dep_kind {
      Some(k) => dep_obj.set("kind", k.to_json())
      None => ()
    }
    deps_arr.push(Json::object(dep_obj))
  }
  obj.set("dependencies", Json::array(deps_arr))
  // Add circular references
  let circ_arr : Array[Json] = []
  for circ in circulars {
    let circ_obj : Map[String, Json] = {}
    circ_obj.set("from", circ.from.to_json())
    circ_obj.set("to", circ.to.to_json())
    circ_arr.push(Json::object(circ_obj))
  }
  obj.set("circular_dependencies", Json::array(circ_arr))
  // Add statistics
  let stats : Map[String, Json] = {}
  stats.set("total_dependencies", deps.length().to_json())
  stats.set("circular_count", circulars.length().to_json())
  obj.set("statistics", Json::object(stats))
  Json::object(obj).stringify()
}

///|
/// Progress callback for file analysis.
fn print_progress(info : (Int, Int, String)) -> Unit {
  let (current, total, path) = info
  println(
    "[" + current.to_string() + "/" + total.to_string() + "] Analyzing: " + path,
  )
}

///|
/// Run the graph command.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.input_paths.length() == 0 {
    println("No input files found.")
    return
  }
  let mut has_existing_input = false
  for path in config.input_paths {
    let exists = (@fs.is_dir(path) || @fs.is_file(path)) catch { _ => false }
    if exists {
      has_existing_input = true
      break
    }
  }
  if not(has_existing_input) {
    println("No input files found.")
    return
  }
  // Stage 1: Collect candidate files from input directories.
  println("Collecting files...")
  let discover_opts = @pipeline.DiscoverOptions::default()
  let candidate_paths = @pipeline.discover_files(
    config.input_paths,
    discover_opts,
  )
  if candidate_paths.length() == 0 {
    println("No input files found.")
    return
  }
  // Stage 2: Select relevant KGF specs from discovered files.
  println("Loading language specs...")
  let registry = @pipeline.load_registry_for_paths(
    config.specs_dir,
    candidate_paths,
  )
  let specs = registry.to_specs_map()
  // Stage 3: Filter supported files and read contents.
  let files = @pipeline.collect_supported_files(candidate_paths, registry)
  if files.length() == 0 {
    println("No input files found.")
    return
  }
  println("Found " + files.length().to_string() + " files to analyze.")
  // Stage 4: Build dependency graph using KGF parser pipeline.
  let doc_config = @build.DocConfig::new(
    files,
    specs,
    options=@render.RenderOptions::new(format=@render.OutputFormat::json()),
  )
  let progress = @build.ProgressCallback::new(print_progress)
  let (_, graph) = @build.build_with_graph_progress(doc_config, Some(progress))
  println("Analysis complete.")
  // Extract dependencies and circular references
  let deps = @query.extract_module_deps(graph)
  let circulars = @query.extract_circular_deps(graph)
  // Stage 5: Render graph output.
  // Build intermediate GraphJSON for flexible rendering
  let graph_json = @diagram.build_graph_from_deps(
    deps,
    circulars~,
    graph~,
    title=config.title,
  )
  let output = if config.format == "json" {
    // Raw dependency JSON
    generate_json_output(deps, circulars)
  } else if config.format == "dot" {
    @diagram.render_dot(graph_json)
  } else if config.format == "d2" {
    @diagram.render_d2(graph_json)
  } else if config.format == "text" {
    @diagram.render_text(graph_json)
  } else {
    // Default to Mermaid
    @diagram.render_mermaid(graph_json)
  }
  // Handle empty graph case
  if output.length() == 0 {
    if config.format == "json" {
      write_output(
        config.output,
        "{\"dependencies\":[],\"circular_dependencies\":[],\"statistics\":{\"total_dependencies\":0,\"circular_count\":0}}",
      )
    } else {
      println("No dependencies found in the analyzed files.")
    }
    return
  }
  write_output(config.output, output)
  // Print summary to stderr if outputting to file
  if config.output != "-" {
    println("Dependencies: " + deps.length().to_string())
    if circulars.length() > 0 {
      println("Circular references: " + circulars.length().to_string())
    }
  }
}
