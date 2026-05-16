///|
using @test {assert_eq}

///|
/// Initialize and mark server as ready (initialize + notifications/initialized).
async fn do_init(server : McpServer) -> Unit {
  server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{}}",
  )
  |> ignore
  server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
  |> ignore
}

///|
async test "initialize handshake" {
  let server = McpServer::new({ name: "test-server", version: "0.1.0" })
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json is { "result": { "protocolVersion": String(v), .. }, .. } else {
    fail("unexpected structure")
  }
  inspect(v, content="2025-03-26")
}

///|
async test "notification returns None" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
  assert_eq(resp, None)
}

///|
async test "tools/list requires initialization" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json is { "error": { "code": Number(code, ..), .. }, .. } else {
    fail("expected error")
  }
  inspect(code, content="-32600")
}

///|
async test "tools/list with registered tool" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  server.register_tool(
    {
      name: "search",
      description: "Search code",
      input_schema: {
        properties: { "query": @types.string_prop("Search query") },
        required: ["query"],
      },
    },
    fn(_params) { @types.text_result("found it") },
  )
  do_init(server)
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json is { "result": { "tools": Array(tools), .. }, .. } else {
    fail("unexpected structure")
  }
  inspect(tools.length(), content="1")
}

///|
async test "tools/call invokes handler" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  server.register_tool(
    {
      name: "greet",
      description: "Say hello",
      input_schema: {
        properties: { "name": @types.string_prop("Name") },
        required: ["name"],
      },
    },
    fn(params) {
      let name = match params {
        Some(Object(obj)) =>
          match obj.get("name") {
            Some(String(n)) => n
            _ => "world"
          }
        _ => "world"
      }
      @types.text_result("hello " + name)
    },
  )
  do_init(server)
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"greet\",\"arguments\":{\"name\":\"alice\"}}}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json
    is {
      "result": { "content": Array([{ "text": String(text), .. }]), .. },
      ..
    } else {
    fail("unexpected structure")
  }
  inspect(text, content="hello alice")
}

///|
async test "unknown method returns error" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  do_init(server)
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"unknown/method\"}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json is { "error": { "code": Number(code, ..), .. }, .. } else {
    fail("unexpected structure")
  }
  inspect(code, content="-32601")
}

///|
async test "ping responds with empty object" {
  let server = McpServer::new({ name: "test", version: "0.1.0" })
  let resp = server.handle_message(
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"ping\"}",
  )
  guard resp is Some(r) else { fail("expected response") }
  let json : Json = @json.parse(r)
  guard json is { "result": Object(obj), .. } else {
    fail("unexpected structure")
  }
  inspect(obj.length(), content="0")
}
