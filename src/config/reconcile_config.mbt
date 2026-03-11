///|
/// Optional values loaded from `.indexion.toml` or `.indexion.json` for
/// `indexion plan reconcile`.
pub struct ReconcileFileConfig {
  doc_scope : String?
  doc_paths : Array[String]?
  doc_specs : Array[String]?
  index_dir : String?
  format : String?
  review_results_path : String?
  threshold_seconds : Int?
  max_candidates : Int?
  allow_file_fallback : Bool?
  git_preferred : Bool?
  mtime_fallback : Bool?
  logical_review_mode : String?
} derive(Eq, Show)

///|
/// Resolved document selection for reconcile.
pub struct ReconcileDocumentScope {
  scope_name : String
  doc_paths : Array[String]
  doc_specs : Array[String]
  path_scope : @scope.PathScope
} derive(Eq, Show)

///|
pub fn ReconcileFileConfig::empty() -> ReconcileFileConfig {
  {
    doc_scope: None,
    doc_paths: None,
    doc_specs: None,
    index_dir: None,
    format: None,
    review_results_path: None,
    threshold_seconds: None,
    max_candidates: None,
    allow_file_fallback: None,
    git_preferred: None,
    mtime_fallback: None,
    logical_review_mode: None,
  }
}

///|
pub fn resolve_reconcile_specs_dir(
  target_dir : String,
  explicit_specs_dir? : String = "",
) -> String {
  if explicit_specs_dir.length() > 0 {
    resolve_path(target_dir, explicit_specs_dir)
  } else {
    match find_kgfs_dir(target_dir~) {
      Some(dir) => dir
      None => normalize_path("kgfs")
    }
  }
}

///|
pub fn normalize_reconcile_doc_scope(scope : String) -> String {
  match trim_string(scope).to_lower() {
    "package-docs" => "package-docs"
    "tree-docs" => "tree-docs"
    "custom" => "custom"
    _ => "custom"
  }
}

///|
pub fn reconcile_doc_scope_paths(scope : String) -> Array[String] {
  match normalize_reconcile_doc_scope(scope) {
    "package-docs" => ["README.md", "docs/**/*.md"]
    "tree-docs" => ["**/README.md", "**/docs/**/*.md"]
    _ => []
  }
}

///|
pub fn reconcile_doc_scope_specs(scope : String) -> Array[String] {
  match normalize_reconcile_doc_scope(scope) {
    "package-docs" | "tree-docs" => ["markdown"]
    _ => []
  }
}

///|
pub fn resolve_reconcile_document_scope(
  scope : String,
  doc_paths? : Array[String] = [],
  doc_specs? : Array[String] = [],
) -> ReconcileDocumentScope {
  let scope_name = normalize_reconcile_doc_scope(scope)
  let resolved_doc_paths = if doc_paths.is_empty() {
    reconcile_doc_scope_paths(scope_name)
  } else {
    doc_paths
  }
  let resolved_doc_specs = if doc_specs.is_empty() {
    reconcile_doc_scope_specs(scope_name)
  } else {
    doc_specs
  }
  {
    scope_name,
    doc_paths: resolved_doc_paths,
    doc_specs: resolved_doc_specs,
    path_scope: @scope.PathScope::new(includes=resolved_doc_paths),
  }
}

///|
pub fn load_reconcile_file_config(path : String) -> ReconcileFileConfig {
  if path.length() == 0 {
    return ReconcileFileConfig::empty()
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => return ReconcileFileConfig::empty()
  }
  if path.has_suffix(".json") {
    parse_reconcile_json_config(content)
  } else if path.has_suffix(".toml") {
    parse_reconcile_toml_config(content)
  } else {
    ReconcileFileConfig::empty()
  }
}

