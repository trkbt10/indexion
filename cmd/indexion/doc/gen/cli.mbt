///|
/// # indexion doc gen
///
/// Generate documentation from source files using KGF-based analysis.
///
/// ## Overview
///
/// Analyzes source code using KGF (Knowledge Graph Format) specifications,
/// extracts structure and documentation comments, and generates Markdown
/// or JSON output with optional Mermaid diagrams.
///
/// ## Usage
///
/// ```bash
/// indexion doc gen [options] [files...]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--format=FORMAT` | Output: `markdown`, `json`, `both` | both |
/// | `--output=DIR` | Output directory | .docgen |
/// | `--specs=DIR` | KGF specs directory | kgfs |
/// | `--no-diagrams` | Disable Mermaid diagram generation | false |
/// | `--config=FILE` | Documentation config file | doc.json |
///
/// ## Examples
///
/// ```bash
/// # Generate docs for all .mbt files
/// indexion doc gen src/*.mbt
///
/// # JSON output only
/// indexion doc gen --format=json --output=docs src/
///
/// # Using custom KGF specs
/// indexion doc gen --specs=my-kgfs src/
/// ```
///
/// ## Configuration
///
/// Create `doc.json` for advanced configuration:
/// ```json
/// {
///   "packages": [
///     {"path": "src/module", "title": "Module Name"}
///   ],
///   "root": {"output": "README.md"}
/// }
/// ```

///|
/// CLI configuration parsed from arguments.
pub struct DocgenConfig {
  format : String // "markdown", "json", or "both"
  output_dir : String
  specs_dir : String
  include_diagrams : Bool
  input_paths : Array[String]
  show_help : Bool
}

///|
/// Create default CLI configuration.
pub fn DocgenConfig::default() -> DocgenConfig {
  {
    format: "both",
    output_dir: ".docgen",
    specs_dir: "kgfs",
    include_diagrams: true,
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
/// Parse command line arguments for docgen.
/// The args should already have the subcommand removed (i.e., start from the docgen args).
pub fn parse_docgen_args(args : Array[String], start_idx : Int) -> DocgenConfig {
  let mut config = DocgenConfig::default()
  let paths : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--no-diagrams" {
      config = { ..config, include_diagrams: false }
    } else if arg.has_prefix("--format=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--output=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, output_dir: value }
    } else if arg.has_prefix("--specs=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, specs_dir: value }
    } else if not(arg.has_prefix("-")) {
      paths.push(arg)
    }
  }
  { ..config, input_paths: paths }
}

///|
/// Show help message for doc gen.
pub fn show_help() -> Unit {
  println("indexion doc gen - Generate documentation from source files")
  println("")
  println("Usage:")
  println("  indexion doc gen [options] [files...]")
  println("")
  println("Options:")
  println("  --format=markdown|json|both  Output format (default: both)")
  println("  --output=DIR                 Output directory (default: .docgen)")
  println("  --specs=DIR                  KGF specs directory (default: kgfs)")
  println("  --no-diagrams                Disable Mermaid diagrams")
  println("  --help                       Show this help message")
  println("")
  println("Examples:")
  println("  indexion doc gen src/*.mbt")
  println("  indexion doc gen --format=json --output=docs src/")
  println("  indexion doc gen (uses sample data for demo)")
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
    e => println("Warning: Could not read " + clean_path + ": " + e.to_string())
  }
}

///|
/// Remove trailing slash from path.
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
/// Check if file extension is supported.
fn is_supported_file(path : String) -> Bool {
  let extensions = [
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".mbt", ".py", ".go", ".rs", ".sql", ".html",
    ".css", ".md",
  ]
  for ext in extensions {
    if path.has_suffix(ext) {
      return true
    }
  }
  false
}

