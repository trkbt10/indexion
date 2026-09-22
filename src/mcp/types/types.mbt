///|
/// # MCP type definitions
///
/// Core types for the Model Context Protocol (MCP) 2025-03-26 spec.
/// Defines tool schemas, server capabilities, and content types.

///|
/// JSON Schema for a tool's input parameters.
pub(all) struct InputSchema {
  properties : Map[String, PropertySchema]
  required : Array[String]
}

///|
/// Schema for a single property in a tool's input.
pub(all) struct PropertySchema {
  type_ : String
  description : String
  enum_values : Array[String]
  items : PropertySchema?
  default : String
}

///|
/// An MCP tool definition exposed by this server.
pub(all) struct ToolDefinition {
  name : String
  description : String
  input_schema : InputSchema
}

///|
/// Serialize an InputSchema to JSON.
pub fn InputSchema::to_json(self : InputSchema) -> Json {
  let props : Map[String, Json] = Map([])
  self.properties.each(fn(key, schema) { props[key] = schema.to_json() })
  let obj : Map[String, Json] = Map([])
  obj["type"] = "object".to_json()
  obj["properties"] = Json::object(props)
  if self.required.length() > 0 {
    obj["required"] = Json::array(
      self.required.iter().map(fn(s) { s.to_json() }).collect(),
    )
  }
  Json::object(obj)
}

///|
/// Serialize a PropertySchema to JSON.
pub fn PropertySchema::to_json(self : PropertySchema) -> Json {
  let obj : Map[String, Json] = Map([])
  // Handle array type with items
  match self.items {
    Some(item_schema) => {
      obj["type"] = "array".to_json()
      obj["items"] = item_schema.to_json()
    }
    None => obj["type"] = self.type_.to_json()
  }
  if self.description.length() > 0 {
    obj["description"] = self.description.to_json()
  }
  if self.enum_values.length() > 0 {
    obj["enum"] = Json::array(
      self.enum_values.iter().map(fn(s) { s.to_json() }).collect(),
    )
  }
  if self.default.length() > 0 {
    obj["default"] = self.default.to_json()
  }
  Json::object(obj)
}

///|
/// Serialize a ToolDefinition to JSON.
pub fn ToolDefinition::to_json(self : ToolDefinition) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = self.name.to_json()
  obj["description"] = self.description.to_json()
  obj["inputSchema"] = self.input_schema.to_json()
  Json::object(obj)
}

///|
/// Create a simple string property schema.
pub fn string_prop(
  description : String,
  default? : String = "",
) -> PropertySchema {
  { type_: "string", description, enum_values: [], items: None, default, }
}

///|
/// Create a string property schema with allowed values.
pub fn enum_prop(
  description : String,
  values : Array[String],
  default? : String = "",
) -> PropertySchema {
  { type_: "string", description, enum_values: values, items: None, default, }
}

///|
/// Create a number property schema.
pub fn number_prop(
  description : String,
  default? : String = "",
) -> PropertySchema {
  { type_: "number", description, enum_values: [], items: None, default, }
}

///|
/// Create a boolean property schema.
pub fn bool_prop(
  description : String,
  default? : String = "",
) -> PropertySchema {
  { type_: "boolean", description, enum_values: [], items: None, default, }
}

///|
/// Create a string array property schema.
pub fn string_array_prop(description : String) -> PropertySchema {
  {
    type_: "array",
    description,
    enum_values: [],
    items: Some({
      type_: "string",
      description: "",
      enum_values: [],
      items: None,
      default: "",
    }),
    default: "",
  }
}

///|
/// MCP content block — text content only (sufficient for CLI tool results).
pub(all) struct TextContent {
  text : String
  is_error : Bool
}

///|
/// Serialize a TextContent to JSON as an MCP content block.
pub fn TextContent::to_json(self : TextContent) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["type"] = "text".to_json()
  obj["text"] = self.text.to_json()
  Json::object(obj)
}

///|
/// Build a tools/call result JSON from content blocks.
pub fn call_result(
  content : Array[TextContent],
  is_error? : Bool = false,
) -> Json {
  let items = content.iter().map(fn(c) { c.to_json() }).collect()
  let obj : Map[String, Json] = Map([])
  obj["content"] = Json::array(items)
  if is_error {
    obj["isError"] = true.to_json()
  }
  Json::object(obj)
}

///|
/// Shorthand: success result with a single text block.
pub fn text_result(text : String) -> Json {
  call_result([{ text, is_error: false, }])
}

///|
/// Shorthand: error result with a single text block.
pub fn error_result(text : String) -> Json {
  call_result([{ text, is_error: true, }], is_error=true)
}

///|
/// MCP server info for the initialize response.
pub(all) struct ServerInfo {
  name : String
  version : String
}

///|
/// Serialize ServerInfo to JSON.
pub fn ServerInfo::to_json(self : ServerInfo) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = self.name.to_json()
  obj["version"] = self.version.to_json()
  Json::object(obj)
}

///|
/// Build the capabilities object for the initialize response.
/// Currently only tools capability is advertised.
pub fn server_capabilities() -> Json {
  let caps : Map[String, Json] = Map([])
  // Advertise tools capability (empty object = supported, no streaming)
  caps["tools"] = Json::object({})
  Json::object(caps)
}

///|
/// Build a complete MCP initialize result.
pub fn initialize_result(info : ServerInfo) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["protocolVersion"] = "2025-03-26".to_json()
  obj["capabilities"] = server_capabilities()
  obj["serverInfo"] = info.to_json()
  Json::object(obj)
}
