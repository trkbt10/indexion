///|
/// # indexion doc readme
///
/// Extract documentation from source files and generate README files.
///
/// ## Overview
///
/// Extracts documentation comments from source files using KGF-based
/// language detection and parsing. Supports multiple languages and
/// template-based generation.
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
/// | `--specs-dir=DIR` | KGF specs directory | kgfs |
/// | `--include=PATTERN` | Include packages matching glob (repeatable) | all |
/// | `--exclude=PATTERN` | Exclude packages matching glob (repeatable) | none |
/// | `--recursive` | Scan directories recursively | true |
/// | `--no-recursive` | Do not scan recursively | |
/// | `--format=FORMAT` | Output: `markdown`, `json`, `raw` | markdown |
/// | `--output=FILE` | Output to file | stdout |
/// | `--template=FILE` | Use template file for generation | none |
/// | `--per-package` | Generate README.md per package | false |
///
/// ## Template Syntax
///
/// Templates support simple placeholder substitution:
/// - `{{include:path}}` - Include file contents
/// - `{{packages}}` - List of all discovered packages
///
/// ## Examples
///
/// ```bash
/// # Extract docs from current directory
/// indexion doc readme
///
/// # Generate README from template
/// indexion doc readme --template=docs/templates/readme.md --output=README.md
///
/// # Filter packages
/// indexion doc readme --include="cmd/*" --exclude="*test*"
/// ```

///|
/// Configuration for README generation.
pub struct ReadmeConfig {
  paths : Array[String]
  specs_dir : String
  includes : Array[String]
  excludes : Array[String]
  recursive : Bool
  format : String
  output : String?
  template : String?
  config_path : String?
  per_package : Bool
  show_help : Bool
}

///|
pub fn ReadmeConfig::default() -> ReadmeConfig {
  {
    paths: [],
    specs_dir: "kgfs",
    includes: [],
    excludes: [],
    recursive: true,
    format: "markdown",
    output: None,
    template: None,
    config_path: None,
    per_package: false,
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
    } else if arg.has_prefix("--specs-dir=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, specs_dir: value }
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
    } else if arg.has_prefix("--template=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, template: Some(value) }
    } else if arg.has_prefix("--config=") {
      let value = get_arg_value(arg, 9)
      config = { ..config, config_path: Some(value) }
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
  println("  --specs-dir=DIR      KGF specs directory (default: kgfs)")
  println("  --include=PATTERN    Include packages matching glob (repeatable)")
  println("  --exclude=PATTERN    Exclude packages matching glob (repeatable)")
  println("  --recursive          Scan directories recursively (default)")
  println("  --no-recursive       Do not scan recursively")
  println(
    "  --format=FORMAT      Output format: markdown, json, raw (default: markdown)",
  )
  println("  --output=FILE        Write output to file (default: stdout)")
  println("  -o=FILE              Short form of --output")
  println("  --template=FILE      Use template file for generation")
  println("  --config=FILE        Use doc.json configuration file")
  println("  --per-package        Generate README.md in each package directory")
  println("  --help               Show this help message")
  println("")
  println("Template Syntax:")
  println("  {{include:path}}     Include file contents")
  println("  {{packages}}         List of all discovered packages")
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
    "  indexion doc readme --template=docs/templates/readme.md --output=README.md",
  )
}

///|
/// Log progress message to stderr (falls back to println for now).
fn log_progress(msg : String) -> Unit {
  // TODO: Use stderr when MoonBit supports it
  println(msg)
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  // If --config is specified, use doc.json-based generation
  match config.config_path {
    Some(config_path) => {
      run_with_doc_config(config_path, config)
      return
    }
    None => ()
  }
  // Stage 1: Load KGF specs to get ignore patterns.
  log_progress("[1/4] Loading KGF specs...")
  let registry = @registry.KGFRegistry::load_from_dir(config.specs_dir)
  if registry.spec_count() == 0 {
    println("Warning: No KGF specs found in " + config.specs_dir)
  } else {
    log_progress("      Loaded " + registry.spec_count().to_string() + " specs")
  }
  // Stage 2: Collect candidate files using KGF ignore patterns.
  log_progress("[2/4] Discovering files...")
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    recursive=config.recursive,
    excludes=config.excludes,
    kgf_ignore~,
  )
  let candidate_paths = @pipeline.discover_files(config.paths, discover_opts)
  // If using template with only {{include:...}}, we don't need packages
  if candidate_paths.length() == 0 {
    match config.template {
      Some(template_path) => {
        // Process template even without packages (for {{include:...}} only)
        let base_dir = if config.paths.length() > 0 {
          config.paths[0]
        } else {
          "."
        }
        let ctx = TemplateContext::new(base_dir, [])
        match render_template_file(template_path, ctx) {
          Some(content) =>
            write_output(content, config.output, config.output is None)
          None =>
            println("Error: Could not read template file: " + template_path)
        }
        return
      }
      None => {
        println("No packages found.")
        return
      }
    }
  }
  log_progress("      Found " + candidate_paths.length().to_string() + " files")
  // Reuse loaded specs for docgen.
  let specs = registry.to_specs_map()
  // Stage 3: Build package groups from file list + selected specs.
  log_progress("[3/4] Grouping packages...")
  let packages = discover_packages_from_files(
    registry,
    candidate_paths,
    config.includes,
    config.excludes,
  )
  if packages.length() == 0 {
    println("No packages found.")
    return
  }
  log_progress("      Found " + packages.length().to_string() + " packages")
  // Extract documentation from each package
  log_progress("[4/4] Extracting documentation...")
  let docs : Array[(PackageInfo, ExtractedDoc)] = []
  for pkg in packages {
    match extract_package_doc(pkg, specs) {
      Some(doc) => docs.push((pkg, doc))
      None => ()
    }
  }
  log_progress("      Extracted " + docs.length().to_string() + " docs")
  if docs.length() == 0 {
    println("No documentation found.")
    return
  }
  // Handle per-package output
  if config.per_package {
    println("Generating package READMEs...")
    write_per_package(docs)
    println("")
  }
  // Handle template-based generation
  match config.template {
    Some(template_path) => {
      let base_dir = if config.paths.length() > 0 {
        config.paths[0]
      } else {
        "."
      }
      let ctx = TemplateContext::new(base_dir, docs)
      match render_template_file(template_path, ctx) {
        Some(content) =>
          write_output(content, config.output, config.output is None)
        None => println("Error: Could not read template file: " + template_path)
      }
    }
    None =>
      // If not using template and not per-package, output combined docs
      if not(config.per_package) {
        let format = OutputFormat::from_string(config.format)
        let content = match format {
          Markdown => render_markdown(docs)
          Json => render_json(docs)
          Raw => render_raw(docs)
        }
        write_output(content, config.output, config.output is None)
      }
  }
}
