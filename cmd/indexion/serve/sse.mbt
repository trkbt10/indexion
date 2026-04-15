///|
/// SSE (Server-Sent Events) streaming support for search endpoints.
///
/// SSE protocol:
///   Content-Type: text/event-stream
///   Each event: data: {json}\n\n
///
/// Event types:
///   - progress: { "type":"progress", "phase":"...", "detail":"..." }
///   - item:     { "type":"item", "data":{...} }
///   - items:    { "type":"items", "data":[...] }
///   - result:   { "type":"result", "data":{...} }  (for explore — complex object)
///   - done:     { "type":"done", "total":N }
///   - error:    { "type":"error", "message":"..." }

///|
fn sse_headers(cors : Bool) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["content-type"] = "text/event-stream"
  headers["cache-control"] = "no-cache"
  headers["connection"] = "keep-alive"
  if cors {
    headers["access-control-allow-origin"] = "*"
    headers["access-control-allow-methods"] = "GET, POST, OPTIONS"
    headers["access-control-allow-headers"] = "Content-Type"
  }
  headers
}

///|
async fn sse_start(conn : @mhttp.ServerConnection, cors : Bool) -> Unit {
  conn.send_response(200, "OK", extra_headers=sse_headers(cors)) catch {
    _ => return
  }
}

///|
async fn sse_event(conn : @mhttp.ServerConnection, data : String) -> Unit {
  conn.write("data: " + data + "\n\n")
  conn.flush() catch {
    _ => ()
  }
}

///|
async fn sse_progress(
  conn : @mhttp.ServerConnection,
  phase : String,
  detail : String,
) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "progress".to_json()
  obj["phase"] = phase.to_json()
  obj["detail"] = detail.to_json()
  sse_event(conn, Json::object(obj).stringify())
}

///|
async fn sse_item(conn : @mhttp.ServerConnection, item : Json) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "item".to_json()
  obj["data"] = item
  sse_event(conn, Json::object(obj).stringify())
}

///|
async fn _sse_items(conn : @mhttp.ServerConnection, items : Json) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "items".to_json()
  obj["data"] = items
  sse_event(conn, Json::object(obj).stringify())
}

///|
async fn sse_result(conn : @mhttp.ServerConnection, data : Json) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "result".to_json()
  obj["data"] = data
  sse_event(conn, Json::object(obj).stringify())
}

///|
async fn sse_done(conn : @mhttp.ServerConnection, total : Int) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "done".to_json()
  obj["total"] = total.to_json()
  sse_event(conn, Json::object(obj).stringify())
  conn.end_response() catch {
    _ => ()
  }
}

///|
async fn sse_error(conn : @mhttp.ServerConnection, message : String) -> Unit {
  let obj : Map[String, Json] = {}
  obj["type"] = "error".to_json()
  obj["message"] = message.to_json()
  sse_event(conn, Json::object(obj).stringify())
  conn.end_response() catch {
    _ => ()
  }
}

// ─── Streaming Grep ────────────────────────────────────

///|
async fn handle_grep_stream(
  conn : @mhttp.ServerConnection,
  body_text : String,
  config : ServeConfig,
  cors : Bool,
) -> Unit {
  let json : Json = @json.parse(body_text) catch {
    _ => {
      send_json_error(conn, 400, "Invalid JSON body", cors)
      return
    }
  }
  let grep_config : @grep_cli.GrepConfig = {
    pattern: json_string(json, "pattern", ""),
    paths: {
      let p = json_string_array(json, "paths")
      if p.length() > 0 {
        for dir in p {
          if !validate_path(dir) {
            send_json_error(conn, 400, "Invalid path", cors)
            return
          }
        }
        p
      } else {
        [config.workspace_dir]
      }
    },
    includes: json_string_array(json, "includes"),
    excludes: json_string_array(json, "excludes"),
    specs_dir: config.specs_dir,
    semantic: json_string(json, "semantic", ""),
    undocumented: json_bool(json, "undocumented", false),
    context_lines: 0,
    count_only: false,
    files_only: false,
  }
  // Start SSE
  sse_start(conn, cors)
  sse_progress(conn, "searching", "Running grep...")
  @async.sleep(0)
  // Prepare search: load registry, collect files, parse matchers
  let paths = if grep_config.paths.length() == 0 {
    [config.workspace_dir]
  } else {
    grep_config.paths
  }
  match @grep_cli.prepare_pattern_search(paths, grep_config) {
    None => {
      sse_error(conn, "Pattern or semantic query required")
      return
    }
    Some((registry, files, matchers)) => {
      // Process files one at a time, yielding between each file
      // so the event loop can serve other requests (health, wiki, etc).
      let mut total = 0
      for i, file in files {
        let (path, content) = file
        let items = @grep_cli.grep_single_file(
          path, content, matchers, registry,
        )
        for item in items {
          sse_item(conn, item)
          total = total + 1
        }
        // Yield every few files to let other connections be served.
        if i % 5 == 4 {
          @async.sleep(0)
        }
      }
      sse_done(conn, total)
    }
  }
}

// ─── Streaming Search ──────────────────────────────────

