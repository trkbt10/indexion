///|
/// # indexion doc init
///
/// Initialize documentation template structure for a project.
///
/// ## Overview
///
/// Generates `docs/` directory with template files based on
/// project metadata and KGF spec configuration.
///
/// ## Generated Structure
///
/// ```
/// docs/
///   intro.md              # Project introduction
///   templates/readme.md   # README template with {{include:...}} and {{packages}}
///   installation.md       # Installation instructions
/// ```
///
/// ## Usage
///
/// ```bash
/// indexion doc init [options] [directory]
/// ```

///|
pub struct InitConfig {
  target_dir : String
  specs_dir : String // KGF specs directory
  force : Bool // overwrite existing files
  show_help : Bool
}

///|
pub fn InitConfig::default() -> InitConfig {
  { target_dir: ".", specs_dir: "kgfs", force: false, show_help: false }
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
pub fn parse_args(args : Array[String], start_idx : Int) -> InitConfig {
  let mut config = InitConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg == "--force" || arg == "-f" {
      config = { ..config, force: true }
    } else if arg.has_prefix("--specs-dir=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, specs_dir: value }
    } else if not(arg.has_prefix("-")) && config.target_dir == "." {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
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
  println("  docs/intro.md              Project introduction")
  println("  docs/templates/readme.md   README template with placeholders")
  println("  docs/installation.md       Installation instructions")
  println("")
  println("After initialization, generate README.md with:")
  println(
    "  indexion doc readme --template=docs/templates/readme.md -o=README.md",
  )
  println("")
  println("Examples:")
  println("  indexion doc init                    # Init in current directory")
  println("  indexion doc init ./myproject        # Init in specific directory")
  println("  indexion doc init --force            # Overwrite existing docs/")
}

///|
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  let target_dir = normalize_path(config.target_dir)
  // Load KGF registry
  let registry = @registry.KGFRegistry::load_from_dir(config.specs_dir)
  // Detect project type and load info
  let (info, lang_spec) = detect_project_info(target_dir, registry)
  if info.name == "project" {
    println("Warning: No project config found. Using defaults.")
  }
  // Create docs/ directory structure
  let docs_dir = target_dir + "/docs"
  let templates_dir = docs_dir + "/templates"
  // Create directories
  @fs.create_dir(docs_dir) catch {
    _ => () // Directory may already exist
  }
  @fs.create_dir(templates_dir) catch {
    _ => ()
  }
  // Generate and write files
  let files_created : Array[String] = []
  // 1. docs/intro.md
  let intro_path = docs_dir + "/intro.md"
  if write_file_if_ok(intro_path, generate_intro(info), config.force) {
    files_created.push(intro_path)
  }
  // 2. docs/installation.md
  let install_path = docs_dir + "/installation.md"
  if write_file_if_ok(
      install_path,
      generate_installation(info, lang_spec),
      config.force,
    ) {
    files_created.push(install_path)
  }
  // 3. docs/templates/readme.md
  let template_path = templates_dir + "/readme.md"
  if write_file_if_ok(template_path, generate_template(), config.force) {
    files_created.push(template_path)
  }
  // Summary
  if files_created.length() > 0 {
    println("Created documentation templates:")
    for path in files_created {
      println("  " + path)
    }
    println("")
    println("Generate README.md with:")
    println(
      "  indexion doc readme --template=docs/templates/readme.md -o=README.md",
    )
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
  _version : String
  description : String
  repository : String
  _license : String
  keywords : Array[String]
}

///|
fn ProjectInfo::default() -> ProjectInfo {
  {
    name: "project",
    _version: "0.0.0",
    description: "",
    repository: "",
    _license: "",
    keywords: [],
  }
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
  let mut info = ProjectInfo::default()
  info = { ..info, name: extract_json_string(content, "name") }
  info = { ..info, _version: extract_json_string(content, "version") }
  info = { ..info, description: extract_json_string(content, "description") }
  info = { ..info, repository: extract_json_string(content, "repository") }
  info = { ..info, _license: extract_json_string(content, "license") }
  info = { ..info, keywords: extract_json_array(content, "keywords") }
  info
}

///|
fn extract_json_string(json : String, key : String) -> String {
  let pattern = "\"" + key + "\":"
  let chars = json.to_array()
  let pat_chars = pattern.to_array()
  let mut start = -1
  for i = 0; i < chars.length() - pat_chars.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < pat_chars.length(); j = j + 1 {
      if chars[i + j] != pat_chars[j] {
        found = false
        break
      }
    }
    if found {
      start = i + pat_chars.length()
      break
    }
  }
  if start < 0 {
    return ""
  }
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  if start >= chars.length() || chars[start] != '"' {
    return ""
  }
  start = start + 1
  let result : Array[Char] = []
  while start < chars.length() && chars[start] != '"' {
    if chars[start] == '\\' && start + 1 < chars.length() {
      start = start + 1
    }
    result.push(chars[start])
    start = start + 1
  }
  String::from_array(result)
}

///|
fn extract_json_array(json : String, key : String) -> Array[String] {
  let result : Array[String] = []
  let pattern = "\"" + key + "\":"
  let chars = json.to_array()
  let pat_chars = pattern.to_array()
  let mut start = -1
  for i = 0; i < chars.length() - pat_chars.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < pat_chars.length(); j = j + 1 {
      if chars[i + j] != pat_chars[j] {
        found = false
        break
      }
    }
    if found {
      start = i + pat_chars.length()
      break
    }
  }
  if start < 0 {
    return result
  }
  while start < chars.length() && chars[start] != '[' {
    start = start + 1
  }
  if start >= chars.length() {
    return result
  }
  start = start + 1
  while start < chars.length() && chars[start] != ']' {
    while start < chars.length() &&
          (
            chars[start] == ' ' ||
            chars[start] == '\t' ||
            chars[start] == '\n' ||
            chars[start] == ','
          ) {
      start = start + 1
    }
    if start >= chars.length() || chars[start] == ']' {
      break
    }
    if chars[start] == '"' {
      start = start + 1
      let item : Array[Char] = []
      while start < chars.length() && chars[start] != '"' {
        item.push(chars[start])
        start = start + 1
      }
      if item.length() > 0 {
        result.push(String::from_array(item))
      }
      start = start + 1
    } else {
      start = start + 1
    }
  }
  result
}

