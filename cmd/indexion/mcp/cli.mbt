///|
/// # indexion mcp
///
/// Start MCP (Model Context Protocol) server exposing indexion tools.
/// Supports two transport modes:
/// - stdio: reads JSON-RPC from stdin, writes to stdout (default)
/// - http: serves MCP over HTTP POST /mcp endpoint
///
/// ## Usage
///
/// ```bash
/// # stdio mode (for Claude Code, Cursor, etc.)
/// indexion mcp
///
/// # HTTP mode
/// indexion mcp --transport=http --port=3741
/// ```

///|
pub struct McpConfig {
  transport : String
  port : Int
  host : String
  specs_dir : String
  workspace_dir : String
}

///|
pub fn McpConfig::default() -> McpConfig {
  {
    transport: "stdio",
    port: 3741,
    host: "127.0.0.1",
    specs_dir: "kgfs",
    workspace_dir: ".",
  }
}

///|
pub fn McpConfig::from_matches(matches : @argparse.Matches) -> McpConfig {
  let mut config = McpConfig::default()
  match matches.values.get("transport") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, transport: vals[0] }
      }
    None => ()
  }
  match matches.values.get("port") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, port: @common.parse_int(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("host") {
    Some(vals) => if vals.length() > 0 { config = { ..config, host: vals[0] } }
    None => ()
  }
  match matches.values.get("specs-dir") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, specs_dir: vals[0] }
      }
    None => ()
  }
  match matches.values.get("workspace") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, workspace_dir: vals[0] }
      }
    None => ()
  }
  config
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "mcp",
    about="Start MCP server exposing indexion tools",
    options=[
      @argparse.OptionArg("transport", about="Transport mode: stdio, http", default_values=[
        "stdio",
      ]),
      @argparse.OptionArg("port", about="HTTP server port", default_values=[
        "3741",
      ]),
      @argparse.OptionArg("host", about="HTTP server host", default_values=[
        "127.0.0.1",
      ]),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
    ],
    positionals=[
      @argparse.PositionArg(
        "workspace",
        about="Workspace directory",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
/// Apply file config (from .indexion.toml) as defaults.
/// CLI-explicit values (non-default) take precedence over file config.
pub fn McpConfig::apply_file_config(
  self : McpConfig,
  file : @config.McpFileConfig,
) -> McpConfig {
  let defaults = McpConfig::default()
  let mut config = self
  match file.transport {
    Some(v) =>
      if config.transport == defaults.transport {
        config = { ..config, transport: v }
      }
    None => ()
  }
  match file.port {
    Some(v) =>
      if config.port == defaults.port {
        config = { ..config, port: v }
      }
    None => ()
  }
  match file.host {
    Some(v) =>
      if config.host == defaults.host {
        config = { ..config, host: v }
      }
    None => ()
  }
  match file.specs_dir {
    Some(v) =>
      if config.specs_dir == defaults.specs_dir {
        config = { ..config, specs_dir: v }
      }
    None => ()
  }
  config
}

///|
fn load_mcp_file_config() -> @config.McpFileConfig {
  let config_path = @config.find_indexion_config_path(".")
  @config.load_effective_mcp_config(config_path)
}

///|
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = McpConfig::from_matches(matches).apply_file_config(
    load_mcp_file_config(),
  )
  let server = build_server(config)
  match config.transport {
    "http" => @transport.run_http(server, host=config.host, port=config.port)
    _ =>
      // Default: stdio
      @transport.run_stdio(server, @async_stdio.stdin)
  }
}
