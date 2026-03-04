///|
/// # indexion doc readme
///
/// Extract documentation from source files and generate README files.
///
/// ## Overview
///
/// Extracts `///` documentation comments from MoonBit source files and
/// outputs them in various formats. Supports flexible package discovery
/// with include/exclude patterns.
///
/// ## Usage
///
/// ```bash
/// indexion doc readme [options] [paths...]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--include=PATTERN` | Include packages matching glob (repeatable) | all |
/// | `--exclude=PATTERN` | Exclude packages matching glob (repeatable) | none |
/// | `--recursive` | Scan directories recursively | true |
/// | `--no-recursive` | Do not scan recursively | |
/// | `--format=FORMAT` | Output: `markdown`, `json`, `raw` | markdown |
/// | `--output=FILE` | Output to file | stdout |
/// | `--per-package` | Generate README.md per package | false |
/// | `--root` | Generate root README.md | false |
/// | `--no-packages` | Skip individual package output | false |
///
/// ## Examples
///
/// ```bash
/// # Extract docs from current directory
/// indexion doc readme
///
/// # Extract from specific path with JSON output
/// indexion doc readme --format=json src/
///
/// # Filter packages
/// indexion doc readme --include="cmd/*" --exclude="*test*"
///
/// # Generate per-package READMEs (legacy behavior)
/// indexion doc readme --per-package --root
/// ```

///|
/// Configuration for README generation.
pub struct ReadmeConfig {
  paths : Array[String]
  includes : Array[String]
  excludes : Array[String]
  recursive : Bool
  format : String
  output : String?
  per_package : Bool
  generate_root : Bool
  skip_packages : Bool
  show_help : Bool
}

///|
pub fn ReadmeConfig::default() -> ReadmeConfig {
  {
    paths: [],
    includes: [],
    excludes: [],
    recursive: true,
    format: "markdown",
    output: None,
    per_package: false,
    generate_root: false,
    skip_packages: false,
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
pub fn parse_args(args : Array[String], start_idx : Int) -> ReadmeConfig {
  let mut config = ReadmeConfig::default()
  let paths : Array[String] = []
  let includes : Array[String] = []
  let excludes : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--recursive" {
      config = { ..config, recursive: true }
    } else if arg == "--no-recursive" {
      config = { ..config, recursive: false }
    } else if arg == "--per-package" {
      config = { ..config, per_package: true }
    } else if arg == "--root" {
      config = { ..config, generate_root: true }
    } else if arg == "--no-packages" {
      config = { ..config, skip_packages: true }
    } else if arg.has_prefix("--include=") {
      let value = get_arg_value(arg, 10)
      includes.push(value)
    } else if arg.has_prefix("--exclude=") {
      let value = get_arg_value(arg, 10)
      excludes.push(value)
    } else if arg.has_prefix("--format=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = get_arg_value(arg, prefix_len)
      config = { ..config, output: Some(value) }
    } else if not(arg.has_prefix("-")) {
      paths.push(arg)
    }
  }
  // Default path if none specified
  if paths.length() == 0 {
    paths.push(".")
  }
  { ..config, paths, includes, excludes }
}

///|
pub fn show_help() -> Unit {
  println("indexion doc readme - Extract documentation from source files")
  println("")
  println("Usage:")
  println("  indexion doc readme [options] [paths...]")
  println("")
  println("Options:")
  println("  --include=PATTERN    Include packages matching glob (repeatable)")
  println("  --exclude=PATTERN    Exclude packages matching glob (repeatable)")
  println("  --recursive          Scan directories recursively (default)")
  println("  --no-recursive       Do not scan recursively")
  println(
    "  --format=FORMAT      Output format: markdown, json, raw (default: markdown)",
  )
  println("  --output=FILE        Write output to file (default: stdout)")
  println("  -o=FILE              Short form of --output")
  println("  --per-package        Generate README.md in each package directory")
  println("  --root               Generate root README.md")
  println(
    "  --no-packages        Skip individual package output (use with --root)",
  )
  println("  --help               Show this help message")
  println("")
  println("Examples:")
  println(
    "  indexion doc readme                                  # Extract from current dir",
  )
  println(
    "  indexion doc readme --format=json src/               # JSON output",
  )
  println("  indexion doc readme --include=\"cmd/*\" --exclude=\"*test*\"")
  println(
    "  indexion doc readme --per-package --root             # Legacy behavior",
  )
  println("")
  println("Patterns:")
  println("  *           Match any characters")
  println("  cmd/*       Match packages starting with cmd/")
  println("  *test*      Match packages containing 'test'")
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  // Discover packages
  let packages = discover_packages(
    config.paths,
    config.includes,
    config.excludes,
    config.recursive,
  )
  if packages.length() == 0 {
    println("No packages found.")
    return
  }
  // Extract documentation from each package
  let docs : Array[(PackageInfo, ExtractedDoc)] = []
  for pkg in packages {
    match pkg.main_file {
      Some(file) =>
        match extract_doc_from_file(file) {
          Some(doc) => docs.push((pkg, doc))
          None => ()
        }
      None => ()
    }
  }
  if docs.length() == 0 {
    println("No documentation found.")
    return
  }
  // Handle per-package output (legacy behavior)
  if config.per_package {
    println("Generating package READMEs...")
    write_per_package(docs)
    println("")
  }
  // Handle root README generation
  if config.generate_root {
    println("Generating root README...")
    let base_dir = if config.paths.length() > 0 { config.paths[0] } else { "." }
    let _ = generate_root_readme(docs, base_dir)
    println("")
  }
  // If not per-package and not root-only, output combined docs
  if not(config.per_package) && not(config.skip_packages) {
    let format = OutputFormat::from_string(config.format)
    let content = match format {
      Markdown => render_markdown(docs)
      Json => render_json(docs)
      Raw => render_raw(docs)
    }
    let to_stdout = config.output is None && not(config.generate_root)
    write_output(content, config.output, to_stdout)
  }
}