///|
async fn handle_search_stream(
  conn : @mhttp.ServerConnection,
  body_text : String,
  state : ServerState,
  cors : Bool,
) -> Unit {
  let json : Json = @json.parse(body_text) catch {
    _ => {
      send_json_error(conn, 400, "Invalid JSON body", cors)
      return
    }
  }
  let query = json_string(json, "query", "")
  if query.length() == 0 {
    send_json_error(conn, 400, "query is required", cors)
    return
  }
  let top_k = json_double(json, "topK", 20.0).to_int()
  let min_score = json_double(json, "minScore", 0.05)
  // Start SSE
  sse_start(conn, cors)
  sse_progress(conn, "searching", "Querying digest index...")
  @async.sleep(0)
  // Query the pre-built digest index directly — no corpus rebuild.
  let hits = serve_query_cascade(state.index, state.digest_config, query, top_k)
  let mut total = 0
  for i, hit in hits {
    if hit.score >= min_score {
      sse_item(conn, query_hit_to_search_json(hit))
      total = total + 1
    }
    if i % 50 == 49 {
      @async.sleep(0)
    }
  }
  sse_done(conn, total)
}

// ─── Streaming Explore ─────────────────────────────────

///|
async fn handle_explore_stream(
  conn : @mhttp.ServerConnection,
  body_text : String,
  config : ServeConfig,
  cors : Bool,
) -> Unit {
  let json : Json = @json.parse(body_text) catch {
    _ => {
      send_json_error(conn, 400, "Invalid JSON body", cors)
      return
    }
  }
  let target_dirs = json_string_array(json, "targetDirs")
  if target_dirs.length() == 0 {
    send_json_error(conn, 400, "targetDirs is required", cors)
    return
  }
  for dir in target_dirs {
    if !validate_path(dir) {
      send_json_error(conn, 400, "Invalid path", cors)
      return
    }
  }
  // Start SSE
  sse_start(conn, cors)
  sse_progress(conn, "scanning", "Collecting files...")
  let explore_config : @explore_cli.ExploreConfig = {
    target_dirs,
    format: "json",
    strategy: json_string(json, "strategy", "tfidf"),
    threshold: json_double(json, "threshold", 0.5),
    fdr: json_double(json, "fdr", 0.0),
    extensions: json_string_array(json, "extensions"),
    includes: json_string_array(json, "includes"),
    excludes: json_string_array(json, "excludes"),
    specs_dir: config.specs_dir,
  }
  sse_progress(conn, "comparing", "Analyzing similarity...")
  @async.sleep(0)
  match @explore_cli.run_to_json(explore_config) {
    Some(result) => {
      let parsed : Json = @json.parse(result) catch { _ => Json::object({}) }
      let count = match parsed {
        Object(obj) =>
          match obj.get("pairs") {
            Some(Array(arr)) => arr.length()
            _ => 0
          }
        _ => 0
      }
      // Explore result is a complex object (files + pairs), send as single result event
      sse_result(conn, parsed)
      sse_done(conn, count)
    }
    None => sse_error(conn, "No results found")
  }
}

// ─── Streaming Digest Query ────────────────────────────

///|
async fn handle_digest_query_stream(
  conn : @mhttp.ServerConnection,
  body_text : String,
  index : @index.DigestIndex,
  digest_config : @dconfig.DigestConfig,
  cors : Bool,
) -> Unit {
  let json : Json = @json.parse(body_text) catch {
    _ => {
      send_json_error(conn, 400, "Invalid JSON body", cors)
      return
    }
  }
  let purpose = if json is { "purpose": String(p), .. } {
    p
  } else {
    send_json_error(conn, 400, "Missing 'purpose' field", cors)
    return
  }
  let top_k = if json is { "topK": Number(n, ..), .. } {
    n.to_int()
  } else {
    10
  }
  let min_score = if json is { "minScore": Number(s, ..), .. } {
    s
  } else {
    0.1
  }
  // Start SSE
  sse_start(conn, cors)
  sse_progress(conn, "querying", "Searching functions by purpose...")
  @async.sleep(0)
  let hits = serve_query_cascade(index, digest_config, purpose, top_k)
  let mut total = 0
  for i, hit in hits {
    if hit.score >= min_score {
      sse_item(conn, query_hit_to_json(hit))
      total = total + 1
    }
    if i % 50 == 49 {
      @async.sleep(0)
    }
  }
  sse_done(conn, total)
}

///|
/// Convert a digest QueryHit to the search frontend JSON format.
/// Maps digest fields to the SearchHit shape: title, source, line, kind, score.
fn query_hit_to_search_json(hit : @types.QueryHit) -> Json {
  let m : Map[String, Json] = {}
  m["id"] = hit.function.symbol.id.to_json()
  m["title"] = hit.function.name().to_json()
  m["source"] = hit.function.module_id.to_json()
  m["line"] = (0 : Int).to_json()
  m["kind"] = hit.function.symbol.kind.to_json()
  m["score"] = hit.score.to_json()
  let summary = match hit.function.symbol.doc {
    Some(doc) => doc
    None =>
      match hit.function.impression {
        Some(imp) => imp.summary
        None => ""
      }
  }
  if summary.length() > 0 {
    let attrs_json : Map[String, Json] = {}
    attrs_json["summary"] = summary.to_json()
    m["attrs"] = Json::object(attrs_json)
  }
  Json::object(m)
}

///|
/// Convert a SearchHit to the JSON format expected by the frontend.
/// Matches the structure produced by @search_cli.hits_to_json (per-item).
fn _search_hit_to_json(hit : @search_engine.SearchHit) -> Json {
  let doc = hit.document
  let m : Map[String, Json] = {}
  m["id"] = doc.id.to_json()
  m["title"] = doc.title.to_json()
  m["source"] = doc.source.to_json()
  m["line"] = doc.line.to_json()
  m["kind"] = doc.kind.to_json()
  m["score"] = hit.score.to_json()
  if !doc.attrs.is_empty() {
    let attrs_json : Map[String, Json] = {}
    for entry in doc.attrs {
      attrs_json[entry.0] = entry.1.to_json()
    }
    m["attrs"] = Json::object(attrs_json)
  }
  Json::object(m)
}
