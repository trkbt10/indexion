///|
/// Documentation analysis - extract doc coverage from MoonBit files.

///|
/// Project info from moon.mod.json.
pub struct ProjectInfo {
  name : String
  version : String
  description : String
  repository : String
  license : String
  keywords : Array[String]
}

///|
pub fn ProjectInfo::default() -> ProjectInfo {
  {
    name: "project",
    version: "0.0.0",
    description: "",
    repository: "",
    license: "",
    keywords: [],
  }
}

///|
/// A public item (function, type, etc.) found in the code.
pub struct PubItem {
  name : String
  kind : String // "fn", "type", "struct", "enum", "trait"
  file : String
  line : Int
  has_doc : Bool
  doc_preview : String // first line of doc if exists
}

///|
/// Package-level documentation analysis.
pub struct PackageAnalysis {
  path : String
  files : Array[String]
  pub_items : Array[PubItem]
  total_pub : Int
  documented : Int
  has_readme : Bool
}

///|
/// Full documentation analysis result.
pub struct DocAnalysis {
  packages : Array[PackageAnalysis]
  total_pub_items : Int
  total_documented : Int
  coverage_percent : Double
  critical_missing : Array[PubItem] // high priority undocumented
}

///|
/// Load project info from moon.mod.json.
pub fn load_project_info(dir : String) -> ProjectInfo {
  let path = normalize_path(dir) + "/moon.mod.json"
  try {
    let content = @fs.read_file_to_string(path)
    parse_moon_mod_json(content)
  } catch {
    _ => ProjectInfo::default()
  }
}

///|
fn parse_moon_mod_json(content : String) -> ProjectInfo {
  let mut info = ProjectInfo::default()
  // Simple JSON parsing for specific fields
  info = { ..info, name: extract_json_string(content, "name") }
  info = { ..info, version: extract_json_string(content, "version") }
  info = { ..info, description: extract_json_string(content, "description") }
  info = { ..info, repository: extract_json_string(content, "repository") }
  info = { ..info, license: extract_json_string(content, "license") }
  info = { ..info, keywords: extract_json_array(content, "keywords") }
  info
}