///|
pub fn parse_reconcile_toml_config(content : String) -> ReconcileFileConfig {
  let mut file_config = ReconcileFileConfig::empty()
  let mut section = ""
  for raw_line in split_lines(content) {
    let line = trim_toml_comment(raw_line)
    if line.length() == 0 {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      section = trim_quotes(substring(line, 1, line.length() - 1))
      continue
    }
    let eq_idx = last_index_of_char(line, '=')
    if eq_idx <= 0 {
      continue
    }
    let key = trim_string(substring(line, 0, eq_idx))
    let value = trim_string(substring(line, eq_idx + 1, line.length()))
    match section {
      "reconcile" =>
        match key {
          "doc_scope" =>
            file_config = { ..file_config, doc_scope: Some(trim_quotes(value)) }
          "doc_paths" =>
            file_config = {
              ..file_config,
              doc_paths: Some(parse_string_array_literal(value)),
            }
          "doc_specs" =>
            file_config = {
              ..file_config,
              doc_specs: Some(parse_string_array_literal(value)),
            }
          "index_dir" =>
            file_config = { ..file_config, index_dir: Some(trim_quotes(value)) }
          "review_results_path" =>
            file_config = {
              ..file_config,
              review_results_path: Some(trim_quotes(value)),
            }
          "threshold_seconds" =>
            file_config = {
              ..file_config,
              threshold_seconds: Some(parse_int(value)),
            }
          "max_candidates" =>
            file_config = {
              ..file_config,
              max_candidates: Some(parse_int(value)),
            }
          _ => ()
        }
      "reconcile.mapping" =>
        if key == "allow_file_fallback" {
          match parse_bool_like(value) {
            Some(v) =>
              file_config = { ..file_config, allow_file_fallback: Some(v) }
            None => ()
          }
        }
      "reconcile.output" =>
        if key == "default_format" {
          file_config = { ..file_config, format: Some(trim_quotes(value)) }
        }
      "reconcile.time" =>
        if key == "git_preferred" {
          match parse_bool_like(value) {
            Some(v) => file_config = { ..file_config, git_preferred: Some(v) }
            None => ()
          }
        } else if key == "mtime_fallback" {
          match parse_bool_like(value) {
            Some(v) => file_config = { ..file_config, mtime_fallback: Some(v) }
            None => ()
          }
        }
      "reconcile.logical_review" =>
        if key == "mode" {
          file_config = {
            ..file_config,
            logical_review_mode: Some(trim_quotes(value)),
          }
        }
      _ => ()
    }
  }
  file_config
}

