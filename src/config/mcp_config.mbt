///|
/// Optional values loaded from `.indexion.toml` or `.indexion.json`
/// for the `indexion mcp` command.
pub struct McpFileConfig {
  transport : String?
  port : Int?
  host : String?
  specs_dir : String?
} derive(Eq, Debug)

///|
/// Create an empty MCP file config with all fields set to None.
pub fn McpFileConfig::empty() -> McpFileConfig {
  { transport: None, port: None, host: None, specs_dir: None }
}

///|
/// Parse key-value in [mcp] section of TOML.
pub fn parse_mcp_section_key(
  config : McpFileConfig,
  key : String,
  value : String,
) -> McpFileConfig {
  match key {
    "transport" => { ..config, transport: Some(trim_quotes(value)) }
    "port" => { ..config, port: Some(parse_int(value)) }
    "host" => { ..config, host: Some(trim_quotes(value)) }
    "specs_dir" => { ..config, specs_dir: Some(trim_quotes(value)) }
    _ => config
  }
}

///|
/// Load McpFileConfig from JSON root object.
pub fn load_mcp_from_json_root(root : Map[String, Json]) -> McpFileConfig {
  let mcp_json = match root.get("mcp") {
    Some(value) => value
    None => return McpFileConfig::empty()
  }
  let mcp_obj : Map[String, Json] = @json.from_json(mcp_json) catch {
    _ => return McpFileConfig::empty()
  }
  let mut config = McpFileConfig::empty()
  match mcp_obj.get("transport") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, transport: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match mcp_obj.get("port") {
    Some(value) =>
      match parse_json_int(value) {
        Some(v) => if v > 0 { config = { ..config, port: Some(v) } }
        None => ()
      }
    None => ()
  }
  match mcp_obj.get("host") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) => if v.length() > 0 { config = { ..config, host: Some(v) } }
        None => ()
      }
    None => ()
  }
  match mcp_obj.get("specs_dir") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, specs_dir: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  config
}

///|
/// Merge two McpFileConfigs. Primary takes precedence over fallback.
pub fn merge_mcp_configs(
  primary : McpFileConfig,
  fallback : McpFileConfig,
) -> McpFileConfig {
  {
    transport: or_opt(primary.transport, fallback.transport),
    port: or_opt(primary.port, fallback.port),
    host: or_opt(primary.host, fallback.host),
    specs_dir: or_opt(primary.specs_dir, fallback.specs_dir),
  }
}

///|
/// Load merged MCP config from project + global config files.
pub fn load_effective_mcp_config(project_config_path : String) -> McpFileConfig {
  let project = load_project_config(project_config_path)
  if project.inherit_global {
    let global = load_global_config()
    merge_mcp_configs(project.mcp, global.mcp)
  } else {
    project.mcp
  }
}
