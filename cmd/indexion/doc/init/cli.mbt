///|
/// # indexion doc init
///
/// Initialize documentation template structure for a project.
///
/// ## Overview
///
/// Generates `.indexion/` directory with template files based on
/// project metadata and KGF spec configuration. This keeps indexion
/// files isolated from user's docs/ directory.
///
/// ## Generated Structure
///
/// ```
/// .indexion/
///   templates/
///     readme.md           # README template with {{include:...}} placeholders
/// ```
///
/// ## Usage
///
/// ```bash
/// indexion doc init [options] [directory]
/// ```

///|
/// Configuration for doc init command.
pub struct InitConfig {
  target_dir : String
  specs_dir : String // KGF specs directory
  force : Bool // overwrite existing files
  show_help : Bool
}

///|
/// Create default InitConfig.
pub fn InitConfig::default() -> InitConfig {
  { target_dir: ".", specs_dir: "kgfs", force: false, show_help: false }
}

// get_arg_value: use @common (SoT)

///|
/// Parse command line arguments into InitConfig.
pub fn parse_args(args : Array[String], start_idx : Int) -> InitConfig {
  let mut config = InitConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--force" || arg == "-f" {
      config = { ..config, force: true }
    } else if arg.has_prefix("--specs-dir=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, specs_dir: value }
    } else if not(arg.has_prefix("-")) && config.target_dir == "." {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
/// Display help message for doc init command.
pub fn show_help() -> Unit {
  println("indexion doc init - Initialize documentation template structure")
  println("")
  println("Usage:")
  println("  indexion doc init [options] [directory]")
  println("")
  println("Options:")
  println("  --specs-dir=DIR      KGF specs directory (default: kgfs)")
  println("  --force, -f          Overwrite existing files")
  println("  --help               Show this help message")
  println("")
  println("Generated Files:")
  println(
    "  .indexion/state/templates/readme.md   README template with placeholders",
  )
  println("")
  println("Workflow:")
  println("  1. indexion doc init                  # Generate template")
  println(
    "  2. indexion plan readme --template=.indexion/state/templates/readme.md",
  )
  println("                                        # Generate writing plans")
  println("  3. Write docs/ files based on plans   # Manual or LLM")
  println(
    "  4. indexion doc readme --template=.indexion/state/templates/readme.md -o=README.md",
  )
  println("")
  println("Examples:")
  println("  indexion doc init                    # Init in current directory")
  println("  indexion doc init ./myproject        # Init in specific directory")
  println(
    "  indexion doc init --force            # Overwrite existing template",
  )
}

///|
/// Run the doc init command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  let target_dir = @common.normalize_path(config.target_dir)
  // Load KGF registry
  let registry = @registry.KGFRegistry::load_from_dir(config.specs_dir)
  // Detect project type and load info
  let (info, lang_spec) = detect_project_info(target_dir, registry)
  let _ = lang_spec
  if info.name == "project" {
    println("Warning: No project config found. Using defaults.")
  }
  // Create .indexion/ directory structure (isolated from user's docs/)
  let indexion_dir = target_dir + "/.indexion"
  let state_dir = indexion_dir + "/state"
  let templates_dir = state_dir + "/templates"
  // Create directories
  @fs.create_dir(indexion_dir) catch {
    _ => () // Directory may already exist
  }
  @fs.create_dir(state_dir) catch {
    _ => ()
  }
  @fs.create_dir(templates_dir) catch {
    _ => ()
  }
  // Generate only the template file (no placeholder files)
  let files_created : Array[String] = []
  let template_path = templates_dir + "/readme.md"
  if write_file_if_ok(template_path, generate_template(info), config.force) {
    files_created.push(template_path)
  }
  // Summary
  if files_created.length() > 0 {
    println("Created documentation template:")
    for path in files_created {
      println("  " + path)
    }
    println("")
    println("Next steps:")
    println(
      "  1. indexion plan readme --template=.indexion/state/templates/readme.md",
    )
    println("     Generate writing plans for each section")
    println("")
    println("  2. Write docs/ files based on the plans")
    println("")
    println(
      "  3. indexion doc readme --template=.indexion/state/templates/readme.md -o=README.md",
    )
    println("     Assemble README.md from docs/")
  } else {
    println("No files created. Use --force to overwrite existing files.")
  }
}

///|
fn write_file_if_ok(path : String, content : String, force : Bool) -> Bool {
  if not(force) {
    try {
      let _ = @fs.read_file_to_string(path)
      // File exists, skip
      return false
    } catch {
      _ => ()
    }
  }
  try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    _ => false
  }
}

// Project info

///|
priv struct ProjectInfo {
  name : String
  license : String
}

///|
fn ProjectInfo::default() -> ProjectInfo {
  { name: "project", license: "" }
}

///|
/// Detect project type using KGF specs and load project info.
/// Returns (ProjectInfo, Option<KGFSpec>) where spec contains install/build commands.
fn detect_project_info(
  dir : String,
  registry : @registry.KGFRegistry,
) -> (ProjectInfo, @kgf_types.KGFSpec?) {
  // Get all specs and check each project_config
  let specs_map = registry.to_specs_map()
  for lang, spec in specs_map {
    let _ = lang
    let resolver = spec.get_resolver()
    let project_config = resolver.get_project_config()
    if project_config.length() > 0 {
      let config_path = dir + "/" + project_config
      try {
        let content = @fs.read_file_to_string(config_path)
        // Found a matching config file
        let info = parse_config_content(project_config, content)
        if info.name != "project" {
          return (info, Some(spec))
        }
      } catch {
        _ => continue
      }
    }
  }
  (ProjectInfo::default(), None)
}

///|
/// Parse config file content based on filename.
fn parse_config_content(filename : String, content : String) -> ProjectInfo {
  // Currently only JSON-like formats are supported
  // moon.mod.json, package.json use similar structure
  if filename.has_suffix(".json") {
    parse_json_config(content)
  } else {
    // For TOML/other formats, return default (could be extended)
    ProjectInfo::default()
  }
}

///|
fn parse_json_config(content : String) -> ProjectInfo {
  let name = @common.extract_json_string(content, "name")
  let license = @common.extract_json_string(content, "license")
  { name: if name.length() > 0 { name } else { "project" }, license }
}

// extract_json_string: use @common (SoT)

// Template generation

///|
/// Generate .indexion/state/templates/readme.md content.
fn generate_template(info : ProjectInfo) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{{include:docs/intro.md}}\n\n")
  buf.write_string("{{include:docs/overview.md}}\n\n")
  buf.write_string("{{include:docs/getting-started.md}}\n\n")
  buf.write_string("{{include:docs/usage.md}}\n\n")
  buf.write_string("{{include:docs/installation.md}}\n\n")
  buf.write_string("## License\n\n")
  if info.license.length() > 0 {
    buf.write_string(info.license)
    buf.write_string(" - see [LICENSE](LICENSE) for details.\n")
  } else {
    buf.write_string("See [LICENSE](LICENSE) for details.\n")
  }
  buf.to_string()
}

// use @common (SoT) — normalize_path