///|
/// Create sample MoonBit content for demo.
fn create_sample_mbt() -> String {
  let sample =
    #|///|
    #|/// A sample struct for demonstration.
    #|pub struct Point {
    #|  /// X coordinate.
    #|  x : Int
    #|  /// Y coordinate.
    #|  y : Int
    #|}
    #|
    #|///|
    #|/// Calculate distance between two points.
    #|pub fn Point::distance(self : Point, other : Point) -> Double {
    #|  let dx = (other.x - self.x).to_double()
    #|  let dy = (other.y - self.y).to_double()
    #|  (dx * dx + dy * dy).sqrt()
    #|}
    #|
    #|///|
    #|/// Sample enum for directions.
    #|pub enum Direction {
    #|  /// North direction.
    #|  North
    #|  /// South direction.
    #|  South
    #|  /// East direction.
    #|  East
    #|  /// West direction.
    #|  West
    #|}
    #|
  sample
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
/// Ensure output directory exists.
fn ensure_output_dir(dir : String) -> Unit {
  try {
    if not(@fs.path_exists(dir)) {
      @fs.create_dir(dir)
    }
  } catch {
    _ => ()
  }
}

///|
/// Generate a summary document.
fn generate_summary(graph : @graph.CodeGraph) -> String {
  let lines : Array[String] = []
  lines.push("# indexion Documentation Summary")
  lines.push("")
  lines.push(
    "Generated by indexion documentation generator using KGF-based analysis.",
  )
  lines.push("")
  lines.push("---")
  lines.push("")
  lines.push("## Graph Statistics")
  lines.push("")
  lines.push("| Metric | Count |")
  lines.push("|--------|-------|")
  lines.push("| Modules | " + graph.module_count().to_string() + " |")
  lines.push("| Symbols | " + graph.symbol_count().to_string() + " |")
  lines.push("| Edges | " + graph.edge_count().to_string() + " |")
  lines.push("")
  lines.push("## Modules")
  lines.push("")
  for entry in graph.get_modules() {
    let m = entry.1
    lines.push("- `" + m.id + "`")
  }
  lines.push("")
  lines.push("## Symbols by Module")
  lines.push("")
  for entry in graph.get_modules() {
    let module_id = entry.0
    lines.push("### `" + module_id + "`")
    lines.push("")
    for sym_entry in graph.get_symbols() {
      let sym = sym_entry.1
      if sym.module_id == module_id {
        lines.push("- **" + sym.kind + "**: `" + sym.name + "`")
      }
    }
    lines.push("")
  }
  join_lines(lines)
}

///|
/// Join lines with newline.
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
/// Run docgen with the given arguments.
/// Args should be the full CLI args including program name.
/// start_idx is the index to start parsing from (after "docgen" subcommand).
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_docgen_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  println("=== indexion Documentation Generator ===")
  println("")
  // Load KGF specs
  println("Loading KGF specs from: " + config.specs_dir)
  let specs = load_specs(config.specs_dir)
  println("  Loaded " + specs.length().to_string() + " specs")
  println("")
  // Collect input files
  let files : Array[(String, String)] = []
  if config.input_paths.length() > 0 {
    for path in config.input_paths {
      collect_files(path, files)
    }
    println("Processing " + files.length().to_string() + " file(s)...")
  } else {
    println("No input files specified, using sample data for demo.")
    files.push(("demo/sample.mbt", create_sample_mbt()))
  }
  println("")
  // Build documentation using KGF pipeline
  let doc_config = @build.DocConfig::new(
    files,
    specs,
    options=@render.RenderOptions::new(
      format=if config.format == "json" {
        @render.OutputFormat::json()
      } else {
        @render.OutputFormat::markdown()
      },
      include_diagrams=config.include_diagrams,
    ),
  )
  let (output, graph) = @build.build_with_graph(doc_config)
  println("Graph Statistics:")
  println("  Modules: " + graph.module_count().to_string())
  println("  Symbols: " + graph.symbol_count().to_string())
  println("  Edges: " + graph.edge_count().to_string())
  println("")
  // Ensure output directory exists
  ensure_output_dir(config.output_dir)
  // Generate outputs based on format
  if config.format == "markdown" || config.format == "both" {
    println("Generating markdown documentation...")
    let markdown = output.to_markdown()
    let path = config.output_dir + "/api-reference.md"
    if write_output(path, markdown) {
      println(
        "  Written to: " +
        path +
        " (" +
        markdown.length().to_string() +
        " chars)",
      )
    }
  }
  if config.format == "json" || config.format == "both" {
    println("Generating JSON output...")
    let json_output = @render.render_json(graph)
    let path = config.output_dir + "/api-reference.json"
    if write_output(path, json_output) {
      println(
        "  Written to: " +
        path +
        " (" +
        json_output.length().to_string() +
        " chars)",
      )
    }
  }
  // Generate summary
  println("Generating summary...")
  let summary = generate_summary(graph)
  let summary_path = config.output_dir + "/summary.md"
  if write_output(summary_path, summary) {
    println("  Written to: " + summary_path)
  }
  println("")
  println("=== Done ===")
}
