///|
/// Digest-specific config from `.indexion.toml` or `.indexion.json`.
/// Embedding provider settings are in EmbeddingFileConfig (shared).
pub struct DigestFileConfig {
  // Currently empty — all provider settings moved to EmbeddingFileConfig.
  // Future digest-specific fields (e.g., exclude_kinds, index_dir) go here.
  placeholder_ : Bool // MoonBit requires at least one field
} derive(Eq, Debug)

///|
pub impl Show for DigestFileConfig with output(self, logger) {
  to_repr(self).output(logger)
}

///|
pub fn DigestFileConfig::empty() -> DigestFileConfig {
  { placeholder_: false }
}

///|
/// Parse key-value in [digest] section.
pub fn parse_digest_section_key(
  config : DigestFileConfig,
  _key : String,
  _value : String,
) -> DigestFileConfig {
  // No digest-specific keys currently — all moved to [embedding]
  config
}

///|
/// Merge two DigestFileConfigs.
pub fn merge_digest_configs(
  _primary : DigestFileConfig,
  _fallback : DigestFileConfig,
) -> DigestFileConfig {
  DigestFileConfig::empty()
}

// --- Embedding file config (shared across digest, search, serve, wiki) ---

///|
/// Per-provider entry from config file.
pub(all) struct ProviderFileEntry {
  key : String?
  kind : String?
  dim : Int?
  api_key_env : String?
  api_base_url : String?
  model : String?
} derive(Eq, Debug)

///|
pub fn ProviderFileEntry::empty() -> ProviderFileEntry {
  {
    key: None,
    kind: None,
    dim: None,
    api_key_env: None,
    api_base_url: None,
    model: None,
  }
}

///|
/// Embedding configuration from [embedding] section.
/// Shared across digest, search, serve, and wiki.
pub struct EmbeddingFileConfig {
  /// Legacy single-provider field (backward compat from old [digest] section).
  provider : String?
  /// vcdb strategy ("hnsw", "ivf", "bruteforce").
  strategy : String?
  /// Legacy fields (backward compat from old [digest] section).
  dim : Int?
  api_key_env : String?
  api_base_url : String?
  model : String?
  /// N-provider configuration.
  providers : Array[ProviderFileEntry]
} derive(Eq, Debug)

///|
pub fn EmbeddingFileConfig::empty() -> EmbeddingFileConfig {
  {
    provider: None,
    strategy: None,
    dim: None,
    api_key_env: None,
    api_base_url: None,
    model: None,
    providers: [],
  }
}

///|
/// Parse key-value in [embedding] section.
pub fn parse_embedding_section_key(
  config : EmbeddingFileConfig,
  key : String,
  value : String,
) -> EmbeddingFileConfig {
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
/// Parse key-value in [[embedding.providers]] section.
pub fn parse_embedding_provider_key(
  config : EmbeddingFileConfig,
  key : String,
  value : String,
) -> EmbeddingFileConfig {
  if config.providers.length() == 0 {
    return config
  }
  let idx = config.providers.length() - 1
  let entry = config.providers[idx]
  let updated = match key {
    "key" => { ..entry, key: Some(trim_quotes(value)) }
    "kind" => { ..entry, kind: Some(trim_quotes(value)) }
    "dim" => { ..entry, dim: Some(parse_int(value)) }
    "api_key_env" => { ..entry, api_key_env: Some(trim_quotes(value)) }
    "api_base_url" => { ..entry, api_base_url: Some(trim_quotes(value)) }
    "model" => { ..entry, model: Some(trim_quotes(value)) }
    _ => entry
  }
  config.providers[idx] = updated
  config
}

///|
/// Start a new [[embedding.providers]] entry.
pub fn start_embedding_provider_entry(
  config : EmbeddingFileConfig,
) -> EmbeddingFileConfig {
  let providers = config.providers
  providers.push(ProviderFileEntry::empty())
  { ..config, providers, }
}

///|
/// Load EmbeddingFileConfig from JSON root object.
/// Reads from "embedding" section. Falls back to "digest" for backward compat.
pub fn load_embedding_from_json_root(
  root : Map[String, Json],
) -> EmbeddingFileConfig {
  // Try [embedding] section first
  let section_json = match root.get("embedding") {
    Some(value) => value
    None =>
      // Backward compat: try [digest] section for legacy provider fields
      match root.get("digest") {
        Some(value) => value
        None => return EmbeddingFileConfig::empty()
      }
  }
  let obj : Map[String, Json] = @json.from_json(section_json) catch {
    _ => return EmbeddingFileConfig::empty()
  }
  let mut config = EmbeddingFileConfig::empty()
  match obj.get("provider") {
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
  match obj.get("strategy") {
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
  match obj.get("dim") {
    Some(value) =>
      match parse_json_int(value) {
        Some(v) => if v > 0 { config = { ..config, dim: Some(v) } }
        None => ()
      }
    None => ()
  }
  match obj.get("api_key_env") {
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
  match obj.get("api_base_url") {
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
  match obj.get("model") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) => if v.length() > 0 { config = { ..config, model: Some(v) } }
        None => ()
      }
    None => ()
  }
  match obj.get("providers") {
    Some(providers_json) =>
      match providers_json {
        Array(arr) => {
          let entries : Array[ProviderFileEntry] = []
          for item in arr {
            let entry = parse_provider_json_entry(item)
            entries.push(entry)
          }
          config = { ..config, providers: entries }
        }
        _ => ()
      }
    None => ()
  }
  config
}

///|
fn parse_provider_json_entry(json : Json) -> ProviderFileEntry {
  let obj : Map[String, Json] = @json.from_json(json) catch {
    _ => return ProviderFileEntry::empty()
  }
  let mut entry = ProviderFileEntry::empty()
  match obj.get("key") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => entry = { ..entry, key: Some(s) }
        None => ()
      }
    None => ()
  }
  match obj.get("kind") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => entry = { ..entry, kind: Some(s) }
        None => ()
      }
    None => ()
  }
  match obj.get("dim") {
    Some(v) =>
      match parse_json_int(v) {
        Some(d) => entry = { ..entry, dim: Some(d) }
        None => ()
      }
    None => ()
  }
  match obj.get("api_key_env") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => entry = { ..entry, api_key_env: Some(s) }
        None => ()
      }
    None => ()
  }
  match obj.get("api_base_url") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => entry = { ..entry, api_base_url: Some(s) }
        None => ()
      }
    None => ()
  }
  match obj.get("model") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => entry = { ..entry, model: Some(s) }
        None => ()
      }
    None => ()
  }
  entry
}

///|
/// Merge two EmbeddingFileConfigs. Primary takes precedence.
pub fn merge_embedding_configs(
  primary : EmbeddingFileConfig,
  fallback : EmbeddingFileConfig,
) -> EmbeddingFileConfig {
  {
    provider: or_opt(primary.provider, fallback.provider),
    strategy: or_opt(primary.strategy, fallback.strategy),
    dim: or_opt(primary.dim, fallback.dim),
    api_key_env: or_opt(primary.api_key_env, fallback.api_key_env),
    api_base_url: or_opt(primary.api_base_url, fallback.api_base_url),
    model: or_opt(primary.model, fallback.model),
    providers: if primary.providers.length() > 0 {
      primary.providers
    } else {
      fallback.providers
    },
  }
}
