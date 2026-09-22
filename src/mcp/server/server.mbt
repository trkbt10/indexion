///|
/// # MCP Server core
///
/// Manages tool registration and request dispatching.
/// Transport-agnostic: receives JSON-RPC messages and returns responses.

///|
/// A registered tool handler. Takes JSON params, returns a result.
/// Async to support handlers that call async commands (e.g. reconcile).
priv struct ToolHandler {
  invoke : async (Json?) -> Json
}

///|
/// A registered tool: definition + handler.
struct RegisteredTool {
  definition : @types.ToolDefinition
  handler : ToolHandler
}

///|
/// The MCP server. Holds registered tools and dispatches requests.
pub struct McpServer {
  priv info : @types.ServerInfo
  priv tools : Map[String, RegisteredTool]
  priv mut initialized : Bool
}

///|
/// Create a new MCP server with the given server info.
pub fn McpServer::new(info : @types.ServerInfo) -> McpServer {
  { info, tools: {}, initialized: false, }
}

///|
/// Register a tool with the server.
pub fn McpServer::register_tool(
  self : McpServer,
  definition : @types.ToolDefinition,
  handler : async (Json?) -> Json,
) -> Unit {
  self.tools[definition.name] = { definition, handler: { invoke: handler, }, }
}

///|
/// Handle a single JSON-RPC 2.0 request string and return the response string.
/// Returns None for notifications that need no response (e.g. notifications/initialized).
pub async fn McpServer::handle_message(
  self : McpServer,
  message : String,
) -> String? {
  let request = match @protocol.JsonRpcRequest::from_json_string(message) {
    Some(req) => req
    None =>
      return Some(
        @protocol.response_error(None, @protocol.parse_error, "Parse error"),
      )
  }
  // Notifications (no id) — process silently
  if request.is_notification() {
    self.handle_notification(request)
    return None
  }
  Some(self.dispatch(request))
}

///|
/// Handle a notification (no response expected).
fn McpServer::handle_notification(
  self : McpServer,
  request : @protocol.JsonRpcRequest,
) -> Unit {
  match request.meth {
    "notifications/initialized" => self.initialized = true
    // Ignore unknown notifications per spec
    _ => ()
  }
}

///|
/// Dispatch a request to the appropriate handler and build the response.
async fn McpServer::dispatch(
  self : McpServer,
  request : @protocol.JsonRpcRequest,
) -> String {
  // initialize and ping are always allowed
  match request.meth {
    "initialize" => return self.handle_initialize(request)
    "ping" => return @protocol.response_ok(request.id, Json::object({}))
    _ => ()
  }
  // All other methods require initialization
  if !self.initialized {
    return @protocol.response_error(
      request.id,
      @protocol.invalid_request,
      "Server not initialized",
    )
  }
  match request.meth {
    "tools/list" => self.handle_tools_list(request)
    "tools/call" => self.handle_tools_call(request)
    _ =>
      @protocol.response_error(
        request.id,
        @protocol.method_not_found,
        "Method not found: " + request.meth,
      )
  }
}

///|
fn McpServer::handle_initialize(
  self : McpServer,
  request : @protocol.JsonRpcRequest,
) -> String {
  let result = @types.initialize_result(self.info)
  @protocol.response_ok(request.id, result)
}

///|
fn McpServer::handle_tools_list(
  self : McpServer,
  request : @protocol.JsonRpcRequest,
) -> String {
  let tool_jsons : Array[Json] = []
  self.tools.each(fn(_name, registered) {
    tool_jsons.push(registered.definition.to_json())
  })
  let result : Map[String, Json] = Map([])
  result["tools"] = Json::array(tool_jsons)
  @protocol.response_ok(request.id, Json::object(result))
}

///|
async fn McpServer::handle_tools_call(
  self : McpServer,
  request : @protocol.JsonRpcRequest,
) -> String {
  // Extract tool name from params
  let params = match request.params {
    Some(Object(obj)) => obj
    _ =>
      return @protocol.response_error(
        request.id,
        @protocol.invalid_params,
        "params must be an object",
      )
  }
  let tool_name = match params.get("name") {
    Some(String(n)) => n
    _ =>
      return @protocol.response_error(
        request.id,
        @protocol.invalid_params,
        "Missing tool name",
      )
  }
  let arguments = params.get("arguments")
  // Look up the registered tool
  match self.tools.get(tool_name) {
    Some(registered) => {
      let result = (registered.handler.invoke)(arguments)
      @protocol.response_ok(request.id, result)
    }
    None =>
      @protocol.response_error(
        request.id,
        @protocol.method_not_found,
        "Unknown tool: " + tool_name,
      )
  }
}
