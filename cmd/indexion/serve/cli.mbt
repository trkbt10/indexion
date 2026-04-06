///|
/// # indexion serve
///
/// Start HTTP server for codebase search queries.
/// Serves digest index queries and code graph data via REST API.
/// Supports live rebuild via POST /api/digest/rebuild.

///|
pub struct ServeConfig {
  port : Int
  host : String
  index_dir : String
  static_dir : String
  workspace_dir : String
  provider : String
  dim : Int
  strategy : String
  specs_dir : String
  cors : Bool
  api_key_env : String
  api_base_url : String
  model : String
  watch_stdin : Bool
}

///|
pub fn ServeConfig::default() -> ServeConfig {
  {
    port: 3741,
    host: "127.0.0.1",
    index_dir: @dconfig.DEFAULT_INDEX_DIR,
    static_dir: "",
    workspace_dir: ".",
    provider: "auto",
    dim: @dconfig.DEFAULT_TFIDF_DIM,
    strategy: "hnsw",
    specs_dir: "kgfs",
    cors: false,
    api_key_env: @dconfig.DEFAULT_API_KEY_ENV,
    api_base_url: @dconfig.DEFAULT_API_BASE_URL,
    model: @dconfig.DEFAULT_EMBEDDING_MODEL,
    watch_stdin: false,
  }
}

///|
pub fn ServeConfig::from_matches(matches : @argparse.Matches) -> ServeConfig {
  let mut config = ServeConfig::default()
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
  match matches.values.get("index-dir") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, index_dir: vals[0] }
      }
    None => ()
  }
  match matches.values.get("static-dir") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, static_dir: vals[0] }
      }
    None => ()
  }
  match matches.values.get("provider") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, provider: vals[0] }
      }
    None => ()
  }
  match matches.values.get("dim") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, dim: @common.parse_int(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("strategy") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, strategy: vals[0] }
      }
    None => ()
  }
  match matches.values.get("specs") {
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
  if matches.flags.get("cors").unwrap_or(false) {
    config = { ..config, cors: true }
  }
  if matches.flags.get("watch-stdin").unwrap_or(false) {
    config = { ..config, watch_stdin: true }
  }
  config
}

