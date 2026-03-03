///|
/// Documentation Generator CLI
/// Generates documentation from source files using KGF-based analysis.
///
/// Usage:
///   moon run cmd/docgen -- [options] [files...]
///
/// Options:
///   --format=markdown|json|both  Output format (default: both)
///   --output=DIR                 Output directory (default: output)
///   --no-diagrams                Disable Mermaid diagrams
///   --help                       Show this help message
///
/// Examples:
///   moon run cmd/docgen -- src/*.ts
///   moon run cmd/docgen -- --format=json --output=docs src/
///   moon run cmd/docgen -- (uses sample data for demo)

///|
/// CLI configuration parsed from arguments.
struct CliConfig {
  format : String // "markdown", "json", or "both"
  output_dir : String
  include_diagrams : Bool
  input_paths : Array[String]
  show_help : Bool
}

///|
/// Create default CLI configuration.
fn CliConfig::default() -> CliConfig {
  {
    format: "both",
    output_dir: "output",
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
/// Parse command line arguments.
fn parse_args(args : Array[String]) -> CliConfig {
  let mut config = CliConfig::default()
  let paths : Array[String] = []
  // Skip first argument (program name/path)
  let start_idx = if args.length() > 0 { 1 } else { 0 }
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
    } else if not(arg.has_prefix("-")) {
      paths.push(arg)
    }
  }
  { ..config, input_paths: paths }
}

///|
/// Show help message.
fn show_help() -> Unit {
  println("indexion Documentation Generator")
  println("")
  println("Usage:")
  println("  moon run cmd/docgen -- [options] [files...]")
  println("")
  println("Options:")
  println("  --format=markdown|json|both  Output format (default: both)")
  println("  --output=DIR                 Output directory (default: output)")
  println("  --no-diagrams                Disable Mermaid diagrams")
  println("  --help                       Show this help message")
  println("")
  println("Examples:")
  println("  moon run cmd/docgen -- src/*.ts")
  println("  moon run cmd/docgen -- --format=json --output=docs src/")
  println("  moon run cmd/docgen -- (uses sample data for demo)")
}

