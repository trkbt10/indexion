///|
/// # JSON-RPC 2.0 protocol layer for MCP
///
/// Parses and serializes JSON-RPC 2.0 messages as required by the
/// Model Context Protocol specification.

///|
/// A parsed JSON-RPC 2.0 request.
pub struct JsonRpcRequest {
  jsonrpc : String
  id : Json?
  meth : String
  params : Json?
}

///|
/// Parse a JSON string into a JSON-RPC 2.0 request.
/// Returns None if the JSON is malformed or missing required fields.
pub fn JsonRpcRequest::from_json_string(text : String) -> JsonRpcRequest? {
  let json : Json = @json.parse(text) catch { _ => return None }
  JsonRpcRequest::from_json(json)
}

///|
/// Parse a Json value into a JSON-RPC 2.0 request.
pub fn JsonRpcRequest::from_json(json : Json) -> JsonRpcRequest? {
  guard json is Object(obj) else { return None }
  let meth = match obj.get("method") {
    Some(String(m)) => m
    _ => return None
  }
  let jsonrpc = match obj.get("jsonrpc") {
    Some(String(v)) => v
    _ => "2.0"
  }
  let id = obj.get("id")
  let params = obj.get("params")
  Some({ jsonrpc, id, meth, params, })
}

///|
/// Check whether this request is a notification (no id field).
pub fn JsonRpcRequest::is_notification(self : JsonRpcRequest) -> Bool {
  self.id is None
}

///|
/// Build a JSON-RPC 2.0 success response.
pub fn response_ok(id : Json?, result : Json) -> String {
  let obj : Map[String, Json] = Map([])
  obj["jsonrpc"] = "2.0".to_json()
  match id {
    Some(v) => obj["id"] = v
    None => obj["id"] = Json::null()
  }
  obj["result"] = result
  Json::object(obj).stringify()
}

///|
/// Build a JSON-RPC 2.0 error response.
pub fn response_error(
  id : Json?,
  code : Int,
  message : String,
  data? : Json? = None,
) -> String {
  let err_obj : Map[String, Json] = Map([])
  err_obj["code"] = code.to_json()
  err_obj["message"] = message.to_json()
  match data {
    Some(d) => err_obj["data"] = d
    None => ()
  }
  let obj : Map[String, Json] = Map([])
  obj["jsonrpc"] = "2.0".to_json()
  match id {
    Some(v) => obj["id"] = v
    None => obj["id"] = Json::null()
  }
  obj["error"] = Json::object(err_obj)
  Json::object(obj).stringify()
}

///|
/// Standard JSON-RPC 2.0 error codes.
pub let parse_error : Int = -32700

///|
pub let invalid_request : Int = -32600

///|
pub let method_not_found : Int = -32601

///|
pub let invalid_params : Int = -32602

///|
pub let internal_error : Int = -32603