///|
fn serve_options() -> Array[@argparse.OptionArg] {
  let dim_default = @dconfig.DEFAULT_TFIDF_DIM.to_string()
  [
    @argparse.OptionArg("port", about="Server port", default_values=["3741"]),
    @argparse.OptionArg("host", about="Server host", default_values=[
      "127.0.0.1",
    ]),
    @argparse.OptionArg("index-dir", about="Digest index directory", default_values=[
      @dconfig.DEFAULT_INDEX_DIR,
    ]),
    @argparse.OptionArg(
      "static-dir",
      about="Static files directory for SPA serving",
    ),
    @argparse.OptionArg(
      "provider",
      about="Embedding provider: tfidf, openai, auto",
      default_values=["auto"],
    ),
    @argparse.OptionArg(
      "dim",
      about="Embedding dimension (default: 256 for tfidf, 1536 for openai)",
      default_values=[dim_default],
    ),
    @argparse.OptionArg("strategy", about="vcdb: bruteforce, hnsw, ivf", default_values=[
      "hnsw",
    ]),
    @argparse.OptionArg("specs", about="KGF specs directory", default_values=[
      "kgfs",
    ]),
  ]
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "serve",
    about="Start HTTP server for codebase search",
    options=serve_options(),
    flags=[
      @argparse.FlagArg("cors", about="Enable CORS headers"),
      @argparse.FlagArg(
        "watch-stdin",
        about="Exit when stdin is closed (for IDE integration)",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "workspace",
        about="Workspace directory",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
    subcommands=[
      @argparse.Command(
        "export",
        about="Export self-contained static site (wiki + explorer) for GitHub Pages",
        options={
          let opts = serve_options()
          opts.push(
            @argparse.OptionArg("output", about="Output directory", default_values=[
              "dist/pages",
            ]),
          )
          opts
        },
        positionals=[
          @argparse.PositionArg(
            "workspace",
            about="Workspace directory",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      ),
    ],
  )
}

///|
/// Mutable server state — replaced atomically on rebuild.
priv struct ServerState {
  mut graph_json : String
  mut index : @index.DigestIndex
  mut index_json : String
  mut stats_json : String
  mut digest_config : @dconfig.DigestConfig
  mut wiki : @wiki_types.WikiData
  mut wiki_search : @wiki_search.WikiSearchIndex?
}

///|
/// Apply DigestFileConfig from .indexion.toml as defaults for serve.
/// CLI-explicit values (non-default) take precedence over file config.
pub fn ServeConfig::apply_file_config(
  self : ServeConfig,
  file : @config.DigestFileConfig,
) -> ServeConfig {
  let defaults = ServeConfig::default()
  let mut config = self
  match file.provider {
    Some(v) =>
      if config.provider == defaults.provider {
        config = { ..config, provider: v }
      }
    None => ()
  }
  match file.strategy {
    Some(v) =>
      if config.strategy == defaults.strategy {
        config = { ..config, strategy: v }
      }
    None => ()
  }
  match file.dim {
    Some(v) => if config.dim == defaults.dim { config = { ..config, dim: v } }
    None => ()
  }
  match file.api_key_env {
    Some(v) =>
      if config.api_key_env == defaults.api_key_env {
        config = { ..config, api_key_env: v }
      }
    None => ()
  }
  match file.api_base_url {
    Some(v) =>
      if config.api_base_url == defaults.api_base_url {
        config = { ..config, api_base_url: v }
      }
    None => ()
  }
  match file.model {
    Some(v) =>
      if config.model == defaults.model {
        config = { ..config, model: v }
      }
    None => ()
  }
  config
}

///|
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  // Dispatch to subcommand if present
  match matches.subcommand {
    Some(("export", sub)) => {
      run_export(sub)
      return
    }
    _ => ()
  }
  let merged = ServeConfig::from_matches(matches).apply_file_config(
    @digest_cli.load_digest_file_config(),
  )
  let resolved_index_dir : String? = if merged.index_dir ==
    @dconfig.DEFAULT_INDEX_DIR {
    @config.resolve_project_indexion_dir(merged.workspace_dir, "digest")
  } else {
    Some(merged.index_dir)
  }
  let config = {
    ..merged,
    index_dir: match resolved_index_dir {
      Some(dir) => dir
      None => "" // no project root — skip index loading
    },
  }
  let digest_cli_config = make_digest_cli_config(config)
  let digest_config = @digest_cli.build_digest_config(digest_cli_config)
  // Try to load existing index if project root was found.
  // Users can explicitly build via POST /api/digest/rebuild.
  let state = if resolved_index_dir is None {
    None
  } else {
    do_load(config, digest_cli_config, digest_config)
  }
  let state = match state {
    Some(s) => s
    None => {
      if resolved_index_dir is None {
        @digest_cli.log_progress(
          "No project root found. Server starts without digest index.",
        )
      } else {
        @digest_cli.log_progress(
          "No existing index found. Use POST /api/digest/rebuild to build.",
        )
      }
      let provider = @digest_cli.resolve_provider(digest_cli_config)
      let (wiki, wiki_search) = load_wiki_pages(config, provider)
      let empty_index = @index.DigestIndex::load_or_create(
        config.index_dir,
        digest_config,
      )
      ServerState::{
        graph_json: "{}",
        index: empty_index,
        index_json: "[]",
        stats_json: "{}",
        digest_config,
        wiki,
        wiki_search,
      }
    }
  }
  // Build GET route table (SoT for API paths)
  let get_routes = build_get_routes(state, config)
  // Start HTTP server
  let server = @mhttp.Server::new(host=config.host, port=config.port) catch {
    err => {
      @digest_cli.log_error("Server init failed: " + err.to_string())
      return
    }
  }
  let listen_port = server.port()
  println("Serving on http://" + config.host + ":" + listen_port.to_string())
  if config.watch_stdin {
    println("Watching stdin — will exit on EOF.")
  } else {
    println("Press Ctrl+C to stop.")
  }
  server.run_forever(
    (req, body, conn) => {
      let path = strip_query_string(req.path)
      let cors_enabled = config.cors
      // CORS preflight
      if req.meth == @mhttp.Options && path.has_prefix("/api/") {
        conn.skip_request_body()
        send_cors_preflight(conn, cors_enabled)
        return
      }
      // GET API routes — served from the route table (SoT)
      if req.meth == @mhttp.Get && path.has_prefix("/api/") {
        conn.skip_request_body()
        match get_routes.get(path) {
          Some(data) => {
            send_json_ok(conn, data, cors_enabled)
            return
          }
          None => ()
        }
        // Not in route table — fall through to POST handlers / static / 404
      }
      // POST endpoints (not in route table — these are dynamic)
      if req.meth == @mhttp.Post && path == "/api/digest/rebuild" {
        conn.skip_request_body()
        handle_rebuild(
          conn, state, config, digest_cli_config, digest_config, cors_enabled, get_routes,
        )
        return
      }
      if req.meth == @mhttp.Post && path == "/api/digest/query" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_digest_query(
          conn,
          body_text,
          state.index,
          state.digest_config,
          cors_enabled,
        )
        return
      }
      if req.meth == @mhttp.Post && path == "/api/wiki/search" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_wiki_search(conn, body_text, state.wiki_search, cors_enabled)
        return
      }
      // Explore endpoint
      if req.meth == @mhttp.Post && path == "/api/explore" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_explore(conn, body_text, config, cors_enabled)
        return
      }
      // KGF POST endpoints
      if req.meth == @mhttp.Post && path == "/api/kgf/tokens" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_kgf_tokens(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/kgf/edges" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_kgf_edges(conn, body_text, config, cors_enabled)
        return
      }
      // Doc graph endpoint
      if req.meth == @mhttp.Post && path == "/api/doc/graph" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_doc_graph(conn, body_text, config, cors_enabled)
        return
      }
      // Plan endpoints
      if req.meth == @mhttp.Post && path == "/api/plan/refactor" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_refactor(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/plan/documentation" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_documentation(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/plan/reconcile" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_reconcile(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/plan/solid" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_solid(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/plan/unwrap" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_unwrap(conn, body_text, config, cors_enabled)
        return
      }
      if req.meth == @mhttp.Post && path == "/api/plan/readme" {
        let body_data = body.read_all()
        let body_text = body_data.text()
        handle_plan_readme(conn, body_text, config, cors_enabled)
        return
      }
      // Static file serving
      let effective_static_dir = if config.static_dir != "" {
        config.static_dir
      } else {
        match @config.get_wiki_install_dir() {
          Some(dir) =>
            if @fs.path_exists(dir + "/index.html") {
              dir
            } else {
              ""
            }
          None => ""
        }
      }
      if effective_static_dir != "" &&
        req.meth == @mhttp.Get &&
        !path.has_prefix("/api/") {
        conn.skip_request_body()
        serve_static(conn, effective_static_dir, path)
        return
      }
      // 404
      conn.skip_request_body()
      send_json_error(conn, 404, "Not Found", cors_enabled)
    },
    allow_failure=true,
  ) catch {
    err => @digest_cli.log_error("Server failed: " + err.to_string())
  }
}