///|
fn parse_reconcile_json_config(content : String) -> ReconcileFileConfig {
  let parsed = @json.parse(content) catch {
    _ => return ReconcileFileConfig::empty()
  }
  let root : Map[String, Json] = @json.from_json(parsed) catch {
    _ => return ReconcileFileConfig::empty()
  }
  let reconcile_json = match root.get("reconcile") {
    Some(value) => value
    None => return ReconcileFileConfig::empty()
  }
  let reconcile_obj : Map[String, Json] = @json.from_json(reconcile_json) catch {
    _ => return ReconcileFileConfig::empty()
  }
  let mut file_config = ReconcileFileConfig::empty()
  match reconcile_obj.get("doc_scope") {
    Some(value) =>
      match parse_json_string(value) {
        Some(parsed_value) =>
          if parsed_value.length() > 0 {
            file_config = { ..file_config, doc_scope: Some(parsed_value) }
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("doc_paths") {
    Some(value) =>
      match parse_json_string_array(value) {
        Some(values) => file_config = { ..file_config, doc_paths: Some(values) }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("doc_specs") {
    Some(value) =>
      match parse_json_string_array(value) {
        Some(values) => file_config = { ..file_config, doc_specs: Some(values) }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("index_dir") {
    Some(value) =>
      match parse_json_string(value) {
        Some(parsed_value) =>
          if parsed_value.length() > 0 {
            file_config = { ..file_config, index_dir: Some(parsed_value) }
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("review_results_path") {
    Some(value) =>
      match parse_json_string(value) {
        Some(parsed_value) =>
          if parsed_value.length() > 0 {
            file_config = {
              ..file_config,
              review_results_path: Some(parsed_value),
            }
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("max_candidates") {
    Some(value) =>
      match parse_json_int(value) {
        Some(parsed_value) =>
          if parsed_value > 0 {
            file_config = { ..file_config, max_candidates: Some(parsed_value) }
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("threshold_seconds") {
    Some(value) =>
      match parse_json_int(value) {
        Some(parsed_value) =>
          if parsed_value > 0 {
            file_config = {
              ..file_config,
              threshold_seconds: Some(parsed_value),
            }
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("mapping") {
    Some(value) =>
      match parse_json_object(value) {
        Some(mapping_obj) =>
          match mapping_obj.get("allow_file_fallback") {
            Some(bool_value) =>
              match parse_json_bool(bool_value) {
                Some(parsed_value) =>
                  file_config = {
                    ..file_config,
                    allow_file_fallback: Some(parsed_value),
                  }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("output") {
    Some(value) =>
      match parse_json_object(value) {
        Some(output_obj) =>
          match output_obj.get("default_format") {
            Some(format_json) =>
              match parse_json_string(format_json) {
                Some(parsed_value) =>
                  if parsed_value.length() > 0 {
                    file_config = { ..file_config, format: Some(parsed_value) }
                  }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("time") {
    Some(value) =>
      match parse_json_object(value) {
        Some(time_obj) => {
          match time_obj.get("git_preferred") {
            Some(bool_value) =>
              match parse_json_bool(bool_value) {
                Some(parsed_value) =>
                  file_config = {
                    ..file_config,
                    git_preferred: Some(parsed_value),
                  }
                None => ()
              }
            None => ()
          }
          match time_obj.get("mtime_fallback") {
            Some(bool_value) =>
              match parse_json_bool(bool_value) {
                Some(parsed_value) =>
                  file_config = {
                    ..file_config,
                    mtime_fallback: Some(parsed_value),
                  }
                None => ()
              }
            None => ()
          }
        }
        None => ()
      }
    None => ()
  }
  match reconcile_obj.get("logical_review") {
    Some(value) =>
      match parse_json_object(value) {
        Some(logical_obj) =>
          match logical_obj.get("mode") {
            Some(mode_json) =>
              match parse_json_string(mode_json) {
                Some(parsed_value) =>
                  if parsed_value.length() > 0 {
                    file_config = {
                      ..file_config,
                      logical_review_mode: Some(parsed_value),
                    }
                  }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  file_config
}

///|
fn parse_json_string_array(value : Json) -> Array[String]? {
  let values : Array[String] = @json.from_json(value) catch { _ => return None }
  Some(values)
}

///|
fn parse_json_string(value : Json) -> String? {
  let parsed : String = @json.from_json(value) catch { _ => return None }
  Some(parsed)
}

///|
fn parse_json_int(value : Json) -> Int? {
  let parsed : Int = @json.from_json(value) catch { _ => return None }
  Some(parsed)
}

///|
fn parse_json_bool(value : Json) -> Bool? {
  let parsed : Bool = @json.from_json(value) catch { _ => return None }
  Some(parsed)
}

///|
fn parse_json_object(value : Json) -> Map[String, Json]? {
  let parsed : Map[String, Json] = @json.from_json(value) catch {
    _ => return None
  }
  Some(parsed)
}

///|
fn parse_string_array_literal(value : String) -> Array[String] {
  let trimmed = trim_string(value)
  if not(trimmed.has_prefix("[")) || not(trimmed.has_suffix("]")) {
    return []
  }
  let inner = substring(trimmed, 1, trimmed.length() - 1)
  let chars = inner.to_array()
  let items : Array[String] = []
  let current : Array[Char] = []
  let mut in_quote = false
  let mut quote_char = '"'
  for ch in chars {
    if in_quote {
      if ch == quote_char {
        in_quote = false
      } else {
        current.push(ch)
      }
    } else if ch == '"' || ch == '\'' {
      in_quote = true
      quote_char = ch
    } else if ch == ',' {
      let item = trim_string(String::from_array(current))
      if item.length() > 0 {
        items.push(trim_quotes(item))
      }
      current.clear()
    } else {
      current.push(ch)
    }
  }
  let last = trim_string(String::from_array(current))
  if last.length() > 0 {
    items.push(trim_quotes(last))
  }
  items
}

///|
pub fn trim_toml_comment(line : String) -> String {
  let chars = line.to_array()
  let result : Array[Char] = []
  let mut in_quote = false
  let mut quote_char = '"'
  for ch in chars {
    if in_quote {
      if ch == quote_char {
        in_quote = false
      }
      result.push(ch)
    } else if ch == '"' || ch == '\'' {
      in_quote = true
      quote_char = ch
      result.push(ch)
    } else if ch == '#' {
      break
    } else {
      result.push(ch)
    }
  }
  trim_string(String::from_array(result))
}

///|
fn parse_bool_like(value : String) -> Bool? {
  match trim_string(value).to_lower() {
    "true" => Some(true)
    "false" => Some(false)
    _ => None
  }
}

///|
fn parse_int(text : String) -> Int {
  let chars = trim_string(text).to_array()
  if chars.length() == 0 {
    return 0
  }
  let mut idx = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    idx = 1
  }
  let mut result = 0
  while idx < chars.length() {
    let ch = chars[idx]
    if ch < '0' || ch > '9' {
      break
    }
    result = result * 10 + (ch.to_int() - '0'.to_int())
    idx = idx + 1
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
fn trim_string(text : String) -> String {
  text.trim().to_string()
}

///|
fn trim_quotes(text : String) -> String {
  let trimmed = trim_string(text)
  if trimmed.length() >= 2 &&
    (
      (trimmed.has_prefix("\"") && trimmed.has_suffix("\"")) ||
      (trimmed.has_prefix("'") && trimmed.has_suffix("'"))
    ) {
    substring(trimmed, 1, trimmed.length() - 1)
  } else {
    trimmed
  }
}

///|
fn substring(text : String, start : Int, end : Int) -> String {
  let chars = text.to_array()
  let actual_start = if start < 0 { 0 } else { start }
  let capped_end = if end > chars.length() { chars.length() } else { end }
  if actual_start >= capped_end {
    return ""
  }
  let out : Array[Char] = []
  for i = actual_start; i < capped_end; i = i + 1 {
    out.push(chars[i])
  }
  String::from_array(out)
}

///|
fn split_lines(content : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = content.to_array()
  let current : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\n' {
      lines.push(String::from_array(current))
      current.clear()
    } else if ch == '\r' {
      lines.push(String::from_array(current))
      current.clear()
    } else {
      current.push(ch)
    }
    i = i + 1
  }
  if current.length() > 0 || content.length() == 0 {
    lines.push(String::from_array(current))
  }
  lines
}

///|
fn last_index_of_char(text : String, target : Char) -> Int {
  let chars = text.to_array()
  let mut idx = -1
  for i, ch in chars {
    if ch == target {
      idx = i
    }
  }
  idx
}
