///|
/// # indexion plan readme
///
/// Generate README documentation writing plans from a template.
///
/// ## Usage
///
/// ```bash
/// indexion plan readme [options] [directory]
/// ```
///
/// ## Options
///
/// | Option | Description | Default |
/// |--------|-------------|---------|
/// | `--template=FILE` | Template file with {{include:...}} placeholders | required |
/// | `--plans-dir=DIR` | Output directory for plans | .indexion/plans |
/// | `--output=FILE`, `-o=` | Output summary file path | stdout |
/// | `--format=FORMAT` | Output format: markdown, json | markdown |

///|
/// Configuration for plan readme command.
pub struct ReadmePlanConfig {
  target_dir : String
  output : String
  format : String // "markdown", "json"
  specs_dir : String // KGF specs directory
  template : String // Template file to analyze for {{include:...}}
  plans_dir : String // Output directory for plan files (default: .plans)
  show_help : Bool
}

///|
/// Create default ReadmePlanConfig.
pub fn ReadmePlanConfig::default() -> ReadmePlanConfig {
  {
    target_dir: ".",
    output: "",
    format: "markdown",
    specs_dir: "kgfs",
    template: "",
    plans_dir: ".indexion/plans",
    show_help: false,
  }
}

// use @common (SoT)

///|
/// Parse command line arguments into ReadmePlanConfig.
pub fn parse_args(args : Array[String], start_idx : Int) -> ReadmePlanConfig {
  let mut config = ReadmePlanConfig::default()
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--output=") || arg.has_prefix("-o=") {
      let prefix_len = if arg.has_prefix("--output=") { 9 } else { 3 }
      let value = @common.get_arg_value(arg, prefix_len)
      config = { ..config, output: value }
    } else if arg.has_prefix("--format=") {
      let value = @common.get_arg_value(arg, 9)
      config = { ..config, format: value }
    } else if arg.has_prefix("--specs-dir=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, specs_dir: value }
    } else if arg.has_prefix("--template=") {
      let value = @common.get_arg_value(arg, 11)
      config = { ..config, template: value }
    } else if arg.has_prefix("--plans-dir=") {
      let value = @common.get_arg_value(arg, 12)
      config = { ..config, plans_dir: value }
    } else if not(arg.has_prefix("-")) && config.target_dir == "." {
      config = { ..config, target_dir: arg }
    }
  }
  config
}

///|
/// Display help message for plan readme command.
pub fn show_help() -> Unit {
  println("indexion plan readme - Generate README documentation writing plans")
  println("")
  println("Usage:")
  println("  indexion plan readme --template=FILE [options] [directory]")
  println("")
  println("Options:")
  println(
    "  --template=FILE      Template file with {{include:...}} placeholders (required)",
  )
  println(
    "  --plans-dir=DIR      Output directory for plans (default: .indexion/plans)",
  )
  println("  --output=FILE, -o=   Output summary file path (default: stdout)")
  println(
    "  --format=FORMAT      Output format: markdown, json (default: markdown)",
  )
  println("  --specs-dir=DIR      KGF specs directory (default: kgfs)")
  println("  --help               Show this help message")
  println("")
  println("Output:")
  println(
    "  For each {{include:docs/foo.md}} in template, generates .indexion/plans/foo.md",
  )
  println("  with project analysis and writing guidance.")
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
  println(
    "  indexion plan readme --template=.indexion/state/templates/readme.md",
  )
  println(
    "  indexion plan readme --template=.indexion/state/templates/readme.md --plans-dir=plans/",
  )
}