///|
fn make_digest_cli_config(config : ServeConfig) -> @digest_cli.CliConfig {
  {
    command: "",
    input_path: config.workspace_dir,
    purpose: "",
    index_dir: config.index_dir,
    provider: config.provider,
    dim: config.dim,
    strategy: config.strategy,
    top_k: 10,
    min_score: 0.1,
    specs_dir: config.specs_dir,
    api_key_env: config.api_key_env,
    api_base_url: config.api_base_url,
    model: config.model,
    source_dir: config.workspace_dir,
    no_update: false,
  }
}

///|
/// Load existing index from disk. Returns None if files don't exist.
async fn do_load(
  config : ServeConfig,
  digest_cli_config : @digest_cli.CliConfig,
  digest_config : @dconfig.DigestConfig,
) -> ServerState? {
  let mp = @dconfig.manifest_path(config.index_dir)
  let gp = @dconfig.graph_path(config.index_dir)
  if !@fs.path_exists(mp) || !@fs.path_exists(gp) {
    return None
  }
  @digest_cli.log_progress("Loading index from " + config.index_dir + "...")
  let graph_json = @fs.read_file_to_string(gp) catch {
    _ => return None
  }
  let graph = match @graph.CodeGraph::from_json_string(graph_json) {
    Some(g) => g
    None => return None
  }
  @digest_cli.log_progress(
    "Graph: " + graph.symbol_count().to_string() + " symbols",
  )
  let index = @index.DigestIndex::load_or_create(config.index_dir, digest_config)
  // Populate units from graph (incremental — skips unchanged)
  let _ = index.build_with_config(graph, digest_config) catch {
    _ => return None
  }
  let provider = @digest_cli.resolve_provider(digest_cli_config)
  let index_json = build_index_json(index)
  let stats_json = build_stats_json(graph, config.index_dir, digest_config)
  @digest_cli.log_progress(
    "Ready: " + index.units.length().to_string() + " functions indexed.",
  )
  let (wiki, wiki_search) = load_wiki_pages(config, provider)
  Some(ServerState::{
    graph_json,
    index,
    index_json,
    stats_json,
    digest_config,
    wiki,
    wiki_search,
  })
}

