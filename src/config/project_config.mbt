///|
/// Project-level configuration loaded from .indexion.toml or .indexion.json.
/// Contains project-specific settings and inherit_global flag for global config.

///|
/// Project configuration with inherit_global flag and command-specific settings.
pub struct ProjectFileConfig {
  inherit_global : Bool
  reconcile : ReconcileFileConfig
  digest : DigestFileConfig
  embedding : EmbeddingFileConfig
  mcp : McpFileConfig
  doc : DocFileConfig
  wiki : WikiFileConfig
} derive(Eq, Debug)

///|
/// Effective reconcile config with merged values and provenance.
pub struct EffectiveReconcileConfig {
  project : ProjectFileConfig
  global : GlobalConfig
  merged : ReconcileFileConfig
  global_config_path : String?
} derive(Eq, Debug)

///|
/// Create default project config with inherit_globalance enabled.
pub fn ProjectFileConfig::default() -> ProjectFileConfig {
  {
    inherit_global: true,
    reconcile: ReconcileFileConfig::empty(),
    digest: DigestFileConfig::empty(),
    embedding: EmbeddingFileConfig::empty(),
    mcp: McpFileConfig::empty(),
    doc: DocFileConfig::empty(),
    wiki: WikiFileConfig::empty(),
  }
}

///|
/// Load project configuration from .indexion.toml or .indexion.json.
pub fn load_project_config(path : String) -> ProjectFileConfig {
  if path.length() == 0 {
    return ProjectFileConfig::default()
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => return ProjectFileConfig::default()
  }
  if path.has_suffix(".json") {
    parse_project_json_config(content)
  } else if path.has_suffix(".toml") {
    parse_project_toml_config(content)
  } else {
    ProjectFileConfig::default()
  }
}

///|
/// Parse project TOML configuration.
/// Supports both [section] headers and [[array.of.tables]] headers.
pub fn parse_project_toml_config(content : String) -> ProjectFileConfig {
  let mut config = ProjectFileConfig::default()
  let mut section = ""
  let mut is_array_section = false
  for raw_line in split_lines(content) {
    let line = trim_toml_comment(raw_line)
    if line.length() == 0 {
      continue
    }
    // Detect [[array.of.tables]] (double bracket)
    if line.has_prefix("[[") && line.has_suffix("]]") {
      section = trim_quotes(substring(line, 2, line.length() - 2))
      is_array_section = true
      // Handle array-of-tables entry creation
      if section == "embedding.providers" {
        config = {
          ..config,
          embedding: start_embedding_provider_entry(config.embedding),
        }
      }
      continue
    }
    // Detect [section] (single bracket)
    if line.has_prefix("[") && line.has_suffix("]") {
      section = trim_quotes(substring(line, 1, line.length() - 1))
      is_array_section = false
      continue
    }
    let eq_idx = find_last_char(line, '=')
    if eq_idx <= 0 {
      continue
    }
    let key = trim_string(substring(line, 0, eq_idx))
    let value = trim_string(substring(line, eq_idx + 1, line.length()))
    // Dispatch based on section
    if is_array_section && section == "embedding.providers" {
      config = {
        ..config,
        embedding: parse_embedding_provider_key(config.embedding, key, value),
      }
    } else if section == "embedding" {
      config = {
        ..config,
        embedding: parse_embedding_section_key(config.embedding, key, value),
      }
    } else if section == "digest" {
      // Backward compat: [digest] provider/strategy/dim fields → [embedding]
      config = {
        ..config,
        embedding: parse_embedding_section_key(config.embedding, key, value),
      }
    } else if section == "indexion" {
      if key == "inherit" {
        match parse_bool_like(value) {
          Some(v) => config = { ..config, inherit_global: v }
          None => ()
        }
      }
    } else if section == "mcp" {
      config = { ..config, mcp: parse_mcp_section_key(config.mcp, key, value) }
    } else if section == "doc" {
      config = { ..config, doc: parse_doc_section_key(config.doc, key, value) }
    } else if section == "wiki" {
      config = {
        ..config,
        wiki: parse_wiki_section_key(config.wiki, key, value),
      }
    } else if section == "wiki.colors.dark" {
      config = {
        ..config,
        wiki: {
          ..config.wiki,
          colors_dark: parse_wiki_color_key(config.wiki.colors_dark, key, value),
        },
      }
    } else if section == "wiki.colors.light" {
      config = {
        ..config,
        wiki: {
          ..config.wiki,
          colors_light: parse_wiki_color_key(
            config.wiki.colors_light,
            key,
            value,
          ),
        },
      }
    } else {
      let (reconcile, digest) = parse_shared_toml_sections(
        config.reconcile,
        config.digest,
        section,
        key,
        value,
      )
      config = { ..config, reconcile, digest }
    }
  }
  config
}