// Template generation

///|
/// Generate docs/intro.md content.
fn generate_intro(info : ProjectInfo) -> String {
  let buf = StringBuilder::new()
  // Title
  buf.write_string("# ")
  buf.write_string(info.name)
  buf.write_string("\n\n")
  // Description
  if info.description.length() > 0 {
    buf.write_string(info.description)
    buf.write_string("\n\n")
  } else {
    buf.write_string("<!-- Add project description here -->\n\n")
  }
  // Features from keywords
  if info.keywords.length() > 0 {
    buf.write_string("## Features\n\n")
    for kw in info.keywords {
      buf.write_string("- **")
      buf.write_string(capitalize(kw))
      buf.write_string("**\n")
    }
    buf.write_string("\n")
  } else {
    buf.write_string("## Features\n\n")
    buf.write_string("- Feature 1\n")
    buf.write_string("- Feature 2\n")
    buf.write_string("- Feature 3\n\n")
  }
  buf.to_string()
}

///|
/// Generate docs/installation.md content using KGF spec commands.
fn generate_installation(
  info : ProjectInfo,
  spec : @kgf_types.KGFSpec?,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("## Installation\n\n")
  // Get commands from KGF spec
  let (install_cmd, build_cmd) = match spec {
    Some(s) => {
      let resolver = s.get_resolver()
      (resolver.get_install_cmd(), resolver.get_build_cmd())
    }
    None => ("", "")
  }
  // From package manager
  buf.write_string("### From Package Manager\n\n")
  buf.write_string("```bash\n")
  if install_cmd.length() > 0 {
    // Replace {name} placeholder with actual name
    buf.write_string(replace_placeholder(install_cmd, "{name}", info.name))
  } else {
    buf.write_string("# Install ")
    buf.write_string(info.name)
  }
  buf.write_string("\n```\n\n")
  // From source
  buf.write_string("### From Source\n\n")
  buf.write_string("```bash\n")
  if info.repository.length() > 0 {
    buf.write_string("git clone ")
    buf.write_string(info.repository)
    buf.write_string("\n")
  } else {
    buf.write_string("git clone https://github.com/user/")
    buf.write_string(extract_project_name(info.name))
    buf.write_string("\n")
  }
  buf.write_string("cd ")
  buf.write_string(extract_project_name(info.name))
  buf.write_string("\n")
  if build_cmd.length() > 0 {
    buf.write_string(build_cmd)
  } else {
    buf.write_string("# Build project")
  }
  buf.write_string("\n```\n\n")
  // Requirements
  buf.write_string("### Requirements\n\n")
  match spec {
    Some(s) =>
      buf.write_string("- " + capitalize(s.get_language()) + " toolchain\n")
    None => buf.write_string("- See project documentation\n")
  }
  buf.to_string()
}

///|
/// Generate docs/templates/readme.md content.
fn generate_template() -> String {
  let buf = StringBuilder::new()
  buf.write_string("{{include:docs/intro.md}}\n\n")
  buf.write_string("## Overview\n\n")
  buf.write_string("{{module_doc}}\n\n")
  buf.write_string("{{include:docs/installation.md}}\n\n")
  buf.write_string("## License\n\n")
  buf.write_string("<!-- Add license information here -->\n")
  buf.to_string()
}

// Utilities

///|
fn normalize_path(path : String) -> String {
  if path.has_suffix("/") {
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
fn capitalize(s : String) -> String {
  let chars = s.to_array()
  if chars.length() == 0 {
    return s
  }
  let first = chars[0]
  if first >= 'a' && first <= 'z' {
    chars[0] = (first.to_int() - 32).unsafe_to_char()
  }
  String::from_array(chars)
}

///|
fn extract_project_name(full_name : String) -> String {
  // Extract "project" from "user/project"
  let chars = full_name.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 && last_slash + 1 < chars.length() {
    let result : Array[Char] = []
    for i = last_slash + 1; i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    full_name
  }
}

///|
fn replace_placeholder(
  template : String,
  placeholder : String,
  value : String,
) -> String {
  let chars = template.to_array()
  let ph_chars = placeholder.to_array()
  let result : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    let mut found = false
    if i + ph_chars.length() <= chars.length() {
      found = true
      for j = 0; j < ph_chars.length(); j = j + 1 {
        if chars[i + j] != ph_chars[j] {
          found = false
          break
        }
      }
    }
    if found {
      for c in value {
        result.push(c)
      }
      i = i + ph_chars.length()
    } else {
      result.push(chars[i])
      i = i + 1
    }
  }
  String::from_array(result)
}
