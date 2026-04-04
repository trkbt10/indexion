///|
/// Configuration for documentation generation from `doc.json`.

///|
/// Root documentation configuration.
pub struct DocConfig {
  version : String
  spec : String
  output : DocOutputConfig
  packages : Array[DocPackageEntry]
  root : DocRootConfig
} derive(Eq, Show)

///|
/// Output format configuration.
pub struct DocOutputConfig {
  format : String
  filename : String
} derive(Eq, Show)

///|
/// Package entry for documentation.
pub struct DocPackageEntry {
  path : String
  title : String
  description : String
  include_in_root : Bool
  sections : Array[String]
} derive(Eq, Show)

///|
/// Root README configuration.
pub struct DocRootConfig {
  template : String
  output : String
  sections : Array[DocRootSection]
} derive(Eq, Show)

///|
/// Section types for root README.
pub enum DocRootSection {
  Static(String)
  Toc(String)
  Packages(String)
} derive(Eq, Show)

///|
/// Create an empty doc config with default values.
pub fn DocConfig::empty() -> DocConfig {
  {
    version: "1.0",
    spec: "",
    output: { format: "markdown", filename: "README.md" },
    packages: [],
    root: { template: "", output: "README.md", sections: [] },
  }
}

///|
/// Load documentation config from JSON file.
pub fn load_doc_config(path : String) -> DocConfig? {
  if path.length() == 0 {
    return None
  }
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  parse_doc_config_json(content)
}

///|
/// Parse doc.json content.
fn parse_doc_config_json(content : String) -> DocConfig? {
  let parsed = @json.parse(content) catch { _ => return None }
  let root : Map[String, Json] = @json.from_json(parsed) catch {
    _ => return None
  }
  let version = match root.get("version") {
    Some(v) => parse_doc_json_string(v).unwrap_or("1.0")
    None => "1.0"
  }
  let spec = match root.get("spec") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => ""
  }
  let output = match root.get("output") {
    Some(v) => parse_doc_output_config(v)
    None => { format: "markdown", filename: "README.md" }
  }
  let packages = match root.get("packages") {
    Some(v) => parse_doc_packages(v)
    None => []
  }
  let root_config = match root.get("root") {
    Some(v) => parse_doc_root_config(v)
    None => { template: "", output: "README.md", sections: [] }
  }
  Some({ version, spec, output, packages, root: root_config })
}

///|
fn parse_doc_output_config(value : Json) -> DocOutputConfig {
  let obj : Map[String, Json] = @json.from_json(value) catch {
    _ => return { format: "markdown", filename: "README.md" }
  }
  let format = match obj.get("format") {
    Some(v) => parse_doc_json_string(v).unwrap_or("markdown")
    None => "markdown"
  }
  let filename = match obj.get("filename") {
    Some(v) => parse_doc_json_string(v).unwrap_or("README.md")
    None => "README.md"
  }
  { format, filename }
}

///|
fn parse_doc_packages(value : Json) -> Array[DocPackageEntry] {
  let arr : Array[Json] = @json.from_json(value) catch { _ => return [] }
  let result : Array[DocPackageEntry] = []
  for item in arr {
    match parse_doc_package_entry(item) {
      Some(entry) => result.push(entry)
      None => ()
    }
  }
  result
}

///|
fn parse_doc_package_entry(value : Json) -> DocPackageEntry? {
  let obj : Map[String, Json] = @json.from_json(value) catch {
    _ => return None
  }
  let path = match obj.get("path") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => return None
  }
  if path.length() == 0 {
    return None
  }
  let title = match obj.get("title") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => ""
  }
  let description = match obj.get("description") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => ""
  }
  let include_in_root = match obj.get("include_in_root") {
    Some(v) => parse_doc_json_bool(v).unwrap_or(false)
    None => false
  }
  let sections = match obj.get("sections") {
    Some(v) => parse_doc_json_string_array(v)
    None => []
  }
  Some({ path, title, description, include_in_root, sections })
}