///|
/// Run the plan readme command with given arguments.
pub fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help {
    show_help()
    return
  }
  // Template is required for plan generation
  if config.template.length() == 0 {
    println("Error: --template=FILE is required.")
    println("")
    show_help()
    return
  }
  let target_dir = @common.normalize_path(config.target_dir)
  // Load KGF registry for ignore patterns
  let registry = load_registry_from_paths(config.specs_dir, target_dir)
  // Detect project type and get spec
  let (project_info, lang_spec) = detect_project_with_kgf(target_dir, registry)
  // Read template and extract include paths
  let template_content = @fs.read_file_to_string(config.template) catch {
    e => {
      println("Error reading template: " + e.to_string())
      return
    }
  }
  let include_paths = extract_include_paths(template_content)
  if include_paths.length() == 0 {
    println(
      "Warning: No {{include:...}} placeholders found in template. Nothing to plan.",
    )
    return
  }
  // Discover packages for context
  let packages = discover_packages(target_dir, lang_spec, Some(registry))
  // Discover existing documentation files
  let existing_docs = discover_existing_docs(target_dir, lang_spec)
  // Create plans directory
  let plans_dir = target_dir + "/" + config.plans_dir
  create_dir_recursive(plans_dir)
  // Generate a plan file for each include path
  let plans_created : Array[String] = []
  for include_path in include_paths {
    let plan_filename = get_plan_filename(include_path)
    let plan_path = plans_dir + "/" + plan_filename
    let plan_content = generate_writing_plan(
      include_path, project_info, packages, existing_docs, target_dir,
    )
    try {
      @fs.write_string_to_file(plan_path, plan_content)
      plans_created.push(plan_path)
    } catch {
      e => println("Error writing plan: " + e.to_string())
    }
  }
  // Render summary output
  let output_content = match config.format {
    "json" =>
      render_plans_json(include_paths, plans_created, project_info, plans_dir)
    _ =>
      render_plans_markdown(
        include_paths, plans_created, project_info, plans_dir, target_dir,
      )
  }
  // Output summary
  if config.output.length() > 0 {
    try {
      @fs.write_string_to_file(config.output, output_content)
      println("README plan summary written to: " + config.output)
    } catch {
      e => println("Error writing file: " + e.to_string())
    }
  } else {
    println(output_content)
  }
}

// Project info

///|
priv struct ProjectInfo {
  name : String
  description : String
}

///|
fn ProjectInfo::default() -> ProjectInfo {
  { name: "project", description: "" }
}

///|
/// Load KGF registry using the centralized kgfs directory resolution.
/// Uses @kgf_features.load_registry() which delegates to the config SoT.
fn load_registry_from_paths(
  specs_dir : String,
  target_dir : String,
) -> @kgf_registry.KGFRegistry {
  // Use SoT: explicit path takes priority if not default
  let explicit = if specs_dir != "kgfs" { specs_dir } else { "" }
  match @kgf_features.load_registry(explicit_path=explicit, target_dir~) {
    Some(reg) => reg
    None => @kgf_registry.KGFRegistry::new()
  }
}