///|
fn extract_json_string(json : String, key : String) -> String {
  let pattern = "\"" + key + "\":"
  let chars = json.to_array()
  let pat_chars = pattern.to_array()
  // Find pattern
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
  // Skip whitespace
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  // Expect opening quote
  if start >= chars.length() || chars[start] != '"' {
    return ""
  }
  start = start + 1
  // Find closing quote
  let result : Array[Char] = []
  while start < chars.length() && chars[start] != '"' {
    if chars[start] == '\\' && start + 1 < chars.length() {
      start = start + 1 // skip escape
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
  // Find pattern
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
  // Skip to [
  while start < chars.length() && chars[start] != '[' {
    start = start + 1
  }
  if start >= chars.length() {
    return result
  }
  start = start + 1
  // Parse array items
  while start < chars.length() && chars[start] != ']' {
    // Skip whitespace and commas
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
    // Parse string
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

///|
/// Analyze documentation coverage in directory.
pub fn analyze_documentation(dir : String) -> DocAnalysis {
  let packages : Array[PackageAnalysis] = []
  let all_items : Array[PubItem] = []
  let normalized_dir = normalize_path(dir)
  let filter = @filter.FilterConfig::from_project_root(normalized_dir)
  collect_packages(normalized_dir, packages, "", filter)
  // Aggregate stats
  let mut total_pub = 0
  let mut total_doc = 0
  for pkg in packages {
    total_pub = total_pub + pkg.total_pub
    total_doc = total_doc + pkg.documented
    for item in pkg.pub_items {
      all_items.push(item)
    }
  }
  let coverage = if total_pub > 0 {
    total_doc.to_double() / total_pub.to_double() * 100.0
  } else {
    100.0
  }
  // Find critical missing (pub fn/type without docs)
  let critical : Array[PubItem] = []
  for item in all_items {
    if not(item.has_doc) &&
      (item.kind == "fn" || item.kind == "type" || item.kind == "struct") {
      critical.push(item)
    }
  }
  // Sort critical by file
  sort_pub_items(critical)
  {
    packages,
    total_pub_items: total_pub,
    total_documented: total_doc,
    coverage_percent: coverage,
    critical_missing: critical,
  }
}

///|
fn collect_packages(
  dir : String,
  packages : Array[PackageAnalysis],
  rel_path : String,
  filter : @filter.FilterConfig,
) -> Unit {
  try {
    if not(@fs.is_dir(dir)) {
      return
    }
    let entries = @fs.read_dir(dir)
    let mbt_files : Array[String] = []
    let mut has_moon_pkg = false
    let mut has_readme = false
    for entry in entries {
      let path = dir + "/" + entry
      if entry == "moon.pkg" || entry == "moon.pkg.json" {
        has_moon_pkg = true
      } else if entry == "README.md" || entry == "README.mbt.md" {
        has_readme = true
      } else if entry.has_suffix(".mbt") {
        // Use filter to check if file should be included
        let file_rel = if rel_path.length() > 0 {
          rel_path + "/" + entry
        } else {
          entry
        }
        match filter.should_include(file_rel, false) {
          @filter.FilterResult::Include => mbt_files.push(entry)
          @filter.FilterResult::Exclude(_) => ()
        }
      } else if @fs.is_dir(path) {
        // Use filter to check if directory should be skipped
        if not(filter.should_skip_dir(entry)) {
          let sub_rel = if rel_path.length() > 0 {
            rel_path + "/" + entry
          } else {
            entry
          }
          collect_packages(path, packages, sub_rel, filter)
        }
      }
    }
    // Analyze this package if it has mbt files
    if mbt_files.length() > 0 && has_moon_pkg {
      let pkg_path = if rel_path.length() > 0 { rel_path } else { "." }
      let pub_items : Array[PubItem] = []
      for file in mbt_files {
        let file_path = dir + "/" + file
        let file_rel = if rel_path.length() > 0 {
          rel_path + "/" + file
        } else {
          file
        }
        analyze_mbt_file(file_path, file_rel, pub_items)
      }
      let documented = pub_items
        .iter()
        .filter(fn(i) { i.has_doc })
        .fold(init=0, fn(acc, _) { acc + 1 })
      packages.push({
        path: pkg_path,
        files: mbt_files,
        pub_items,
        total_pub: pub_items.length(),
        documented,
        has_readme,
      })
    }
  } catch {
    _ => ()
  }
}

///|
fn analyze_mbt_file(
  path : String,
  rel_path : String,
  items : Array[PubItem],
) -> Unit {
  try {
    let content = @fs.read_file_to_string(path)
    let lines = split_lines(content)
    let mut doc_buffer : Array[String] = []
    let mut in_doc_block = false
    for i, line in lines {
      let trimmed = trim_string(line)
      // Check for doc comment
      if trimmed.has_prefix("///|") {
        in_doc_block = true
        doc_buffer = []
      } else if in_doc_block && trimmed.has_prefix("///") {
        let doc_line = if trimmed.length() > 3 {
          substring(trimmed, 3, trimmed.length())
        } else {
          ""
        }
        doc_buffer.push(trim_string(doc_line))
      } else if in_doc_block {
        // End of doc block, check if next line is pub declaration
        if trimmed.has_prefix("pub ") {
          let item = parse_pub_declaration(trimmed, rel_path, i + 1, doc_buffer)
          match item {
            Some(it) => items.push(it)
            None => ()
          }
        }
        in_doc_block = false
        doc_buffer = []
      } else if trimmed.has_prefix("pub ") {
        // Pub without doc
        let item = parse_pub_declaration(trimmed, rel_path, i + 1, [])
        match item {
          Some(it) => items.push(it)
          None => ()
        }
      }
    }
  } catch {
    _ => ()
  }
}

///|
fn parse_pub_declaration(
  line : String,
  file : String,
  line_num : Int,
  doc_lines : Array[String],
) -> PubItem? {
  let trimmed = trim_string(line)
  let has_doc = doc_lines.length() > 0
  let doc_preview = if has_doc && doc_lines[0].length() > 0 {
    let preview = doc_lines[0]
    if preview.length() > 60 {
      substring(preview, 0, 60) + "..."
    } else {
      preview
    }
  } else {
    ""
  }
  // Parse pub fn
  if trimmed.has_prefix("pub fn ") {
    let rest = substring(trimmed, 7, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "fn",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  // Parse pub struct
  if trimmed.has_prefix("pub struct ") {
    let rest = substring(trimmed, 11, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "struct",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  // Parse pub enum
  if trimmed.has_prefix("pub enum ") {
    let rest = substring(trimmed, 9, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "enum",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  // Parse pub type
  if trimmed.has_prefix("pub type ") {
    let rest = substring(trimmed, 9, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "type",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  // Parse pub trait
  if trimmed.has_prefix("pub trait ") {
    let rest = substring(trimmed, 10, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "trait",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  // Parse pub let (constants)
  if trimmed.has_prefix("pub let ") {
    let rest = substring(trimmed, 8, trimmed.length())
    let name = extract_identifier(rest)
    if name.length() > 0 {
      return Some({
        name,
        kind: "const",
        file,
        line: line_num,
        has_doc,
        doc_preview,
      })
    }
  }
  None
}

///|
fn extract_identifier(s : String) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  for c in chars {
    if is_ident_char(c) {
      result.push(c)
    } else {
      break
    }
  }
  String::from_array(result)
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == ':'
}

// String utilities

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let current : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else if c != '\r' {
      current.push(c)
    }
  }
  if current.length() > 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end = end - 1
  }
  let result : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let result : Array[Char] = []
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

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
fn sort_pub_items(items : Array[PubItem]) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    for j = i + 1; j < items.length(); j = j + 1 {
      if items[j].file < items[i].file ||
        (items[j].file == items[i].file && items[j].line < items[i].line) {
        let tmp = items[i]
        items[i] = items[j]
        items[j] = tmp
      }
    }
  }
}