///|
fn parse_doc_root_config(value : Json) -> DocRootConfig {
  let obj : Map[String, Json] = @json.from_json(value) catch {
    _ => return { template: "", output: "README.md", sections: [] }
  }
  let template = match obj.get("template") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => ""
  }
  let output = match obj.get("output") {
    Some(v) => parse_doc_json_string(v).unwrap_or("README.md")
    None => "README.md"
  }
  let sections = match obj.get("sections") {
    Some(v) => parse_doc_root_sections(v)
    None => []
  }
  { template, output, sections }
}

///|
fn parse_doc_root_sections(value : Json) -> Array[DocRootSection] {
  let arr : Array[Json] = @json.from_json(value) catch { _ => return [] }
  let result : Array[DocRootSection] = []
  for item in arr {
    match parse_doc_root_section(item) {
      Some(section) => result.push(section)
      None => ()
    }
  }
  result
}

///|
fn parse_doc_root_section(value : Json) -> DocRootSection? {
  let obj : Map[String, Json] = @json.from_json(value) catch {
    _ => return None
  }
  let section_type = match obj.get("type") {
    Some(v) => parse_doc_json_string(v).unwrap_or("")
    None => return None
  }
  match section_type {
    "static" => {
      let file = match obj.get("file") {
        Some(v) => parse_doc_json_string(v).unwrap_or("")
        None => return None
      }
      Some(DocRootSection::Static(file))
    }
    "toc" => {
      let title = match obj.get("title") {
        Some(v) => parse_doc_json_string(v).unwrap_or("Contents")
        None => "Contents"
      }
      Some(DocRootSection::Toc(title))
    }
    "packages" => {
      let filter = match obj.get("filter") {
        Some(v) => parse_doc_json_string(v).unwrap_or("**")
        None => "**"
      }
      Some(DocRootSection::Packages(filter))
    }
    _ => None
  }
}

// --- .indexion.toml [doc] section ---

///|
/// Optional values loaded from `.indexion.toml` or `.indexion.json`
/// for the `doc` command group. Points to the doc.json config file.
pub struct DocFileConfig {
  config_path : String?
} derive(Eq, Show)

///|
/// Create an empty doc file config with all fields set to None.
pub fn DocFileConfig::empty() -> DocFileConfig {
  { config_path: None }
}

///|
/// Parse key-value in [doc] section of TOML.
pub fn parse_doc_section_key(
  config : DocFileConfig,
  key : String,
  value : String,
) -> DocFileConfig {
  match key {
    "config_path" => { config_path: Some(trim_quotes(value)) }
    _ => config
  }
}

///|
/// Load DocFileConfig from JSON root object.
pub fn load_doc_from_json_root(root : Map[String, Json]) -> DocFileConfig {
  let doc_json = match root.get("doc") {
    Some(value) => value
    None => return DocFileConfig::empty()
  }
  let doc_obj : Map[String, Json] = @json.from_json(doc_json) catch {
    _ => return DocFileConfig::empty()
  }
  let mut config = DocFileConfig::empty()
  match doc_obj.get("config_path") {
    Some(value) =>
      match parse_doc_json_string(value) {
        Some(v) => if v.length() > 0 { config = { config_path: Some(v) } }
        None => ()
      }
    None => ()
  }
  config
}

///|
/// Merge two DocFileConfigs. Primary takes precedence over fallback.
pub fn merge_doc_configs(
  primary : DocFileConfig,
  fallback : DocFileConfig,
) -> DocFileConfig {
  { config_path: or_opt(primary.config_path, fallback.config_path) }
}

///|
/// Load merged doc config from project + global config files.
pub fn load_effective_doc_config(project_config_path : String) -> DocFileConfig {
  let project = load_project_config(project_config_path)
  if project.inherit_global {
    let global = load_global_config()
    merge_doc_configs(project.doc, global.doc)
  } else {
    project.doc
  }
}

// JSON parsing helpers (local to doc_config)

///|
fn parse_doc_json_string(value : Json) -> String? {
  let parsed : String = @json.from_json(value) catch { _ => return None }
  Some(parsed)
}

///|
fn parse_doc_json_bool(value : Json) -> Bool? {
  let parsed : Bool = @json.from_json(value) catch { _ => return None }
  Some(parsed)
}

///|
fn parse_doc_json_string_array(value : Json) -> Array[String] {
  let parsed : Array[String] = @json.from_json(value) catch { _ => return [] }
  parsed
}