///|
/// Parse project JSON configuration.
fn parse_project_json_config(content : String) -> ProjectFileConfig {
  let parsed = @json.parse(content) catch {
    _ => return ProjectFileConfig::default()
  }
  let root : Map[String, Json] = @json.from_json(parsed) catch {
    _ => return ProjectFileConfig::default()
  }
  let mut config = ProjectFileConfig::default()
  // Parse [indexion] section
  match root.get("indexion") {
    Some(indexion_json) =>
      match parse_json_object(indexion_json) {
        Some(indexion_obj) =>
          match indexion_obj.get("inherit") {
            Some(inherit_global_json) =>
              match parse_json_bool(inherit_global_json) {
                Some(v) => config = { ..config, inherit_global: v }
                None => ()
              }
            None => ()
          }
        None => ()
      }
    None => ()
  }
  // Parse [reconcile] section (reuse existing logic)
  let reconcile = load_reconcile_from_json_root(root)
  // Parse [digest] section (currently empty)
  let digest = DigestFileConfig::empty()
  // Parse [embedding] section
  let embedding = load_embedding_from_json_root(root)
  // Parse [mcp] section
  let mcp = load_mcp_from_json_root(root)
  // Parse [doc] section
  let doc = load_doc_from_json_root(root)
  // Parse [wiki] section
  let wiki = load_wiki_from_json_root(root)
  { ..config, reconcile, digest, embedding, mcp, doc, wiki }
}

///|
/// Load ReconcileFileConfig from JSON root object.
fn load_reconcile_from_json_root(
  root : Map[String, Json],
) -> ReconcileFileConfig {
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
  file_config
}

///|
/// Choose primary if Some, otherwise fallback.
fn[T] or_opt(primary : T?, fallback : T?) -> T? {
  match primary {
    Some(_) => primary
    None => fallback
  }
}

///|
/// Merge global config into file config.
/// File config values take precedence over global values.
pub fn merge_global_into_file(
  file : ReconcileFileConfig,
  global : ReconcileFileConfig,
) -> ReconcileFileConfig {
  {
    doc_scope: or_opt(file.doc_scope, global.doc_scope),
    doc_paths: or_opt(file.doc_paths, global.doc_paths),
    doc_specs: or_opt(file.doc_specs, global.doc_specs),
    index_dir: or_opt(file.index_dir, global.index_dir),
    format: or_opt(file.format, global.format),
    review_results_path: or_opt(
      file.review_results_path,
      global.review_results_path,
    ),
    threshold_seconds: or_opt(file.threshold_seconds, global.threshold_seconds),
    max_candidates: or_opt(file.max_candidates, global.max_candidates),
    allow_file_fallback: or_opt(
      file.allow_file_fallback,
      global.allow_file_fallback,
    ),
    git_preferred: or_opt(file.git_preferred, global.git_preferred),
    mtime_fallback: or_opt(file.mtime_fallback, global.mtime_fallback),
    logical_review_mode: or_opt(
      file.logical_review_mode,
      global.logical_review_mode,
    ),
    vocabulary_divergence_threshold: or_opt(
      file.vocabulary_divergence_threshold,
      global.vocabulary_divergence_threshold,
    ),
  }
}

///|
fn build_effective_reconcile_config(
  project : ProjectFileConfig,
  global : GlobalConfig,
  global_config_path : String?,
) -> EffectiveReconcileConfig {
  if project.inherit_global {
    {
      project,
      global,
      merged: merge_global_into_file(project.reconcile, global.reconcile),
      global_config_path,
    }
  } else {
    {
      project,
      global: GlobalConfig::empty(),
      merged: project.reconcile,
      global_config_path: None,
    }
  }
}

///|
/// Resolve effective reconcile config with merged values and provenance.
pub fn resolve_effective_reconcile_config(
  project_config_path : String,
) -> EffectiveReconcileConfig {
  let project = load_project_config(project_config_path)
  let global = if project.inherit_global {
    load_global_config()
  } else {
    GlobalConfig::empty()
  }
  let global_config_path = if project.inherit_global {
    get_global_config_path()
  } else {
    None
  }
  build_effective_reconcile_config(project, global, global_config_path)
}

///|
/// Load merged reconcile config only.
pub fn load_effective_reconcile_config(
  project_config_path : String,
) -> ReconcileFileConfig {
  resolve_effective_reconcile_config(project_config_path).merged
}

///|
/// Load merged digest config from project + global config files.
pub fn load_effective_digest_config(
  project_config_path : String,
) -> DigestFileConfig {
  let project = load_project_config(project_config_path)
  if project.inherit_global {
    let global = load_global_config()
    merge_digest_configs(project.digest, global.digest)
  } else {
    project.digest
  }
}

///|
/// Load merged embedding config from project + global config files.
pub fn load_effective_embedding_config(
  project_config_path : String,
) -> EmbeddingFileConfig {
  let project = load_project_config(project_config_path)
  if project.inherit_global {
    let global = load_global_config()
    merge_embedding_configs(project.embedding, global.embedding)
  } else {
    project.embedding
  }
}
