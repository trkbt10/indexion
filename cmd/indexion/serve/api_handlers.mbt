///|
/// API handlers for vscode-plugin endpoints.
/// Each handler parses JSON request body, calls the corresponding
/// command's run_to_json/run_to_string, and returns the result.

///|
/// Validate that a path does not contain path traversal sequences.
fn validate_path(path : String) -> Bool {
  !path.contains("..")
}

///|
/// Extract a string field from parsed JSON, with a default.
fn json_string(json : Json, key : String, default : String) -> String {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// Extract a double field from parsed JSON, with a default.
fn json_double(json : Json, key : String, default : Double) -> Double {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

///|
/// Extract a string array from parsed JSON, with a default.
fn json_string_array(json : Json, key : String) -> Array[String] {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(arr)) => {
          let result : Array[String] = []
          for item in arr {
            match item {
              String(s) => result.push(s)
              _ => ()
            }
          }
          result
        }
        _ => []
      }
    _ => []
  }
}

///|
/// Extract a bool field from parsed JSON, with a default.
fn json_bool(json : Json, key : String, default : Bool) -> Bool {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
async fn handle_explore(
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
  match @explore_cli.run_to_json(explore_config) {
    Some(result) => send_json_ok(conn, result, cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_kgf_tokens(
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
  let file = json_string(json, "file", "")
  if file.length() == 0 || !validate_path(file) {
    send_json_error(conn, 400, "Valid file path required", cors)
    return
  }
  let spec = json_string(json, "spec", "")
  match @kgf_cli.tokenize_json(file, spec, config.specs_dir) {
    Some(result) => send_json_ok(conn, result, cors)
    None => send_json_error(conn, 404, "Failed to tokenize file", cors)
  }
}

///|
async fn handle_kgf_edges(
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
  let file = json_string(json, "file", "")
  if file.length() == 0 || !validate_path(file) {
    send_json_error(conn, 400, "Valid file path required", cors)
    return
  }
  let spec = json_string(json, "spec", "")
  match @kgf_cli.edges_json(file, spec, config.specs_dir) {
    Some(result) => send_json_ok(conn, result, cors)
    None => send_json_error(conn, 404, "Failed to extract edges", cors)
  }
}

///|
async fn handle_doc_graph(
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
  let input_paths = json_string_array(json, "inputPaths")
  if input_paths.length() == 0 {
    send_json_error(conn, 400, "inputPaths is required", cors)
    return
  }
  for p in input_paths {
    if !validate_path(p) {
      send_json_error(conn, 400, "Invalid path", cors)
      return
    }
  }
  let graph_config : @doc_graph_cli.GraphConfig = {
    output: "",
    specs_dir: config.specs_dir,
    title: json_string(json, "title", "Module Dependencies"),
    format: json_string(json, "format", "mermaid"),
    input_paths,
  }
  match @doc_graph_cli.run_to_string(graph_config) {
    Some(result) => {
      // Wrap non-JSON formats as a JSON string
      let format = json_string(json, "format", "mermaid")
      if format == "json" || format == "codegraph" {
        send_json_ok(conn, result, cors)
      } else {
        send_json_ok(conn, Json::string(result).stringify(), cors)
      }
    }
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_refactor(
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
  let target_dir = json_string(json, "targetDir", "")
  if target_dir.length() == 0 || !validate_path(target_dir) {
    send_json_error(conn, 400, "Valid targetDir required", cors)
    return
  }
  let refactor_config : @plan_refactor.RefactorPlanConfig = {
    target_dir,
    threshold: json_double(json, "threshold", 0.7),
    fdr: json_double(json, "fdr", 0.0),
    strategy: json_string(json, "strategy", "hybrid"),
    includes: json_string_array(json, "includes"),
    excludes: json_string_array(json, "excludes"),
    output: "",
    format: json_string(json, "format", "md"),
    style: json_string(json, "style", "raw"),
    project_name: json_string(json, "projectName", ""),
    specs_dir: config.specs_dir,
  }
  match @plan_refactor.run_to_string(refactor_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_documentation(
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
  let target_dir = json_string(json, "targetDir", "")
  if target_dir.length() == 0 || !validate_path(target_dir) {
    send_json_error(conn, 400, "Valid targetDir required", cors)
    return
  }
  let doc_config : @plan_doc.DocPlanConfig = {
    target_dir,
    output: "",
    style: json_string(json, "style", "full"),
    format: json_string(json, "format", "md"),
    template: json_string(json, "template", ""),
    project_name: json_string(json, "projectName", ""),
    specs_dir: config.specs_dir,
  }
  match @plan_doc.run_to_string(doc_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_reconcile(
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
  let target_dir = json_string(json, "targetDir", "")
  if target_dir.length() == 0 || !validate_path(target_dir) {
    send_json_error(conn, 400, "Valid targetDir required", cors)
    return
  }
  let reconcile_config : @plan_reconcile.ReconcileConfig = {
    ..@plan_reconcile.ReconcileConfig::default(),
    target_dir,
    format: json_string(json, "format", "json"),
    specs_dir: config.specs_dir,
  }
  match @plan_reconcile.run_to_string(reconcile_config) {
    Some(result) => {
      let format = json_string(json, "format", "json")
      if format == "json" {
        send_json_ok(conn, result, cors)
      } else {
        send_json_ok(conn, Json::string(result).stringify(), cors)
      }
    }
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
fn build_spec_align_config(
  json : Json,
  config : ServeConfig,
  subcommand : String,
  default_format : String,
) -> @spec_align.SpecAlignConfig? {
  let spec_path = json_string(json, "specPath", "")
  let impl_path = json_string(json, "implPath", "")
  if spec_path.length() == 0 || impl_path.length() == 0 {
    return None
  }
  if !validate_path(spec_path) || !validate_path(impl_path) {
    return None
  }
  Some({
    ..@spec_align.SpecAlignConfig::default(),
    subcommand,
    spec_path,
    impl_path,
    specs_dir: config.specs_dir,
    format: json_string(json, "format", default_format),
    spec_format: json_string(json, "specFormat", "auto"),
    algorithm: json_string(json, "algorithm", "hybrid"),
    threshold: json_double(json, "threshold", 0.6),
    cache_dir: json_string(json, "cacheDir", ""),
    direction: json_string(json, "direction", "both"),
    agent: json_string(json, "agent", "generic"),
    fail_on: json_string(json, "failOn", "none"),
    incremental: json_bool(json, "incremental", false),
    git_base: json_string(json, "gitBase", "HEAD"),
  })
}

///|
async fn handle_spec_align(
  conn : @mhttp.ServerConnection,
  body_text : String,
  config : ServeConfig,
  cors : Bool,
  subcommand : String,
  default_format : String,
) -> Unit {
  let json : Json = @json.parse(body_text) catch {
    _ => {
      send_json_error(conn, 400, "Invalid JSON body", cors)
      return
    }
  }
  let align_config = match
    build_spec_align_config(json, config, subcommand, default_format) {
    Some(value) => value
    None => {
      send_json_error(
        conn, 400, "Valid specPath and implPath are required", cors,
      )
      return
    }
  }
  match @spec_align_cli.run_to_string(align_config) {
    Some(result) =>
      if align_config.format == "json" {
        send_json_ok(conn, result, cors)
      } else {
        send_json_ok(conn, Json::string(result).stringify(), cors)
      }
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_solid(
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
  let from_dirs = json_string_array(json, "fromDirs")
  if from_dirs.length() < 2 {
    send_json_error(conn, 400, "At least 2 fromDirs required", cors)
    return
  }
  for dir in from_dirs {
    if !validate_path(dir) {
      send_json_error(conn, 400, "Invalid path", cors)
      return
    }
  }
  let solid_config : @plan_solid.SolidConfig = {
    from_dirs,
    to_dir: json_string(json, "toDir", ""),
    rules_file: "",
    inline_rules: json_string_array(json, "rules"),
    threshold: json_double(json, "threshold", 0.9),
    strategy: json_string(json, "strategy", "tfidf"),
    includes: json_string_array(json, "includes"),
    excludes: json_string_array(json, "excludes"),
    output: "",
    format: json_string(json, "format", "md"),
    specs_dir: config.specs_dir,
  }
  match @plan_solid.run_to_string(solid_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_unwrap(
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
  let target_dir = json_string(json, "targetDir", "")
  if target_dir.length() == 0 || !validate_path(target_dir) {
    send_json_error(conn, 400, "Valid targetDir required", cors)
    return
  }
  let unwrap_config : @plan_unwrap.UnwrapConfig = {
    target_dir,
    includes: json_string_array(json, "includes"),
    excludes: json_string_array(json, "excludes"),
    output: "",
    format: json_string(json, "format", "md"),
    include_self: json_bool(json, "includeSelf", false),
    include_bare: json_bool(json, "includeBare", false),
    // Only report mode is supported via API (dry-run/fix mutate files)
    mode: "report",
    specs_dir: config.specs_dir,
  }
  match @plan_unwrap.run_to_string(unwrap_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_plan_readme(
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
  let target_dir = json_string(json, "targetDir", ".")
  if !validate_path(target_dir) {
    send_json_error(conn, 400, "Invalid path", cors)
    return
  }
  let template = json_string(json, "template", "")
  if template.length() == 0 {
    send_json_error(conn, 400, "template is required", cors)
    return
  }
  let readme_config : @plan_readme.ReadmePlanConfig = {
    target_dir,
    output: "",
    format: json_string(json, "format", "md"),
    specs_dir: config.specs_dir,
    template,
    plans_dir: {
      let v = json_string(json, "plansDir", "")
      if v.length() > 0 {
        v
      } else {
        match @config.resolve_project_indexion_dir(target_dir, "plans") {
          Some(dir) => dir
          None => {
            send_json_error(conn, 500, "Project root not found", cors)
            return
          }
        }
      }
    },
  }
  match @plan_readme.run_to_string(readme_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}

///|
async fn handle_search(
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
  // Query the pre-built digest index directly.
  let hits = serve_query_cascade(state.index, state.digest_config, query, top_k)
  let arr : Array[Json] = []
  for hit in hits {
    if hit.score >= min_score {
      arr.push(query_hit_to_search_json(hit))
    }
  }
  send_json_ok(conn, Json::array(arr).stringify(), cors)
}

///|
async fn handle_grep(
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
  match @grep_cli.run_to_json(grep_config) {
    Some(result) => send_json_ok(conn, result, cors)
    None =>
      send_json_error(conn, 400, "Pattern or semantic query required", cors)
  }
}

///|
/// Build readonly config JSON from ServeConfig.
fn build_config_json(config : ServeConfig) -> String {
  let obj : Map[String, Json] = {}
  obj.set("workspaceDir", config.workspace_dir.to_json())
  obj.set("specsDir", config.specs_dir.to_json())
  obj.set("indexDir", config.index_dir.to_json())
  obj.set(
    "configDir",
    match @config.get_global_config_dir() {
      Some(dir) => dir.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "dataDir",
    match @config.get_global_data_dir() {
      Some(dir) => dir.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "cacheDir",
    match @config.get_global_cache_dir() {
      Some(dir) => dir.to_json()
      None => Json::null()
    },
  )
  obj.set("branding", config.wiki_config.to_branding_json())
  Json::object(obj).stringify()
}
