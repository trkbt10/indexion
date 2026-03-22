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
/// | `--output=FILE` | Output file | stdout |
/// | `--specs-dir=DIR` | KGF specs directory | kgfs |
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
}

///|
/// Create default configuration.
pub fn GraphConfig::default() -> GraphConfig {
  {
    output: "",
    specs_dir: "kgfs",
    title: "Module Dependencies",
    format: "mermaid",
    input_paths: [],
  }
}

///|
/// Create GraphConfig from argparse matches.
pub fn GraphConfig::from_matches(matches : @argparse.Matches) -> GraphConfig {
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let title = match matches.values.get("title") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "Module Dependencies" }
    _ => "Module Dependencies"
  }
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "mermaid" }
    _ => "mermaid"
  }
  let input_paths = match matches.values.get("files") {
    Some(arr) if arr.length() > 0 => arr
    _ => ["."]
  }
  { output, specs_dir, title, format, input_paths }
}

///|
/// Define the graph command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "graph",
    about="Generate dependency graph in Mermaid format",
    options=[
      @argparse.OptionArg("output", about="Output file (default: stdout)"),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
      @argparse.OptionArg("title", about="Diagram title", default_values=[
        "Module Dependencies",
      ]),
      @argparse.OptionArg(
        "format",
        about="Output format: mermaid, json, dot, d2, text",
        default_values=["mermaid"],
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "files",
        num_args=@argparse.ValueRange(lower=0),
        about="Input files or directories",
      ),
    ],
  )
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
/// Run the graph command from argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = GraphConfig::from_matches(matches)
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
  // Stage 1: Load KGF specs to get ignore patterns.
  println("Loading language specs...")
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.input_paths,
  )
  // Stage 2: Collect candidate files using KGF ignore patterns.
  println("Collecting files...")
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(kgf_ignore~)
  let candidate_paths = @pipeline.discover_files(
    config.input_paths,
    discover_opts,
  )
  if candidate_paths.length() == 0 {
    println("No input files found.")
    return
  }
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
  } else if config.format == "codegraph" {
    // Full CodeGraph JSON (for digest indexing)
    graph.to_json_string()
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
      @common.write_output(
        config.output,
        "{\"dependencies\":[],\"circular_dependencies\":[],\"statistics\":{\"total_dependencies\":0,\"circular_count\":0}}",
      )
    } else {
      println("No dependencies found in the analyzed files.")
    }
    return
  }
  @common.write_output(config.output, output)
  // Print summary to stderr if outputting to file
  if config.output.length() > 0 {
    println("Dependencies: " + deps.length().to_string())
    if circulars.length() > 0 {
      println("Circular references: " + circulars.length().to_string())
    }
  }
}