///|
/// Main entry point.
fn main {
  // Parse command line arguments
  let args = @sys.get_cli_args()
  let config = parse_args(args)
  if config.show_help {
    show_help()
    return
  }
  println("=== indexion Documentation Generator ===")
  println("")
  // Determine if we're using real files or sample data
  let graph = if config.input_paths.length() > 0 {
    process_input_files(config.input_paths)
  } else {
    println("No input files specified, using sample data for demo.")
    println("")
    create_sample_graph()
  }
  println("Graph Statistics:")
  println("  Modules: " + graph.module_count().to_string())
  println("  Symbols: " + graph.symbol_count().to_string())
  println("  Edges: " + graph.edge_count().to_string())
  println("")
  // Create render options
  let options = @render.RenderOptions::new(
    format=if config.format == "json" {
      @render.OutputFormat::json()
    } else {
      @render.OutputFormat::markdown()
    },
    include_diagrams=config.include_diagrams,
  )
  // Ensure output directory exists
  ensure_output_dir(config.output_dir)
  // Generate outputs based on format
  if config.format == "markdown" || config.format == "both" {
    println("Generating markdown documentation...")
    let output = @render.render_markdown(graph, options)
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

///|
/// Process input files and build graph.
fn process_input_files(paths : Array[String]) -> @graph.CodeGraph {
  let files : Array[(String, String)] = []
  for path in paths {
    collect_files(path, files)
  }
  println("Processing " + files.length().to_string() + " file(s)...")
  println("")
  // Build graph from files
  // Note: Currently creates a basic graph since KGF spec loading
  // would require additional setup. This demonstrates the file reading capability.
  let graph = @graph.CodeGraph::new()
  let declares = @graph.EdgeKind::from_string("declares")
  for entry in files {
    let path = entry.0
    let content = entry.1
    // Add module for file
    let _ = graph.get_or_add_module(path, file=Some(path))
    // Extract basic symbols from content (simplified analysis)
    extract_symbols_from_content(graph, path, content, declares)
  }
  graph
}

///|
/// Collect files from a path (file or directory).
fn collect_files(path : String, files : Array[(String, String)]) -> Unit {
  try {
    if @fs.is_dir(path) {
      // Read directory contents
      let entries = @fs.read_dir(path)
      for entry in entries {
        let full_path = path + "/" + entry
        collect_files(full_path, files)
      }
    } else if @fs.is_file(path) {
      // Check if it's a supported file type
      if is_supported_file(path) {
        let content = @fs.read_file_to_string(path)
        files.push((path, content))
      }
    }
  } catch {
    e => println("Warning: Could not read " + path + ": " + e.to_string())
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
/// Extract basic symbols from file content.
/// This is a simplified extraction - full KGF parsing would be used in production.
fn extract_symbols_from_content(
  graph : @graph.CodeGraph,
  path : String,
  content : String,
  declares : @graph.EdgeKind,
) -> Unit {
  let lines = split_lines(content)
  for i, line in lines {
    // Look for common declaration patterns
    let trimmed = trim(line)
    // TypeScript/JavaScript: export function/class/interface/type
    if trimmed.has_prefix("export function ") ||
      trimmed.has_prefix("export async function ") {
      let name = extract_function_name(trimmed)
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Function")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("export class ") {
      let name = extract_class_name(trimmed, "class ")
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Class")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("export interface ") {
      let name = extract_class_name(trimmed, "interface ")
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Interface")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("export type ") {
      let name = extract_type_name(trimmed)
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Type")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("pub fn ") || trimmed.has_prefix("fn ") {
      // MoonBit function
      let name = extract_mbt_function_name(trimmed)
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Function")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("pub struct ") || trimmed.has_prefix("struct ") {
      // MoonBit struct
      let name = extract_mbt_type_name(trimmed, "struct ")
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Struct")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("pub enum ") || trimmed.has_prefix("enum ") {
      // MoonBit enum
      let name = extract_mbt_type_name(trimmed, "enum ")
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Enum")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("def ") {
      // Python function
      let name = extract_python_function_name(trimmed)
      if name.length() > 0 {
        let attrs : Map[String, String] = {}
        attrs.set("name", name)
        attrs.set("kind", "Function")
        attrs.set("line", (i + 1).to_string())
        graph.add_edge(declares, path, path + "::" + name, attrs~)
      }
    } else if trimmed.has_prefix("class ") && not(trimmed.has_prefix("class ")) {
      // Python class (with inheritance check)
      ()
    }
  }
}

///|
/// Extract function name from "export function name(" or "export async function name("
fn extract_function_name(line : String) -> String {
  let start = if line.has_prefix("export async function ") { 22 } else { 16 }
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '(' || c == '<' || c == ' ' {
      break
    }
    if is_identifier_char(c) {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Extract class/interface name from "export class/interface Name"
fn extract_class_name(line : String, keyword : String) -> String {
  let start = 7 + keyword.length() // "export " + keyword
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '{' || c == '<' || c == '\n' {
      break
    }
    if is_identifier_char(c) {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Extract type name from "export type Name = ..."
fn extract_type_name(line : String) -> String {
  let start = 12 // "export type "
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '=' || c == '<' {
      break
    }
    if is_identifier_char(c) {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Extract MoonBit function name from "pub fn name(" or "fn name("
fn extract_mbt_function_name(line : String) -> String {
  let start = if line.has_prefix("pub fn ") { 7 } else { 3 }
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '(' || c == '[' || c == ' ' {
      break
    }
    if is_identifier_char(c) || c == ':' {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Extract MoonBit type name from "pub struct/enum Name" or "struct/enum Name"
fn extract_mbt_type_name(line : String, keyword : String) -> String {
  let prefix = if line.has_prefix("pub ") { "pub " } else { "" }
  let start = prefix.length() + keyword.length()
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '{' || c == '[' || c == '\n' {
      break
    }
    if is_identifier_char(c) {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Extract Python function name from "def name("
fn extract_python_function_name(line : String) -> String {
  let start = 4 // "def "
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '(' {
      break
    }
    if is_identifier_char(c) {
      result.push(c)
    }
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Check if character is valid in an identifier.
fn is_identifier_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Split string into lines.
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == '\n' {
      result.push(String::from_array(current))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    result.push(String::from_array(current))
  }
  result
}

///|
/// Trim whitespace from string.
fn trim(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  if start >= end {
    return ""
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
/// Create a sample code graph for demonstration.
fn create_sample_graph() -> @graph.CodeGraph {
  let graph = @graph.CodeGraph::new()
  // Add modules
  let _ = graph.get_or_add_module(
    "core/graph/graph.mbt",
    file=Some("core/graph/graph.mbt"),
  )
  let _ = graph.get_or_add_module(
    "core/graph/types.mbt",
    file=Some("core/graph/types.mbt"),
  )
  let _ = graph.get_or_add_module(
    "kgf/lexer/lexer.mbt",
    file=Some("kgf/lexer/lexer.mbt"),
  )
  let _ = graph.get_or_add_module(
    "doc/build/pipeline.mbt",
    file=Some("doc/build/pipeline.mbt"),
  )
  // Add declares edges with documentation
  let declares = @graph.EdgeKind::from_string("declares")
  // CodeGraph struct
  let cg_attrs : Map[String, String] = {}
  cg_attrs.set("name", "CodeGraph")
  cg_attrs.set("kind", "Struct")
  cg_attrs.set("doc", "A directed graph representing code relationships.")
  graph.add_edge(
    declares,
    "core/graph/graph.mbt",
    "core/graph/graph.mbt::CodeGraph",
    attrs=cg_attrs,
  )
  // CodeGraph::new
  let cg_new_attrs : Map[String, String] = {}
  cg_new_attrs.set("name", "new")
  cg_new_attrs.set("kind", "Function")
  cg_new_attrs.set("doc", "Creates a new empty CodeGraph.")
  graph.add_edge(
    declares,
    "core/graph/graph.mbt",
    "core/graph/graph.mbt::CodeGraph::new",
    attrs=cg_new_attrs,
  )
  // CodeGraph::add_edge
  let add_edge_attrs : Map[String, String] = {}
  add_edge_attrs.set("name", "add_edge")
  add_edge_attrs.set("kind", "Function")
  add_edge_attrs.set("doc", "Adds an edge between two nodes.")
  graph.add_edge(
    declares,
    "core/graph/graph.mbt",
    "core/graph/graph.mbt::CodeGraph::add_edge",
    attrs=add_edge_attrs,
  )
  // EdgeKind enum
  let ek_attrs : Map[String, String] = {}
  ek_attrs.set("name", "EdgeKind")
  ek_attrs.set("kind", "Enum")
  ek_attrs.set("doc", "Kinds of edges in the code graph.")
  graph.add_edge(
    declares,
    "core/graph/types.mbt",
    "core/graph/types.mbt::EdgeKind",
    attrs=ek_attrs,
  )
  // Lexer struct
  let lexer_attrs : Map[String, String] = {}
  lexer_attrs.set("name", "Lexer")
  lexer_attrs.set("kind", "Struct")
  lexer_attrs.set("doc", "KGF Lexer for tokenizing source code.")
  graph.add_edge(
    declares,
    "kgf/lexer/lexer.mbt",
    "kgf/lexer/lexer.mbt::Lexer",
    attrs=lexer_attrs,
  )
  // Lexer::tokenize
  let tokenize_attrs : Map[String, String] = {}
  tokenize_attrs.set("name", "tokenize")
  tokenize_attrs.set("kind", "Function")
  tokenize_attrs.set("doc", "Tokenizes the input string.")
  graph.add_edge(
    declares,
    "kgf/lexer/lexer.mbt",
    "kgf/lexer/lexer.mbt::Lexer::tokenize",
    attrs=tokenize_attrs,
  )
  // build function
  let build_attrs : Map[String, String] = {}
  build_attrs.set("name", "build")
  build_attrs.set("kind", "Function")
  build_attrs.set("doc", "Build documentation from configuration.")
  graph.add_edge(
    declares,
    "doc/build/pipeline.mbt",
    "doc/build/pipeline.mbt::build",
    attrs=build_attrs,
  )
  // Add module dependencies
  let depends = @graph.EdgeKind::from_string("module_depends_on")
  graph.add_edge(depends, "doc/build/pipeline.mbt", "core/graph/graph.mbt")
  graph.add_edge(depends, "doc/build/pipeline.mbt", "kgf/lexer/lexer.mbt")
  // Add call relationships
  let calls = @graph.EdgeKind::from_string("calls")
  graph.add_edge(
    calls, "doc/build/pipeline.mbt::build", "core/graph/graph.mbt::CodeGraph::new",
  )
  graph.add_edge(
    calls, "doc/build/pipeline.mbt::build", "kgf/lexer/lexer.mbt::Lexer::tokenize",
  )
  // Add references
  let refs = @graph.EdgeKind::from_string("references")
  graph.add_edge(
    refs, "doc/build/pipeline.mbt::build", "core/graph/types.mbt::EdgeKind",
  )
  graph
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
  // Graph statistics
  lines.push("## Graph Statistics")
  lines.push("")
  lines.push("| Metric | Count |")
  lines.push("|--------|-------|")
  lines.push("| Modules | " + graph.module_count().to_string() + " |")
  lines.push("| Symbols | " + graph.symbol_count().to_string() + " |")
  lines.push("| Edges | " + graph.edge_count().to_string() + " |")
  lines.push("")
  // Module list
  lines.push("## Modules")
  lines.push("")
  for entry in graph.get_modules() {
    let m = entry.1
    lines.push("- `" + m.id + "`")
  }
  lines.push("")
  // Symbol list grouped by module
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
