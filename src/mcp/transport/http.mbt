///|
/// # MCP Streamable HTTP transport
///
/// Serves MCP over HTTP using the Streamable HTTP transport defined
/// in the MCP 2025-03-26 specification.
///
/// Endpoint: POST /mcp
/// Content-Type: application/json
/// Response: application/json (single JSON-RPC response)
///
/// Also supports:
/// - GET /mcp for SSE (server-sent events) — future extension
/// - DELETE /mcp for session termination — future extension

///|
/// Run the MCP server over HTTP transport.
pub async fn run_http(
  server : @server.McpServer,
  host? : String = "127.0.0.1",
  port? : Int = 3741,
) -> Unit {
  let http_server = @mhttp.Server::new(host~, port~, reuse_addr=true) catch {
    err => {
      println("MCP HTTP server init failed: " + @debug.to_string(err))
      return
    }
  }
  let listen_port = http_server.port()
  // Log to stderr so stdout remains clean for any future stdio needs
  eprintln(
    "MCP server listening on http://" +
    host +
    ":" +
    listen_port.to_string() +
    "/mcp",
  )
  http_server.run_forever(
    async fn(req, body, conn) {
      let path = strip_query_string(req.path)
      // CORS preflight
      if req.meth == @mhttp.Options && path == "/mcp" {
        send_cors_preflight(conn)
        return
      }
      // MCP endpoint
      if req.meth == @mhttp.Post && path == "/mcp" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_mcp_post(server, conn, body_text)
        return
      }
      // Health check
      if req.meth == @mhttp.Get && path == "/health" {
        conn.skip_request_body()
        let headers : Map[String, String] = {}
        headers["content-type"] = "application/json"
        conn.send_response(200, "OK", extra_headers=headers) catch {
          _ => return
        }
        conn.write("{\"status\":\"ok\"}")
        conn.end_response() catch {
          _ => ()
        }
        return
      }
      // 404
      conn.skip_request_body()
      let headers : Map[String, String] = {}
      headers["content-type"] = "application/json"
      conn.send_response(404, "Not Found", extra_headers=headers) catch {
        _ => return
      }
      conn.write("{\"error\":\"Not Found\"}")
      conn.end_response() catch {
        _ => ()
      }
    },
    allow_failure=true,
  ) catch {
    err => eprintln("MCP HTTP server failed: " + @debug.to_string(err))
  }
}

///|
async fn handle_mcp_post(
  server : @server.McpServer,
  conn : @mhttp.ServerConnection,
  body_text : String,
) -> Unit {
  match server.handle_message(body_text) {
    Some(response) => {
      let headers : Map[String, String] = {}
      headers["content-type"] = "application/json"
      headers["access-control-allow-origin"] = "*"
      headers["access-control-allow-methods"] = "POST, OPTIONS"
      headers["access-control-allow-headers"] = "Content-Type"
      conn.send_response(200, "OK", extra_headers=headers) catch {
        _ => return
      }
      conn.write(response)
      conn.end_response() catch {
        _ => ()
      }
    }
    None => {
      // Notification — respond with 202 Accepted (no body)
      let headers : Map[String, String] = {}
      headers["access-control-allow-origin"] = "*"
      conn.send_response(202, "Accepted", extra_headers=headers) catch {
        _ => return
      }
      conn.end_response() catch {
        _ => ()
      }
    }
  }
}

///|
async fn send_cors_preflight(conn : @mhttp.ServerConnection) -> Unit {
  let headers : Map[String, String] = {}
  headers["access-control-allow-origin"] = "*"
  headers["access-control-allow-methods"] = "POST, OPTIONS"
  headers["access-control-allow-headers"] = "Content-Type"
  conn.send_response(204, "No Content", extra_headers=headers) catch {
    _ => return
  }
  conn.end_response() catch {
    _ => ()
  }
}

///|
fn strip_query_string(path : String) -> String {
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '?' {
      return path[:i].to_string()
    }
  }
  path
}

///|
fn eprintln(msg : String) -> Unit {
  // Write to stderr via platform println fallback
  // For now, use println — the CLI command layer will handle redirection
  println(msg)
}
