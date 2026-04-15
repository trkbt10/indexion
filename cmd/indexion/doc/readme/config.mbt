///|
/// doc.json-based README generation using PlanDocument IR.

///|
/// Run README generation using doc.json configuration.
pub fn run_with_doc_config(
  config_path : String,
  cli_config : ReadmeConfig,
) -> Unit {
  log_progress("[1/3] Loading doc.json...")
  let doc_config = match @doc_config.load_doc_config(config_path) {
    Some(cfg) => cfg
    None => {
      println("Error: Could not load config file: " + config_path)
      return
    }
  }
  log_progress(
    "      Loaded " +
    doc_config.packages.length().to_string() +
    " package entries",
  )
  // Compute project root and config directory from config_path.
  // - project_root: for package paths (src/objects → project_root/src/objects)
  // - config_dir: for static file paths (docs/intro.md → config_dir/docs/intro.md)
  let project_root = compute_config_base_dir(config_path)
  let config_dir = @doc_config.dirname(config_path)
  // Determine output file (relative to project root)
  let output_path = if cli_config.output.length() > 0 {
    cli_config.output
  } else {
    @doc_config.resolve_path(project_root, doc_config.root.output)
  }
  log_progress("[2/3] Building document IR...")
  let doc = build_root_document(doc_config, project_root, config_dir)
  let result = @plan_render.render_markdown(doc)
  log_progress("[3/3] Writing output...")
  @common.write_output(output_path, result, label="Readme")
}

///|
/// Compute the project root directory from a doc.json config path.
///
/// Walks up from the config file's parent directory to find a project root
/// using the SoT markers from `@doc_config.find_project_root_from`.
/// Falls back to the config file's parent directory if no marker is found.
fn compute_config_base_dir(config_path : String) -> String {
  let config_dir = @doc_config.dirname(config_path)
  match @doc_config.find_project_root_from(config_dir) {
    Some(root) => root
    None => config_dir
  }
}

///|
/// Build a PlanDocument from doc.json configuration.
/// Static files, TOC headings, and package entries are all represented as IR sections.
/// The base_dir is used to resolve relative paths in the config.
fn build_root_document(
  config : @doc_config.DocConfig,
  _project_root : String,
  config_dir : String,
) -> @plan_types.PlanDocument {
  // First pass: extract title from first static file's # heading
  let title = extract_document_title(config, config_dir)
  let doc = @plan_types.PlanDocument::new(title)
  // Second pass: build sections
  let mut pending_toc_title : String = ""
  let mut has_pending_toc = false
  let mut title_extracted = false
  for section in config.root.sections {
    match section {
      @doc_config.DocRootSection::Static(file_path) => {
        flush_pending_toc(doc, pending_toc_title, has_pending_toc, [])
        has_pending_toc = false
        let resolved_path = @doc_config.resolve_path(config_dir, file_path)
        let content = @fs.read_file_to_string(resolved_path) catch {
          _ => {
            println("Warning: Could not read file: " + resolved_path)
            continue
          }
        }
        let parsed = parse_markdown_to_sections(content)
        for s in parsed {
          // Skip the first heading that became the document title
          if !title_extracted && s.heading == title && s.heading.length() > 0 {
            title_extracted = true
            // Add children of the title section as top-level sections
            match s.content {
              @plan_types.SectionContent::Nested(children) =>
                for child in children {
                  doc.add_section(child)
                }
              _ =>
                if get_section_text(s.content).length() > 0 {
                  doc.add_section(
                    @plan_types.PlanSection::new("", "", s.content),
                  )
                }
            }
          } else {
            doc.add_section(s)
          }
        }
      }
      @doc_config.DocRootSection::Toc(title) => {
        flush_pending_toc(doc, pending_toc_title, has_pending_toc, [])
        pending_toc_title = title
        has_pending_toc = true
      }
      @doc_config.DocRootSection::Packages(filter) => {
        let filtered = filter_packages(config.packages, filter)
        let table = build_package_summary_table(filtered)
        let section = @plan_types.PlanSection::new(
          "packages",
          pending_toc_title,
          @plan_types.SectionContent::text(table),
        )
        if has_pending_toc {
          doc.add_section(section)
          has_pending_toc = false
        } else {
          doc.add_section(section)
        }
      }
    }
  }
  flush_pending_toc(doc, pending_toc_title, has_pending_toc, [])
  doc
}

