///|
/// # indexion plan documentation
///
/// Generate documentation coverage analysis and README templates.
///
/// ## Usage
///
/// ```bash
/// indexion plan documentation [options] <directory>
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--output=FILE`, `-o=` | Output file path | stdout |
/// | `--style=STYLE` | Output style: coverage, readme, full | full |
/// | `--name=NAME` | Project name (auto-detect from moon.mod.json) | - |

///|
pub struct DocPlanConfig {
  target_dir : String
  output : String
  style : String // "coverage", "readme", "full"
  project_name : String
  show_help : Bool
}

///|
pub fn DocPlanConfig::default() -> DocPlanConfig {
  {
    target_dir: "",
    output: "",
    style: "full",
    project_name: "",
    show_help: false,
  }
}

///|
fn get_arg_value(arg : String, prefix_len : Int) -> String {
  let chars = arg.to_array()
  if prefix_len >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = prefix_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
pub fn parse_args(args : Array[String], start_idx : Int) -> DocPlanConfig {
  let mut config = DocPlanConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = get_arg_value(arg, prefix_len)
      config = { ..config, output: value }
    } else if arg.has_prefix("--style=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, style: value }
    } else if arg.has_prefix("--name=") {
      let value = get_arg_value(arg, 7)
      config = { ..config, project_name: value }
    } else if not(arg.has_prefix("-")) && config.target_dir.length() == 0 {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
pub fn show_help() -> Unit {
  println(
    "indexion plan documentation - Generate documentation coverage analysis",
  )
  println("")
  println("Usage:")
  println("  indexion plan documentation [options] <directory>")
  println("")
  println("Options:")
  println("  --output=FILE, -o=   Output file path (default: stdout)")
  println("  --style=STYLE        Output style: coverage, full (default: full)")
  println("  --name=NAME          Project name (auto-detect from moon.mod.json)")
  println("  --help               Show this help message")
  println("")
  println("Styles:")
  println("  coverage   Documentation coverage analysis only")
  println("  full       Complete documentation plan with action items")
  println("")
  println("Examples:")
  println("  indexion plan documentation src/")
  println("  indexion plan documentation --style=coverage src/")
  println("  indexion plan documentation -o=docs-plan.md src/")
  println("")
  println("Note: Use 'indexion doc init' to generate README templates.")
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  if config.target_dir.length() == 0 {
    println("Error: Directory path required.")
    println("")
    show_help()
    return
  }
  // Load project info from moon.mod.json if available
  let project_info = load_project_info(config.target_dir)
  let project_name = if config.project_name.length() > 0 {
    config.project_name
  } else {
    project_info.name
  }
  // Analyze documentation coverage
  let analysis = analyze_documentation(config.target_dir)
  // Render output
  let output_content = match config.style {
    "coverage" => render_coverage(analysis, project_name)
    _ => render_full(analysis, project_info, project_name)
  }
  // Output
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output_content)
      println("Documentation plan written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output_content)
  }
}
