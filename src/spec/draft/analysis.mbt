///|
fn current_epoch_seconds() -> Int {
  (@env.now() / 1000UL).to_int()
}

///|
fn trim(text : String) -> String {
  @common.trim_ascii_spaces(text)
}

///|
fn root_dir_for(path : String) -> String {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if is_dir {
    path
  } else {
    @config.dirname(path)
  }
}

///|
fn path_is_file(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
fn collect_document_paths(
  config : DraftConfig,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  if config.source_path.length() == 0 {
    return []
  }
  let result : Array[String] = []
  if path_is_file(config.source_path) {
    for
      file in @pipeline.load_supported_file_info([config.source_path], registry) {
      if file.content_type == Some("document") {
        result.push(file.path)
      }
    }
    return result
  }
  let root = root_dir_for(config.source_path)
  let opts = @pipeline.DiscoverOptions::new(
    kgf_ignore=registry.collect_ignore_patterns(),
    root_dir=root,
  )
  for
    file in @pipeline.collect_supported_file_info(
      [config.source_path],
      opts,
      registry,
    ) {
    if file.content_type == Some("document") {
      result.push(file.path)
    }
  }
  result
}

///|
fn push_requirement(
  requirements : Array[DraftRequirement],
  title : String,
  description : String,
  criteria : Array[String],
  source_file : String,
  source_line : Int,
  max_requirements : Int,
) -> Unit {
  if requirements.length() >= max_requirements {
    return
  }
  let clean_title = trim(title)
  let clean_description = trim(description)
  if clean_title.length() == 0 {
    return
  }
  if clean_description.length() == 0 && criteria.length() == 0 {
    return
  }
  requirements.push({
    id: "REQ-" + (requirements.length() + 1).to_string(),
    title: clean_title,
    description: clean_description,
    criteria: criteria.copy(),
    source_file,
    source_line,
  })
}

///|
fn collect_section_requirement(
  requirements : Array[DraftRequirement],
  path : String,
  section : @doc_structure.DocumentSection,
  max_requirements : Int,
) -> Unit {
  push_requirement(
    requirements,
    section.title,
    trim(section.content),
    [],
    path,
    section.line,
    max_requirements,
  )
}

///|
fn section_roles_by_line(
  path : String,
  content : String,
  registry : @registry.KGFRegistry,
) -> Map[Int, String] {
  let result : Map[Int, String] = {}
  let language = match registry.detect_from_path(path) {
    Some(value) => value
    None => return result
  }
  let spec = match registry.get_spec(language) {
    Some(value) => value
    None => return result
  }
  let interpreted = @doc_structure.interpret_document(content, path, spec)
  for fact in interpreted.facts {
    if fact.kind != "document_section_role" {
      continue
    }
    let line = match fact.payload.get("line") {
      Some(Number(value, ..)) => value.to_int()
      Some(String(value)) => @common.parse_int(value)
      _ => 0
    }
    let role = match fact.payload.get("role") {
      Some(String(value)) => value
      _ => ""
    }
    if line > 0 && role.length() > 0 {
      result[line] = role
    }
  }
  result
}

///|
fn should_include_section_role(role : String) -> Bool {
  match role {
    "" | "requirement" => true
    "summary" => true
    _ => false
  }
}

///|
fn collect_requirements_from_file(
  requirements : Array[DraftRequirement],
  path : String,
  content : String,
  registry : @registry.KGFRegistry,
  max_requirements : Int,
) -> Unit {
  let roles = section_roles_by_line(path, content, registry)
  let sections = @doc_structure.load_document_sections(
    content,
    path,
    Some(registry),
  )
  if sections.length() == 0 {
    return
  }
  for section in sections {
    let role = roles.get(section.line).unwrap_or("")
    if !should_include_section_role(role) {
      continue
    }
    collect_section_requirement(requirements, path, section, max_requirements)
    if requirements.length() >= max_requirements {
      return
    }
  }
}

///|
fn build_report(config : DraftConfig) -> DraftReport? {
  let root = root_dir_for(config.source_path)
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir=root,
  )
  let source_files = collect_document_paths(config, registry)
  if source_files.length() == 0 {
    return None
  }
  let requirements : Array[DraftRequirement] = []
  for path in source_files {
    let content = @fs.read_file_to_string(path) catch { _ => continue }
    collect_requirements_from_file(
      requirements,
      path,
      content,
      registry,
      config.max_requirements,
    )
    if requirements.length() >= config.max_requirements {
      break
    }
  }
  if requirements.length() == 0 {
    return None
  }
  Some({
    version: "spec-draft-v1",
    generated_at: current_epoch_seconds(),
    config,
    source_files,
    requirements,
  })
}

///|
fn render_markdown(report : DraftReport) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# SDD Draft\n\n")
  buf.write_string("Generated from:\n")
  for path in report.source_files {
    buf.write_string("- `")
    buf.write_string(path)
    buf.write_string("`\n")
  }
  buf.write_string("\n")
  for requirement in report.requirements {
    buf.write_string("## Requirement ")
    buf.write_string(
      @common.substring(requirement.id, 4, requirement.id.length()),
    )
    buf.write_string(": ")
    buf.write_string(requirement.title)
    buf.write_string("\n")
    if requirement.description.length() > 0 {
      buf.write_string(requirement.description)
      buf.write_string("\n")
    }
    if requirement.criteria.length() > 0 {
      buf.write_string("\n### Acceptance Criteria\n")
      for item in requirement.criteria {
        buf.write_string("- ")
        buf.write_string(item)
        buf.write_string("\n")
      }
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn render_json(report : DraftReport) -> String {
  report.to_json().stringify(indent=2)
}

///|
pub fn render_report(report : DraftReport, format : String) -> String {
  match format {
    "json" => render_json(report)
    _ => render_markdown(report)
  }
}

///|
pub fn run_to_string(config : DraftConfig) -> String? {
  match build_report(config) {
    Some(report) => Some(render_report(report, config.format))
    None => None
  }
}

///|
pub fn report(config : DraftConfig) -> DraftReport? {
  build_report(config)
}