///|
/// Extract document title from first static file's # heading.
fn extract_document_title(
  config : @doc_config.DocConfig,
  config_dir : String,
) -> String {
  for section in config.root.sections {
    match section {
      @doc_config.DocRootSection::Static(file_path) => {
        let resolved_path = @doc_config.resolve_path(config_dir, file_path)
        let content = @fs.read_file_to_string(resolved_path) catch {
          _ => continue
        }
        let parsed = parse_markdown_to_sections(content)
        for s in parsed {
          if s.heading.length() > 0 {
            return s.heading
          }
        }
      }
      _ => ()
    }
  }
  "README"
}

///|
/// Flush a pending TOC section with optional package children.
fn flush_pending_toc(
  doc : @plan_types.PlanDocument,
  title : String,
  has_pending : Bool,
  children : Array[@plan_types.PlanSection],
) -> Unit {
  if !has_pending {
    return
  }
  if children.length() > 0 {
    doc.add_section(
      @plan_types.PlanSection::new(
        "toc",
        title,
        @plan_types.SectionContent::nested(children),
      ),
    )
  } else {
    doc.add_section(
      @plan_types.PlanSection::new(
        "toc",
        title,
        @plan_types.SectionContent::text(""),
      ),
    )
  }
}

///|
/// Extract children from the first heading section.
/// Package READMEs have `# Title` as root; we want its children for filtering.
fn extract_children_sections(
  sections : Array[@plan_types.PlanSection],
) -> Array[@plan_types.PlanSection] {
  // If there's a single top-level heading with nested children, return those children
  if sections.length() == 1 {
    match sections[0].content {
      @plan_types.SectionContent::Nested(children) => return children
      _ => ()
    }
  }
  // If first section is a heading and has nested children, include anonymous pre-heading
  // text as "overview" and the children
  for section in sections {
    if section.heading.length() > 0 {
      match section.content {
        @plan_types.SectionContent::Nested(children) => return children
        _ => ()
      }
    }
  }
  sections
}

///|
/// Extract text content from SectionContent (for simple sections).
fn get_section_text(content : @plan_types.SectionContent) -> String {
  match content {
    @plan_types.SectionContent::Text(s) => s
    _ => ""
  }
}

///|
/// Build a PlanSection for a package entry from its README.md.
/// Returns None if the README cannot be read.
fn _build_package_section(
  entry : @doc_config.DocPackageEntry,
  base_dir : String,
) -> @plan_types.PlanSection? {
  let resolved_pkg_path = @doc_config.resolve_path(base_dir, entry.path)
  let readme_path = resolved_pkg_path + "/README.md"
  let readme_content = @fs.read_file_to_string(readme_path) catch {
    _ => return None
  }
  // Parse README into IR sections
  let all_sections = parse_markdown_to_sections(readme_content)
  // Package READMEs typically have a # title with children.
  // Extract children from the first heading section for filtering.
  let sections_to_filter = extract_children_sections(all_sections)
  // Filter by requested sections (e.g., ["overview", "usage"])
  let filtered = filter_parsed_sections(sections_to_filter, entry.sections)
  // Add documentation link as last child
  let children : Array[@plan_types.PlanSection] = []
  for s in filtered {
    children.push(s)
  }
  let link_path = entry.path + "/README.md"
  children.push(
    @plan_types.PlanSection::new(
      "link",
      "",
      @plan_types.SectionContent::text(
        "\n[Full documentation](" + link_path + ")",
      ),
    ),
  )
  Some(
    @plan_types.PlanSection::new(
      entry.title,
      "`" + entry.title + "`",
      @plan_types.SectionContent::nested(children),
    ),
  )
}

///|
/// Build a markdown summary table from package entries.
/// Produces a "| Package | Description |" table for README use.
fn build_package_summary_table(
  packages : Array[@doc_config.DocPackageEntry],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("| Package | Description |\n")
  buf.write_string("|---------|-------------|\n")
  for entry in packages {
    if !entry.include_in_root {
      continue
    }
    let link = "[`" + entry.title + "`](" + entry.path + "/README.md)"
    buf.write_string("| " + link + " | " + entry.description + " |\n")
  }
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
    let prefix = @common.substring(pattern, 0, pattern.length() - 3)
    return path.has_prefix(prefix)
  }
  // Handle "cmd/*" pattern
  if pattern.has_suffix("/*") {
    let prefix = @common.substring(pattern, 0, pattern.length() - 2)
    if !path.has_prefix(prefix) {
      return false
    }
    // Check that there's no additional / after the prefix
    let rest = @common.substring(path, prefix.length() + 1, path.length())
    return !rest.contains("/")
  }
  // Exact match
  pattern == path
}