///|
/// Build graph + digest index from source. Returns None on failure.
async fn do_build(
  config : ServeConfig,
  digest_cli_config : @digest_cli.CliConfig,
  digest_config : @dconfig.DigestConfig,
) -> ServerState? {
  @digest_cli.log_progress("Building from " + config.workspace_dir + "...")
  // Build graph from source
  let build_result = match
    @digest_cli.build_graph_from_source(config.workspace_dir, config.specs_dir) {
    Some(r) => r
    None => {
      @digest_cli.log_error(
        "Failed to build graph from " + config.workspace_dir,
      )
      return None
    }
  }
  let graph = build_result.graph
  let file_hashes : Map[String, @cas_types.ContentHash]? = Some(
    build_result.file_hashes,
  )
  let graph_json = graph.to_json_string()
  @digest_cli.log_progress(
    "Graph: " + graph.symbol_count().to_string() + " symbols",
  )
  // Load existing index for incremental update, or create new
  let index = @index.DigestIndex::load_or_create(config.index_dir, digest_config)
  // Build — this is incremental: file hashes detect unchanged files
  let result = index.build_with_config(graph, digest_config, file_hashes~) catch {
    @embed.ParseError(msg) => {
      @digest_cli.log_error("Build error: " + msg)
      return None
    }
    @embed.ApiError(code, msg) => {
      @digest_cli.log_error(
        "Build API error (" + code.to_string() + "): " + msg,
      )
      return None
    }
    @embed.NoResult => {
      @digest_cli.log_error("Build: no embedding result")
      return None
    }
  }
  @digest_cli.log_progress(
    "Indexed: " +
    result.indexed_count.to_string() +
    ", skipped: " +
    result.skipped_count.to_string() +
    ", removed: " +
    result.removed_count.to_string(),
  )
  // Persist to disk using save_to_dir (SoT for persistence)
  let save_errors = index.save_to_dir(config.index_dir, graph)
  for err in save_errors {
    @digest_cli.log_error(err)
  }
  if save_errors.length() > 0 {
    return None
  }
  let provider = @digest_cli.resolve_provider(digest_cli_config)
  let index_json = build_index_json(index)
  let stats_json = build_stats_json(graph, config.index_dir, digest_config)
  @digest_cli.log_progress(
    "Ready: " + index.units.length().to_string() + " functions indexed.",
  )
  let (wiki, wiki_search) = load_wiki_pages(config, provider)
  Some(ServerState::{
    graph_json,
    index,
    index_json,
    stats_json,
    digest_config,
    wiki,
    wiki_search,
  })
}

