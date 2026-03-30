///|
/// Global configuration loaded from OS-standard config directory.
/// Provides default settings that can be inherited by project configurations.

///|
/// Global configuration structure.
pub struct GlobalConfig {
  kgfs_dir : String?
  reconcile : ReconcileFileConfig
  digest : DigestFileConfig
} derive(Eq, Show)

///|
/// Create empty global config.
pub fn GlobalConfig::empty() -> GlobalConfig {
  {
    kgfs_dir: None,
    reconcile: ReconcileFileConfig::empty(),
    digest: DigestFileConfig::empty(),
  }
}

///|
/// Load global configuration from OS-standard config directory.
/// Returns empty config if file doesn't exist or is unreadable.
pub fn load_global_config() -> GlobalConfig {
  match get_global_config_dir() {
    Some(dir) => {
      let config_path = join_path(dir, "config.toml")
      if is_valid_file(config_path) {
        let content = @fs.read_file_to_string(config_path) catch {
          _ => return GlobalConfig::empty()
        }
        return parse_global_toml_config(content)
      }
      GlobalConfig::empty()
    }
    None => GlobalConfig::empty()
  }
}

///|
/// Get the path to global config file.
pub fn get_global_config_path() -> String? {
  match get_global_config_dir() {
    Some(dir) => Some(join_path(dir, "config.toml"))
    None => None
  }
}

///|
/// Parse global TOML configuration content.
pub fn parse_global_toml_config(content : String) -> GlobalConfig {
  let mut config = GlobalConfig::empty()
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
    let eq_idx = find_last_char(line, '=')
    if eq_idx <= 0 {
      continue
    }
    let key = trim_string(substring(line, 0, eq_idx))
    let value = trim_string(substring(line, eq_idx + 1, line.length()))
    match section {
      "global" =>
        if key == "kgfs_dir" {
          let parsed = trim_quotes(value)
          if parsed.length() > 0 {
            config = { ..config, kgfs_dir: Some(expand_tilde(parsed)) }
          }
        }
      "reconcile" =>
        config = {
          ..config,
          reconcile: parse_reconcile_section_key(config.reconcile, key, value),
        }
      "reconcile.mapping" =>
        config = {
          ..config,
          reconcile: parse_reconcile_mapping_key(config.reconcile, key, value),
        }
      "reconcile.output" =>
        config = {
          ..config,
          reconcile: parse_reconcile_output_key(config.reconcile, key, value),
        }
      "reconcile.time" =>
        config = {
          ..config,
          reconcile: parse_reconcile_time_key(config.reconcile, key, value),
        }
      "reconcile.logical_review" =>
        config = {
          ..config,
          reconcile: parse_reconcile_logical_review_key(
            config.reconcile,
            key,
            value,
          ),
        }
      "digest" =>
        config = {
          ..config,
          digest: parse_digest_section_key(config.digest, key, value),
        }
      _ => ()
    }
  }
  config
}

///|
/// Parse key-value in [reconcile] section.
fn parse_reconcile_section_key(
  config : ReconcileFileConfig,
  key : String,
  value : String,
) -> ReconcileFileConfig {
  match key {
    "doc_scope" => { ..config, doc_scope: Some(trim_quotes(value)) }
    "doc_paths" =>
      { ..config, doc_paths: Some(parse_string_array_literal(value)) }
    "doc_specs" =>
      { ..config, doc_specs: Some(parse_string_array_literal(value)) }
    "index_dir" => { ..config, index_dir: Some(trim_quotes(value)) }
    "review_results_path" =>
      { ..config, review_results_path: Some(trim_quotes(value)) }
    "threshold_seconds" =>
      { ..config, threshold_seconds: Some(parse_int(value)) }
    "max_candidates" => { ..config, max_candidates: Some(parse_int(value)) }
    _ => config
  }
}

///|
/// Parse key-value in [reconcile.mapping] section.
fn parse_reconcile_mapping_key(
  config : ReconcileFileConfig,
  key : String,
  value : String,
) -> ReconcileFileConfig {
  if key == "allow_file_fallback" {
    match parse_bool_like(value) {
      Some(v) => { ..config, allow_file_fallback: Some(v) }
      None => config
    }
  } else {
    config
  }
}

///|
/// Parse key-value in [reconcile.output] section.
fn parse_reconcile_output_key(
  config : ReconcileFileConfig,
  key : String,
  value : String,
) -> ReconcileFileConfig {
  if key == "default_format" {
    { ..config, format: Some(trim_quotes(value)) }
  } else {
    config
  }
}

///|
/// Parse key-value in [reconcile.time] section.
fn parse_reconcile_time_key(
  config : ReconcileFileConfig,
  key : String,
  value : String,
) -> ReconcileFileConfig {
  match key {
    "git_preferred" =>
      match parse_bool_like(value) {
        Some(v) => { ..config, git_preferred: Some(v) }
        None => config
      }
    "mtime_fallback" =>
      match parse_bool_like(value) {
        Some(v) => { ..config, mtime_fallback: Some(v) }
        None => config
      }
    _ => config
  }
}

///|
/// Parse key-value in [reconcile.logical_review] section.
fn parse_reconcile_logical_review_key(
  config : ReconcileFileConfig,
  key : String,
  value : String,
) -> ReconcileFileConfig {
  if key == "mode" {
    { ..config, logical_review_mode: Some(trim_quotes(value)) }
  } else {
    config
  }
}

///|
/// Expand ~ to home directory in paths.
fn expand_tilde(path : String) -> String {
  if path.has_prefix("~/") {
    match @osenv_dirs.home_dir() {
      Some(home) => home + substring(path, 1, path.length())
      None => path
    }
  } else {
    path
  }
}
