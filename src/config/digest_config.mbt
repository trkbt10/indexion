///|
/// Optional values loaded from `.indexion.toml` or `.indexion.json` for
/// `indexion digest` and `indexion serve` commands.
pub struct DigestFileConfig {
  provider : String?
  strategy : String?
  dim : Int?
  api_key_env : String?
  api_base_url : String?
  model : String?
} derive(Eq, Show)

///|
/// Create an empty digest file config with all fields set to None.
pub fn DigestFileConfig::empty() -> DigestFileConfig {
  {
    provider: None,
    strategy: None,
    dim: None,
    api_key_env: None,
    api_base_url: None,
    model: None,
  }
}

///|
/// Parse key-value in [digest] section.
pub fn parse_digest_section_key(
  config : DigestFileConfig,
  key : String,
  value : String,
) -> DigestFileConfig {
  match key {
    "provider" => { ..config, provider: Some(trim_quotes(value)) }
    "strategy" => { ..config, strategy: Some(trim_quotes(value)) }
    "dim" => { ..config, dim: Some(parse_int(value)) }
    "api_key_env" => { ..config, api_key_env: Some(trim_quotes(value)) }
    "api_base_url" => { ..config, api_base_url: Some(trim_quotes(value)) }
    "model" => { ..config, model: Some(trim_quotes(value)) }
    _ => config
  }
}

///|
/// Load DigestFileConfig from JSON root object.
pub fn load_digest_from_json_root(
  root : Map[String, Json],
) -> DigestFileConfig {
  let digest_json = match root.get("digest") {
    Some(value) => value
    None => return DigestFileConfig::empty()
  }
  let digest_obj : Map[String, Json] = @json.from_json(digest_json) catch {
    _ => return DigestFileConfig::empty()
  }
  let mut config = DigestFileConfig::empty()
  match digest_obj.get("provider") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, provider: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match digest_obj.get("strategy") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, strategy: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match digest_obj.get("dim") {
    Some(value) =>
      match parse_json_int(value) {
        Some(v) =>
          if v > 0 {
            config = { ..config, dim: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match digest_obj.get("api_key_env") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, api_key_env: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match digest_obj.get("api_base_url") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, api_base_url: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match digest_obj.get("model") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, model: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  config
}

///|
/// Merge two DigestFileConfigs. Primary takes precedence over fallback.
pub fn merge_digest_configs(
  primary : DigestFileConfig,
  fallback : DigestFileConfig,
) -> DigestFileConfig {
  {
    provider: or_opt(primary.provider, fallback.provider),
    strategy: or_opt(primary.strategy, fallback.strategy),
    dim: or_opt(primary.dim, fallback.dim),
    api_key_env: or_opt(primary.api_key_env, fallback.api_key_env),
    api_base_url: or_opt(primary.api_base_url, fallback.api_base_url),
    model: or_opt(primary.model, fallback.model),
  }
}