///|
/// Detect project type using KGF specs and return both info and spec.
fn detect_project_with_kgf(
  dir : String,
  registry : @kgf_registry.KGFRegistry,
) -> (ProjectInfo, @kgf_types.KGFSpec?) {
  let specs_map = registry.to_specs_map()
  for lang, spec in specs_map {
    let _ = lang
    let resolver = spec.get_resolver()
    let project_config = resolver.get_project_config()
    if project_config.length() > 0 {
      let config_path = dir + "/" + project_config
      try {
        let content = @fs.read_file_to_string(config_path)
        let info = parse_project_config(project_config, content)
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
fn parse_project_config(filename : String, content : String) -> ProjectInfo {
  if filename.has_suffix(".json") {
    let name = @common.extract_json_string(content, "name")
    let description = @common.extract_json_string(content, "description")
    { name: if name.length() > 0 { name } else { "project" }, description }
  } else {
    ProjectInfo::default()
  }
}

// extract_json_string: use @common (SoT)

// Package discovery

///|
priv struct PackageInfo {
  path : String
  pub_items : Int
}

///|
/// Existing documentation file info.
priv struct ExistingDoc {
  path : String // relative path
  title : String // extracted from first heading
}

///|
/// Discover existing documentation files (README.md, *.md).
fn discover_existing_docs(
  dir : String,
  spec : @kgf_types.KGFSpec?,
) -> Array[ExistingDoc] {
  let docs : Array[ExistingDoc] = []
  let mut filter_config = @filter.FilterConfig::from_project_root(dir)
  match spec {
    Some(s) =>
      match s.get_ignore() {
        Some(ignore_patterns) =>
          if ignore_patterns.length() > 0 {
            filter_config = filter_config.with_kgf_ignore(
              ignore_patterns,
              s.get_language(),
            )
          }
        None => ()
      }
    None => ()
  }
  discover_docs_recursive(dir, dir, docs, filter_config)
  docs
}

///|
fn discover_docs_recursive(
  base_dir : String,
  current_dir : String,
  docs : Array[ExistingDoc],
  filter_config : @filter.FilterConfig,
) -> Unit {
  let entries = @fs.read_dir(current_dir) catch { _ => return }
  // Load nested .gitignore if present
  let local_config = filter_config.with_gitignore_from_dir(current_dir)
  for entry in entries {
    let full_path = current_dir + "/" + entry
    if entry.has_suffix(".md") && not(@common.is_directory(full_path)) {
      let rel_path = @common.make_relative_path(full_path, base_dir)
      let title = extract_doc_title(full_path)
      docs.push({ path: rel_path, title })
    } else if @common.is_directory(full_path) {
      if not(local_config.should_skip_dir(entry)) {
        discover_docs_recursive(base_dir, full_path, docs, local_config)
      }
    }
  }
}

///|
/// Extract title from first heading in markdown file.
fn extract_doc_title(path : String) -> String {
  let content = @fs.read_file_to_string(path) catch { _ => return "" }
  let lines = @common.split_lines(content)
  for line in lines {
    let trimmed = @common.trim_ascii_spaces(line)
    if trimmed.has_prefix("# ") {
      // Extract title after "# "
      let chars = trimmed.to_array()
      let result : Array[Char] = []
      for i = 2; i < chars.length(); i = i + 1 {
        result.push(chars[i])
      }
      return String::from_array(result)
    }
  }
  ""
}

///|
fn discover_packages(
  dir : String,
  spec : @kgf_types.KGFSpec?,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[PackageInfo] {
  let packages : Array[PackageInfo] = []
  let mut filter_config = @filter.FilterConfig::from_project_root(dir)
  // Add KGF ignore patterns if spec is available
  match spec {
    Some(s) =>
      match s.get_ignore() {
        Some(ignore_patterns) =>
          if ignore_patterns.length() > 0 {
            filter_config = filter_config.with_kgf_ignore(
              ignore_patterns,
              s.get_language(),
            )
          }
        None => ()
      }
    None => ()
  }
  discover_packages_recursive(dir, dir, packages, filter_config, registry)
  packages
}

///|
fn discover_packages_recursive(
  base_dir : String,
  current_dir : String,
  packages : Array[PackageInfo],
  filter_config : @filter.FilterConfig,
  registry : @kgf_registry.KGFRegistry?,
) -> Unit {
  let entries = @fs.read_dir(current_dir) catch { _ => return }
  // Load nested .gitignore if present
  let local_config = filter_config.with_gitignore_from_dir(current_dir)
  // Check if this directory has .mbt files (is a package)
  let mut has_mbt_files = false
  let mut pub_count = 0
  for entry in entries {
    if entry.has_suffix(".mbt") && not(entry.has_suffix("_wbtest.mbt")) {
      has_mbt_files = true
      let file_path = current_dir + "/" + entry
      let content = @fs.read_file_to_string(file_path) catch { _ => continue }
      pub_count = pub_count +
        @kgf_features.count_pub_declarations(content, file_path, registry)
    }
  }
  if has_mbt_files && pub_count > 0 {
    let rel_path = @common.make_relative_path(current_dir, base_dir)
    packages.push({ path: rel_path, pub_items: pub_count })
  }
  // Recurse into subdirectories
  for entry in entries {
    let full_path = current_dir + "/" + entry
    if @common.is_directory(full_path) {
      // Use filter to skip excluded directories
      if not(local_config.should_skip_dir(entry)) {
        discover_packages_recursive(
          base_dir, full_path, packages, local_config, registry,
        )
      }
    }
  }
}

// count_pub_items: replaced by @kgf_features.count_pub_declarations (SoT, language-agnostic)

// use @common (SoT) — is_directory

// Rendering

///|
fn get_current_date() -> String {
  "2026-03-06"
}

///|
fn escape_json(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    if c == '"' {
      result.push('\\')
      result.push('"')
    } else if c == '\\' {
      result.push('\\')
      result.push('\\')
    } else if c == '\n' {
      result.push('\\')
      result.push('n')
    } else {
      result.push(c)
    }
  }
  String::from_array(result)
}

// Template parsing and plan generation

///|
/// Extract all {{include:...}} paths from template content.
fn extract_include_paths(template : String) -> Array[String] {
  let paths : Array[String] = []
  let chars = template.to_array()
  let mut i = 0
  while i < chars.length() {
    // Look for {{include:
    if i + 10 < chars.length() &&
      chars[i] == '{' &&
      chars[i + 1] == '{' &&
      chars[i + 2] == 'i' &&
      chars[i + 3] == 'n' &&
      chars[i + 4] == 'c' &&
      chars[i + 5] == 'l' &&
      chars[i + 6] == 'u' &&
      chars[i + 7] == 'd' &&
      chars[i + 8] == 'e' &&
      chars[i + 9] == ':' {
      let start = i + 10
      let mut end = start
      // Find closing }}
      while end + 1 < chars.length() &&
            not(chars[end] == '}' && chars[end + 1] == '}') {
        end = end + 1
      }
      if end > start {
        let path_chars : Array[Char] = []
        for j = start; j < end; j = j + 1 {
          path_chars.push(chars[j])
        }
        paths.push(String::from_array(path_chars))
      }
      i = end + 2
    } else {
      i = i + 1
    }
  }
  paths
}

///|
/// Convert include path to plan filename.
/// e.g., "docs/overview.md" -> "overview.md"
fn get_plan_filename(include_path : String) -> String {
  let chars = include_path.to_array()
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
    include_path
  }
}

///|
/// Create directory recursively.
fn create_dir_recursive(path : String) -> Unit {
  // Split path and create each part
  let parts = @common.split_by_slash(path)
  let mut current = ""
  for part in parts {
    current = if current.length() == 0 {
      if path.has_prefix("/") {
        "/" + part
      } else {
        part
      }
    } else {
      current + "/" + part
    }
    @fs.create_dir(current) catch {
      _ => () // May already exist
    }
  }
}

// split_path: use @common.split_by_slash (SoT)

///|
/// Generate writing plan content for a specific include path.
fn generate_writing_plan(
  include_path : String,
  project : ProjectInfo,
  packages : Array[PackageInfo],
  existing_docs : Array[ExistingDoc],
  target_dir : String,
) -> String {
  let buf = StringBuilder::new()
  // Header
  buf.write_string("# ")
  buf.write_string(include_path)
  buf.write_string(" Writing Plan\n\n")
  // Target file info
  buf.write_string("## Target File\n\n")
  buf.write_string("- **Path**: `")
  buf.write_string(include_path)
  buf.write_string("`\n")
  // Check if file exists
  let full_path = target_dir + "/" + include_path
  let exists = try {
    let _ = @fs.read_file_to_string(full_path)
    true
  } catch {
    _ => false
  }
  buf.write_string("- **Status**: ")
  buf.write_string(if exists { "Exists (update)" } else { "Not created yet" })
  buf.write_string("\n\n")
  // Section guidance based on filename
  let section_guide = get_section_guidance(include_path)
  buf.write_string("## Writing Guidance\n\n")
  buf.write_string(section_guide)
  buf.write_string("\n\n")
  // Project analysis
  buf.write_string("## Project Analysis\n\n")
  buf.write_string("### Project Info\n\n")
  buf.write_string("- **Name**: ")
  buf.write_string(project.name)
  buf.write_string("\n")
  if project.description.length() > 0 {
    buf.write_string("- **Description**: ")
    buf.write_string(project.description)
    buf.write_string("\n")
  }
  buf.write_string("\n")
  // Core packages
  if packages.length() > 0 {
    buf.write_string("### Core Packages\n\n")
    buf.write_string("| Package | Pub Items |\n")
    buf.write_string("|---------|----------|\n")
    let mut count = 0
    for pkg in packages {
      if pkg.path != "." && count < 15 {
        buf.write_string("| `")
        buf.write_string(pkg.path)
        buf.write_string("` | ")
        buf.write_string(pkg.pub_items.to_string())
        buf.write_string(" |\n")
        count = count + 1
      }
    }
    if packages.length() > 15 {
      buf.write_string("| ... | (")
      buf.write_string((packages.length() - 15).to_string())
      buf.write_string(" more) |\n")
    }
    buf.write_string("\n")
  }
  // Related existing docs
  if existing_docs.length() > 0 {
    buf.write_string("### Related Documentation\n\n")
    buf.write_string(
      "These existing files may provide context or can be referenced:\n\n",
    )
    for doc in existing_docs {
      buf.write_string("- `")
      buf.write_string(doc.path)
      buf.write_string("`")
      if doc.title.length() > 0 {
        buf.write_string(" - ")
        buf.write_string(doc.title)
      }
      buf.write_string("\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Get section-specific writing guidance based on filename.
fn get_section_guidance(include_path : String) -> String {
  let filename = get_plan_filename(include_path).to_lower()
  if filename.has_prefix("intro") || filename.has_prefix("introduction") {
    "Write a compelling introduction:\n- Project name and tagline\n- What problem does it solve?\n- Key benefits (2-3 bullet points)\n- Who is the target audience?"
  } else if filename.has_prefix("overview") {
    "Write a technical overview:\n- High-level architecture description\n- Core concepts and terminology\n- How components interact\n- Design principles or philosophy"
  } else if filename.has_prefix("getting-started") ||
    filename.has_prefix("quickstart") {
    "Write a quick start guide:\n- Prerequisites (minimal)\n- Installation command(s)\n- First working example (copy-paste ready)\n- Expected output"
  } else if filename.has_prefix("install") {
    "Write installation instructions:\n- Package manager installation\n- Building from source\n- System requirements\n- Verifying installation"
  } else if filename.has_prefix("usage") {
    "Write usage documentation:\n- Common use cases with examples\n- CLI commands or API methods\n- Configuration options\n- Best practices"
  } else if filename.has_prefix("api") {
    "Write API documentation:\n- Key types and interfaces\n- Function signatures with descriptions\n- Parameter explanations\n- Return values and errors"
  } else if filename.has_prefix("config") {
    "Write configuration documentation:\n- Configuration file format\n- Available options with defaults\n- Environment variables\n- Example configurations"
  } else {
    "Write clear, concise documentation:\n- Focus on practical information\n- Include code examples where helpful\n- Link to related sections\n- Keep paragraphs short"
  }
}

///|
/// Render summary in markdown format.
fn render_plans_markdown(
  include_paths : Array[String],
  plans_created : Array[String],
  project : ProjectInfo,
  plans_dir : String,
  target_dir : String,
) -> String {
  let buf = StringBuilder::new()
  let date = get_current_date()
  // Header
  buf.write_string("# ")
  buf.write_string(project.name)
  buf.write_string(" README Writing Plans\n\n")
  buf.write_string("**Generated**: ")
  buf.write_string(date)
  buf.write_string("\n\n")
  // Plans summary
  buf.write_string("## Generated Plans\n\n")
  buf.write_string("| Target File | Plan | Status |\n")
  buf.write_string("|-------------|------|--------|\n")
  for i, include_path in include_paths {
    let full_path = target_dir + "/" + include_path
    let exists = try {
      let _ = @fs.read_file_to_string(full_path)
      true
    } catch {
      _ => false
    }
    buf.write_string("| `")
    buf.write_string(include_path)
    buf.write_string("` | `")
    if i < plans_created.length() {
      buf.write_string(plans_created[i])
    }
    buf.write_string("` | ")
    buf.write_string(if exists { "Exists" } else { "TODO" })
    buf.write_string(" |\n")
  }
  buf.write_string("\n")
  // Workflow
  buf.write_string("## Next Steps\n\n")
  buf.write_string("1. Review the writing plans in `")
  buf.write_string(plans_dir)
  buf.write_string("/`\n")
  buf.write_string("2. Create/update each target file based on its plan\n")
  buf.write_string(
    "3. Run `indexion doc readme --template=... -o=README.md` to assemble\n",
  )
  buf.to_string()
}

///|
/// Render summary in JSON format.
fn render_plans_json(
  include_paths : Array[String],
  plans_created : Array[String],
  project : ProjectInfo,
  plans_dir : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\n")
  buf.write_string("  \"project\": \"")
  buf.write_string(escape_json(project.name))
  buf.write_string("\",\n")
  buf.write_string("  \"date\": \"")
  buf.write_string(get_current_date())
  buf.write_string("\",\n")
  buf.write_string("  \"plans_dir\": \"")
  buf.write_string(escape_json(plans_dir))
  buf.write_string("\",\n")
  buf.write_string("  \"plans\": [\n")
  for i, include_path in include_paths {
    buf.write_string("    {\n")
    buf.write_string("      \"target\": \"")
    buf.write_string(escape_json(include_path))
    buf.write_string("\",\n")
    buf.write_string("      \"plan\": \"")
    if i < plans_created.length() {
      buf.write_string(escape_json(plans_created[i]))
    }
    buf.write_string("\"\n")
    buf.write_string("    }")
    if i < include_paths.length() - 1 {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  buf.write_string("  ]\n")
  buf.write_string("}\n")
  buf.to_string()
}

// Utilities

// use @common (SoT) — normalize_path

// use @common (SoT) — trim_str → @common.trim_ascii_spaces
