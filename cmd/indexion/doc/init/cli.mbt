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
/// Directory and file names are derived from SoT constants in
/// `src/config/readme_paths.mbt`. The doc.json content uses
/// `DocConfig::for_init().to_json()` for structural correctness.
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
}

///|
/// Create default InitConfig.
pub fn InitConfig::default() -> InitConfig {
  { target_dir: ".", specs_dir: "kgfs", force: false }
}

///|
/// Create InitConfig from argparse matches.
pub fn InitConfig::from_matches(matches : @argparse.Matches) -> InitConfig {
  let target_dir = match matches.values.get("directory") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "." }
    _ => "."
  }
  let specs_dir = match matches.values.get("specs-dir") {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "kgfs" }
    _ => "kgfs"
  }
  let force = matches.flags.get("force").unwrap_or(false)
  { target_dir, specs_dir, force }
}

///|
/// Define the init command for argparse.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "init",
    about="Initialize documentation template structure",
    options=[
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    flags=[
      @argparse.FlagArg("force", short='f', about="Overwrite existing files"),
    ],
    positionals=[
      @argparse.PositionArg(
        "directory",
        num_args=@argparse.ValueRange(lower=0, upper=1),
        about="Target directory",
      ),
    ],
  )
}

///|
/// Run the doc init command from argparse matches.
pub fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = InitConfig::from_matches(matches)
  let target_dir = @common.normalize_path(config.target_dir)
  // Load KGF registry
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir~,
  )
  // Detect project type and load info
  let (info, lang_spec) = detect_project_info(target_dir, registry)
  let _ = lang_spec
  if info.name == "project" {
    println("Warning: No project config found. Using defaults.")
  }
  // Create .indexion/ directory structure (isolated from user's docs/)
  let indexion_dir = target_dir + "/.indexion"
  let the_readme_dir = @config.readme_dir(indexion_dir)
  let the_docs_dir = @config.readme_docs_dir(indexion_dir)
  @config.ensure_dir_recursive(the_readme_dir)
  @config.ensure_dir_recursive(the_docs_dir)
  // Generate template and doc.json using SoT paths
  let files_created : Array[String] = []
  let template_path = @config.readme_template_path(indexion_dir)
  if write_file_if_ok(template_path, generate_template(info), config.force) {
    files_created.push(template_path)
  }
  let doc_json_path = @config.readme_doc_config_path(indexion_dir)
  let doc_config = @config.DocConfig::for_init()
  let doc_json_content = doc_config.to_json().stringify(indent=2)
  if write_file_if_ok(doc_json_path, doc_json_content, config.force) {
    files_created.push(doc_json_path)
  }
  // Summary
  if files_created.length() > 0 {
    println("Created documentation template:")
    for path in files_created {
      println("  " + path)
    }
    let template_rel = @config.readme_template_relative()
    let doc_config_rel = @config.readme_doc_config_relative()
    println("")
    println("Next steps:")
    println(
      "  1. Edit " + doc_config_rel + " to configure sections and packages",
    )
    println("")
    println("  2. indexion plan readme --template=" + template_rel)
    println("     Generate writing plans for each section")
    println("")
    println("  3. Write docs/ files based on the plans")
    println("")
    println(
      "  4. indexion doc readme --template=" + template_rel + " -o=README.md",
    )
    println("     Assemble README.md from docs/")
  } else {
    println("No files created. Use --force to overwrite existing files.")
  }
}

///|
fn write_file_if_ok(path : String, content : String, force : Bool) -> Bool {
  if !force {
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
/// Generate README template content with {{include:...}} placeholders.
/// Include paths are relative to the readme directory (.indexion/readme/).
fn generate_template(info : ProjectInfo) -> String {
  let docs = @config.readme_docs_relative()
  let buf = StringBuilder::new()
  buf.write_string("{{include:" + docs + "/intro.md}}\n\n")
  buf.write_string("{{include:" + docs + "/overview.md}}\n\n")
  buf.write_string("{{include:" + docs + "/getting-started.md}}\n\n")
  buf.write_string("{{include:" + docs + "/usage.md}}\n\n")
  buf.write_string("{{include:" + docs + "/installation.md}}\n\n")
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
// use @config (SoT) — readme paths, DocConfig::for_init, ensure_dir_recursive
