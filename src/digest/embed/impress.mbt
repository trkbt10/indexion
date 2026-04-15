// Native LLM impression generation using mizchi/x/http

///|
/// Generate impression for a function using LLM (async).
pub async fn generate_impression_with_config(
  config : @config.LlmConfig,
  name : String,
  kind : String,
  module_id : String,
  callers : Array[String],
  callees : Array[String],
) -> @types.Impression raise EmbedError {
  let headers : Map[String, String] = {}
  headers.set("Authorization", "Bearer " + config.api_key)
  headers.set("Content-Type", "application/json")
  // Build user prompt
  let callers_str = if callers.length() > 0 {
    callers.join(", ")
  } else {
    "none"
  }
  let callees_str = if callees.length() > 0 {
    callees.join(", ")
  } else {
    "none"
  }
  let user_prompt = "Function: " +
    name +
    "\nKind: " +
    kind +
    "\nModule: " +
    module_id +
    "\nCallers: " +
    callers_str +
    "\nCallees: " +
    callees_str
  // Build request body using @json
  let body = build_chat_request_json(
    config.model,
    config.system_prompt,
    user_prompt,
    config.temperature,
  )
  let (status, response_body) = @http.post_json(config.base_url, body, headers) catch {
    err => raise ApiError(0, @debug.to_string(err))
  }
  if status != 200 {
    raise ApiError(status, response_body)
  }
  parse_impression_response(response_body)
}

///|
/// Generate impression using default config (convenience wrapper).
pub async fn generate_impression(
  api_key : String,
  name : String,
  kind : String,
  module_id : String,
  callers : Array[String],
  callees : Array[String],
) -> @types.Impression raise EmbedError {
  let config = @config.LlmConfig::openai(api_key)
  generate_impression_with_config(
    config, name, kind, module_id, callers, callees,
  )
}

///|
/// Build chat completion request JSON using @json library.
fn build_chat_request_json(
  model : String,
  system_prompt : String,
  user_prompt : String,
  temperature : Double,
) -> String {
  let messages = Json::array([
    Json::object({
      "role": Json::string("system"),
      "content": Json::string(system_prompt),
    }),
    Json::object({
      "role": Json::string("user"),
      "content": Json::string(user_prompt),
    }),
  ])
  let response_format = Json::object({ "type": Json::string("json_object") })
  let request = Json::object({
    "model": Json::string(model),
    "messages": messages,
    "temperature": Json::number(temperature),
    "response_format": response_format,
  })
  request.stringify()
}

///|
/// Parse LLM response to Impression
fn parse_impression_response(
  json_str : String,
) -> @types.Impression raise EmbedError {
  let json = @json.parse(json_str) catch {
    _ => raise ParseError("Invalid JSON")
  }
  let obj = match json {
    Object(m) => m
    _ => raise ParseError("Expected object")
  }
  // Get choices[0].message.content
  let choices = match obj.get("choices") {
    Some(Array(arr)) => arr
    _ => raise ParseError("No choices")
  }
  if choices.length() == 0 {
    raise NoResult
  }
  let choice = match choices[0] {
    Object(c) => c
    _ => raise ParseError("Invalid choice")
  }
  let message = match choice.get("message") {
    Some(Object(m)) => m
    _ => raise ParseError("No message")
  }
  let content_str = match message.get("content") {
    Some(String(s)) => s
    _ => raise ParseError("No content")
  }
  // Parse the JSON content
  let content = @json.parse(content_str) catch {
    _ => raise ParseError("Invalid content JSON")
  }
  let content_obj = match content {
    Object(m) => m
    _ => raise ParseError("Content not object")
  }
  let summary = match content_obj.get("summary") {
    Some(String(s)) => s
    _ => ""
  }
  let keywords : Array[String] = []
  match content_obj.get("keywords") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          String(s) => keywords.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  @types.Impression::new(summary, keywords)
}

///|
/// Generate impressions for multiple functions with config (async).
pub async fn generate_impressions_with_config(
  config : @config.LlmConfig,
  units : Array[@types.FunctionUnit],
) -> Array[@types.FunctionUnit] raise EmbedError {
  let results : Array[@types.FunctionUnit] = []
  for unit in units {
    let impression = generate_impression_with_config(
      config,
      unit.name(),
      unit.symbol.kind,
      unit.module_id,
      unit.callers,
      unit.callees,
    )
    results.push(unit.with_impression(impression))
  }
  results
}

///|
/// Generate impressions using default config (convenience wrapper).
pub async fn generate_impressions(
  api_key : String,
  units : Array[@types.FunctionUnit],
) -> Array[@types.FunctionUnit] raise EmbedError {
  let config = @config.LlmConfig::openai(api_key)
  generate_impressions_with_config(config, units)
}