///|
async fn handle_rebuild(
  conn : @mhttp.ServerConnection,
  state : ServerState,
  config : ServeConfig,
  digest_cli_config : @digest_cli.CliConfig,
  digest_config : @dconfig.DigestConfig,
  cors : Bool,
  get_routes : Map[String, String],
) -> Unit {
  match do_build(config, digest_cli_config, digest_config) {
    Some(new_state) => {
      state.graph_json = new_state.graph_json
      state.index = new_state.index
      state.index_json = new_state.index_json
      state.stats_json = new_state.stats_json
      state.digest_config = new_state.digest_config
      state.wiki = new_state.wiki
      state.wiki_search = new_state.wiki_search
      // Refresh the GET route table from updated state
      let fresh = build_get_routes(state, config)
      fresh.each(fn(k, v) { get_routes[k] = v })
      let msg = "{\"rebuilt\":true,\"functions\":" +
        state.index.units.length().to_string() +
        "}"
      send_json_ok(conn, msg, cors)
    }
    None => send_json_error(conn, 500, "Rebuild failed", cors)
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
fn json_headers(cors : Bool) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["content-type"] = "application/json; charset=utf-8"
  if cors {
    headers["access-control-allow-origin"] = "*"
    headers["access-control-allow-methods"] = "GET, POST, OPTIONS"
    headers["access-control-allow-headers"] = "Content-Type"
  }
  headers
}

///|
async fn send_json_ok(
  conn : @mhttp.ServerConnection,
  data_json : String,
  cors : Bool,
) -> Unit {
  let response = "{\"ok\":true,\"data\":" + data_json + "}"
  conn.send_response(200, "OK", extra_headers=json_headers(cors)) catch {
    _ => return
  }
  conn.write(response)
  conn.end_response() catch {
    _ => ()
  }
}

///|
async fn send_json_error(
  conn : @mhttp.ServerConnection,
  code : Int,
  msg : String,
  cors : Bool,
) -> Unit {
  let response = "{\"ok\":false,\"error\":" +
    Json::string(msg).stringify() +
    "}"
  let reason = match code {
    400 => "Bad Request"
    404 => "Not Found"
    500 => "Internal Server Error"
    _ => "Error"
  }
  conn.send_response(code, reason, extra_headers=json_headers(cors)) catch {
    _ => return
  }
  conn.write(response)
  conn.end_response() catch {
    _ => ()
  }
}

///|
async fn send_cors_preflight(
  conn : @mhttp.ServerConnection,
  cors : Bool,
) -> Unit {
  let headers = json_headers(cors)
  conn.send_response(204, "No Content", extra_headers=headers) catch {
    _ => return
  }
  conn.end_response() catch {
    _ => ()
  }
}

///|
async fn handle_digest_query(
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
  // Cascade: try remote providers first, fall back to local
  let hits = serve_query_cascade(index, digest_config, purpose, top_k)
  let results : Array[Json] = []
  for hit in hits {
    if hit.score >= min_score {
      results.push(query_hit_to_json(hit))
    }
  }
  send_json_ok(conn, Json::array(results).stringify(), cors)
}

///|
fn query_hit_to_json(hit : @types.QueryHit) -> Json {
  let obj : Map[String, Json] = {}
  obj.set("name", hit.function.name().to_json())
  obj.set("file", hit.function.module_id.to_json())
  obj.set("score", hit.score.to_json())
  let summary = match hit.function.symbol.doc {
    Some(doc) => doc
    None =>
      match hit.function.impression {
        Some(imp) => imp.summary
        None => ""
      }
  }
  obj.set("summary", summary.to_json())
  Json::object(obj)
}

///|
/// Cascade query through providers: remote first, then local.
async fn serve_query_cascade(
  index : @index.DigestIndex,
  digest_config : @dconfig.DigestConfig,
  purpose : String,
  top_k : Int,
) -> Array[@types.QueryHit] {
  for p in digest_config.providers {
    if p.kind == "remote" && index.has_provider(p.key) {
      match p.api_config {
        Some(api_config) => {
          let hits = try {
            index.query_api(purpose, top_k, p.key, api_config)
          } catch {
            _ => continue
          }
          return hits
        }
        None => ()
      }
    }
  }
  for p in digest_config.providers {
    if p.kind == "tfidf" && index.has_provider(p.key) {
      return index.query_local(purpose, top_k, p.key)
    }
  }
  []
}

///|
fn build_stats_json(
  graph : @graph.CodeGraph,
  index_dir : String,
  digest_config : @dconfig.DigestConfig,
) -> String {
  let parts : Array[String] = []
  for p in digest_config.providers {
    parts.push(p.key + " (" + p.dim.to_string() + " dims)")
  }
  let provider_desc = if parts.length() > 0 {
    parts.join(" + ")
  } else {
    "none"
  }
  let obj : Map[String, Json] = {}
  obj.set("indexDirectory", index_dir.to_json())
  obj.set("provider", provider_desc.to_json())
  let provider_arr : Array[Json] = []
  for p in digest_config.providers {
    let po : Map[String, Json] = {}
    po.set("key", p.key.to_json())
    po.set("kind", p.kind.to_json())
    po.set("dim", p.dim.to_json())
    provider_arr.push(Json::object(po))
  }
  obj.set("providers", Json::array(provider_arr))
  obj.set("totalSymbols", graph.symbol_count().to_json())
  obj.set("totalModules", graph.module_count().to_json())
  obj.set("totalEdges", graph.edge_count().to_json())
  Json::object(obj).stringify()
}

///|
fn function_unit_to_json(unit : @types.FunctionUnit) -> Json {
  let obj : Map[String, Json] = {}
  obj.set("id", unit.id().to_json())
  obj.set("name", unit.name().to_json())
  obj.set("module", unit.module_id.to_json())
  obj.set("kind", unit.symbol.kind.to_json())
  match unit.symbol.doc {
    Some(d) => obj.set("doc", d.to_json())
    None => obj.set("doc", Json::null())
  }
  match unit.impression {
    Some(imp) => {
      obj.set("summary", imp.summary.to_json())
      obj.set(
        "keywords",
        Json::array(imp.keywords.iter().map(fn(k) { k.to_json() }).collect()),
      )
    }
    None => {
      obj.set("summary", Json::null())
      obj.set("keywords", Json::array([]))
    }
  }
  obj.set(
    "callers",
    Json::array(unit.callers.iter().map(fn(c) { c.to_json() }).collect()),
  )
  obj.set(
    "callees",
    Json::array(unit.callees.iter().map(fn(c) { c.to_json() }).collect()),
  )
  obj.set("depth", unit.depth.to_json())
  Json::object(obj)
}

///|
fn build_index_json(index : @index.DigestIndex) -> String {
  let items : Array[Json] = []
  for entry in index.units {
    items.push(function_unit_to_json(entry.1))
  }
  Json::array(items).stringify()
}

///|
fn content_type_for(extension : String) -> String {
  match extension {
    ".html" => "text/html; charset=utf-8"
    ".js" => "application/javascript; charset=utf-8"
    ".css" => "text/css; charset=utf-8"
    ".json" => "application/json; charset=utf-8"
    ".svg" => "image/svg+xml"
    ".png" => "image/png"
    ".ico" => "image/x-icon"
    ".woff" => "font/woff"
    ".woff2" => "font/woff2"
    ".ttf" => "font/ttf"
    ".map" => "application/json"
    _ => "application/octet-stream"
  }
}

///|
fn get_extension(path : String) -> String {
  let mut last_dot = -1
  for i = path.length() - 1; i >= 0; i = i - 1 {
    if path[i] == '.' {
      last_dot = i
      break
    }
    if path[i] == '/' {
      break
    }
  }
  if last_dot >= 0 {
    path[last_dot:].to_string()
  } else {
    ""
  }
}

///|
async fn serve_static(
  conn : @mhttp.ServerConnection,
  static_dir : String,
  path : String,
) -> Unit {
  if path.contains("..") {
    send_static_error(conn, 403, "Forbidden")
    return
  }
  let file_path = if path == "/" {
    static_dir + "/index.html"
  } else {
    static_dir + path
  }
  if @fs.path_exists(file_path) {
    let content = @fs.read_file_to_bytes(file_path) catch {
      _ => {
        send_static_error(conn, 500, "Read error")
        return
      }
    }
    let ext = get_extension(file_path)
    let ct = content_type_for(ext)
    let headers : Map[String, String] = {}
    headers["content-type"] = ct
    conn.send_response(200, "OK", extra_headers=headers) catch {
      _ => return
    }
    conn.write(content)
    conn.end_response() catch {
      _ => ()
    }
  } else {
    let index_path = static_dir + "/index.html"
    if @fs.path_exists(index_path) {
      let content = @fs.read_file_to_bytes(index_path) catch {
        _ => {
          send_static_error(conn, 500, "Read error")
          return
        }
      }
      let headers : Map[String, String] = {}
      headers["content-type"] = "text/html; charset=utf-8"
      conn.send_response(200, "OK", extra_headers=headers) catch {
        _ => return
      }
      conn.write(content)
      conn.end_response() catch {
        _ => ()
      }
    } else {
      send_static_error(conn, 404, "Not Found")
    }
  }
}

///|
async fn send_static_error(
  conn : @mhttp.ServerConnection,
  code : Int,
  msg : String,
) -> Unit {
  let reason = match code {
    403 => "Forbidden"
    404 => "Not Found"
    _ => "Error"
  }
  conn.send_response(code, reason) catch {
    _ => return
  }
  conn.write(msg)
  conn.end_response() catch {
    _ => ()
  }
}

///|
/// Build a lookup table of all GET API routes: path -> JSON response data.
/// This is the **single source of truth** for API paths. Used by:
///   - HTTP server: lookup on incoming GET requests
///   - `serve export`: iterate to write static files
/// Paths include the /api prefix to match incoming request paths directly.
fn build_get_routes(
  state : ServerState,
  config : ServeConfig,
) -> Map[String, String] {
  let routes : Map[String, String] = {}
  routes["/api/health"] = "{\"status\":\"ready\"}"
  routes["/api/config"] = build_config_json(config)
  routes["/api/graph"] = state.graph_json
  routes["/api/digest/index"] = state.index_json
  routes["/api/digest/stats"] = state.stats_json
  routes["/api/wiki/nav"] = state.wiki.nav.to_json().stringify()
  routes["/api/kgf/list"] = @kgf_cli.list_specs_json()
  @kgf_cli.all_specs_content().each(fn(name, content) {
    routes["/api/kgf/specs/" + name] = content.to_json().stringify()
  })
  state.wiki.pages.each(fn(id, page) {
    routes["/api/wiki/pages/" + id] = page.to_json().stringify()
  })
  routes
}
