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
  output : String
  template : String?
  config_path : String?
  per_package : Bool
}

///|
/// Create a default README generation configuration.
pub fn ReadmeConfig::default() -> ReadmeConfig {
  {
    paths: [],
    specs_dir: "kgfs",
    includes: [],
    excludes: [],
    recursive: true,
    format: "md",
    output: "",
    template: None,
    config_path: None,
    per_package: false,
  }
}

///|
/// Create ReadmeConfig from argparse matches.
pub fn ReadmeConfig::from_matches(matches : @argparse.Matches) -> ReadmeConfig {
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let includes = matches.values.get("include").unwrap_or([])
  let excludes = matches.values.get("exclude").unwrap_or([])
  let recursive = matches.flags.get("recursive").unwrap_or(true)
  let format = match matches.values.get("format") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "md" }
    _ => "md"
  }
  let output = match matches.values.get("output") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    _ => ""
  }
  let template : String? = match matches.values.get("template") {
    Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
    _ => None
  }
  let config_path : String? = match matches.values.get("config") {
    Some(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
    _ => None
  }
  let per_package = matches.flags.get("per-package").unwrap_or(false)
  let paths = match matches.values.get("paths") {
    Some(arr) if arr.length() > 0 => arr
    _ => ["."]
  }
  {
    paths,
    specs_dir,
    includes,
    excludes,
    recursive,
    format,
    output,
    template,
    config_path,
    per_package,
  }
}

///|
/// Define the readme command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "readme",
    about="Extract documentation from source files and generate README files",
    options=[
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
      @argparse.OptionArg(
        "include",
        action=Append,
        about="Include packages matching glob (repeatable)",
      ),
      @argparse.OptionArg(
        "exclude",
        action=Append,
        about="Exclude packages matching glob (repeatable)",
      ),
      @argparse.OptionArg(
        "format",
        about="Output format: markdown, json, raw",
        default_values=["md"],
      ),
      @argparse.OptionArg(
        "output",
        short='o',
        about="Write output to file (default: stdout)",
      ),
      @argparse.OptionArg("template", about="Use template file for generation"),
      @argparse.OptionArg("config", about="Use doc.json configuration file"),
    ],
    flags=[
      @argparse.FlagArg(
        "recursive",
        negatable=true,
        about="Scan directories recursively (default: true)",
      ),
      @argparse.FlagArg(
        "per-package",
        about="Generate README.md in each package directory",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "paths",
        num_args=@argparse.ValueRange(lower=0),
        about="Paths to scan",
      ),
    ],
  )
}

///|
/// Log progress message to stderr (falls back to println for now).
fn log_progress(msg : String) -> Unit {
  // TODO: Use stderr when MoonBit supports it
  println(msg)
}

///|
/// Run the doc readme command from argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = ReadmeConfig::from_matches(matches)
  // If --config is specified, use doc.json-based generation.
  // Otherwise, check .indexion.toml for [doc].config_path as fallback.
  let effective_config_path : String? = match config.config_path {
    Some(_) => config.config_path
    None => {
      let target_dir = if config.paths.length() > 0 {
        config.paths[0]
      } else {
        "."
      }
      let toml_path = @doc_config.find_indexion_config_path(target_dir)
      let doc_file_config = @doc_config.load_effective_doc_config(toml_path)
      doc_file_config.config_path
    }
  }
  match effective_config_path {
    Some(config_path) => {
      run_with_doc_config(config_path, config)
      return
    }
    None => ()
  }
  // Stage 1: Load KGF specs to get ignore patterns.
  log_progress("[1/4] Loading KGF specs...")
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dirs=config.paths,
  )
  if registry.spec_count() > 0 {
    log_progress("      Loaded " + registry.spec_count().to_string() + " specs")
  } else {
    println("Warning: No KGF specs found")
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
            @common.write_output(config.output, content, label="Readme")
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
          @common.write_output(config.output, content, label="Readme")
        None => println("Error: Could not read template file: " + template_path)
      }
    }
    None =>
      // If not using template and not per-package, output combined docs
      if !config.per_package {
        let format = OutputFormat::from_string(config.format)
        let content = match format {
          Markdown => render_markdown(docs)
          Json => render_json(docs)
          Raw => render_raw(docs)
        }
        @common.write_output(config.output, content, label="Readme")
      }
  }
}
