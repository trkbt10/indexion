///|
/// doc.json-based README generation.

///|
/// Run README generation using doc.json configuration.
pub fn run_with_doc_config(config_path : String, cli_config : ReadmeConfig) -> Unit {
  log_progress("[1/4] Loading doc.json...")
  let doc_config = match @doc_config.load_doc_config(config_path) {
    Some(cfg) => cfg
    None => {
      println("Error: Could not load config file: " + config_path)
      return
    }
  }
  log_progress("      Loaded " + doc_config.packages.length().to_string() + " package entries")

  // Determine output file
  let output_path = match cli_config.output {
    Some(path) => path
    None => doc_config.root.output
  }

  log_progress("[2/4] Processing root sections...")
  let result = render_root_sections(doc_config)

  log_progress("[3/4] Writing output...")
  write_output(result, Some(output_path), false)

  log_progress("[4/4] Done")
  println("Written to: " + output_path)
}

///|
/// Render all root sections from doc.json configuration.
fn render_root_sections(config : @doc_config.DocConfig) -> String {
  let result = StringBuilder::new()
  for section in config.root.sections {
    let content = render_root_section(section, config)
    if content.length() > 0 {
      if result.to_string().length() > 0 {
        result.write_string("\n")
      }
      result.write_string(content)
    }
  }
  result.to_string()
}

///|
/// Render a single root section.
fn render_root_section(
  section : @doc_config.DocRootSection,
  config : @doc_config.DocConfig,
) -> String {
  match section {
    @doc_config.DocRootSection::Static(file_path) => render_static_section(file_path)
    @doc_config.DocRootSection::Toc(title) => render_toc_section(title, config)
    @doc_config.DocRootSection::Packages(filter) => render_packages_section(filter, config)
  }
}

///|
/// Render a static file section.
fn render_static_section(file_path : String) -> String {
  @fs.read_file_to_string(file_path) catch {
    _ => {
      println("Warning: Could not read file: " + file_path)
      ""
    }
  }
}

///|
/// Render table of contents header only (packages section renders content).
fn render_toc_section(title : String, config : @doc_config.DocConfig) -> String {
  let buf = StringBuilder::new()
  buf.write_string("## ")
  buf.write_string(title)
  buf.write_string("\n")
  let _ = config
  buf.to_string()
}

///|
/// Render packages section with filter.
fn render_packages_section(
  filter : String,
  config : @doc_config.DocConfig,
) -> String {
  let buf = StringBuilder::new()
  let filtered = filter_packages(config.packages, filter)
  for entry in filtered {
    if not(entry.include_in_root) {
      continue
    }
    let content = render_package_entry(entry)
    if content.length() > 0 {
      if buf.to_string().length() > 0 {
        buf.write_string("\n")
      }
      buf.write_string(content)
    }
  }
  buf.to_string()
}

///|
/// Render a single package entry from its README.md.
fn render_package_entry(entry : @doc_config.DocPackageEntry) -> String {
  // Look for README.md in the package directory
  let readme_path = entry.path + "/README.md"
  let readme_content = @fs.read_file_to_string(readme_path) catch {
    _ => return ""
  }
  let buf = StringBuilder::new()
  // Add command heading
  buf.write_string("### `indexion ")
  buf.write_string(entry.title)
  buf.write_string("`\n\n")
  // Extract overview if "overview" is in sections
  if contains_section(entry.sections, "overview") {
    let overview = extract_overview(readme_content)
    if overview.length() > 0 {
      buf.write_string(overview)
      buf.write_string("\n\n")
    }
  }
  // Extract specified sections
  let section_names = filter_section_names(entry.sections, "overview")
  if section_names.length() > 0 {
    let sections = extract_sections(readme_content, section_names)
    if sections.length() > 0 {
      buf.write_string(sections)
      buf.write_string("\n")
    }
  }
  // Add link to full documentation
  buf.write_string("\n[Full documentation](")
  buf.write_string(readme_path)
  buf.write_string(")\n")
  buf.to_string()
}

///|
/// Filter packages by glob pattern.
fn filter_packages(
  packages : Array[@doc_config.DocPackageEntry],
  filter : String,
) -> Array[@doc_config.DocPackageEntry] {
  if filter == "**" || filter == "*" {
    return packages
  }
  let result : Array[@doc_config.DocPackageEntry] = []
  for entry in packages {
    if glob_match_path(filter, entry.path) {
      result.push(entry)
    }
  }
  result
}

///|
/// Simple glob matching for paths.
fn glob_match_path(pattern : String, path : String) -> Bool {
  // Handle "cmd/**" pattern
  if pattern.has_suffix("/**") {
    let prefix = substring_config(pattern, 0, pattern.length() - 3)
    return path.has_prefix(prefix)
  }
  // Handle "cmd/*" pattern
  if pattern.has_suffix("/*") {
    let prefix = substring_config(pattern, 0, pattern.length() - 2)
    if not(path.has_prefix(prefix)) {
      return false
    }
    // Check that there's no additional / after the prefix
    let rest = substring_config(path, prefix.length() + 1, path.length())
    return not(rest.contains("/"))
  }
  // Exact match
  pattern == path
}

///|
fn contains_section(sections : Array[String], name : String) -> Bool {
  for s in sections {
    if s == name {
      return true
    }
  }
  false
}

///|
fn filter_section_names(sections : Array[String], exclude : String) -> Array[String] {
  let result : Array[String] = []
  for s in sections {
    if s != exclude {
      result.push(s)
    }
  }
  result
}

///|
fn substring_config(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  if start >= end || start >= chars.length() {
    return ""
  }
  let actual_end = if end > chars.length() { chars.length() } else { end }
  let result : Array[Char] = []
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}
