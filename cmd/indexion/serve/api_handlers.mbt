///|
/// API handlers for vscode-plugin endpoints.
/// Each handler parses JSON request body, calls the corresponding
/// command's run_to_json/run_to_string, and returns the result.

///|
/// Validate that a path does not contain path traversal sequences.
fn validate_path(path : String) -> Bool {
  not(path.contains(".."))
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
    if not(validate_path(dir)) {
      send_json_error(conn, 400, "Invalid path", cors)
      return
    }
  }
  let explore_config : @explore_cli.ExploreConfig = {
    target_dirs,
    format: "json",
    strategy: json_string(json, "strategy", "tfidf"),
    threshold: json_double(json, "threshold", 0.5),
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
  if file.length() == 0 || not(validate_path(file)) {
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
  if file.length() == 0 || not(validate_path(file)) {
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
    if not(validate_path(p)) {
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
  if target_dir.length() == 0 || not(validate_path(target_dir)) {
    send_json_error(conn, 400, "Valid targetDir required", cors)
    return
  }
  let refactor_config : @plan_refactor.RefactorPlanConfig = {
    target_dir,
    threshold: json_double(json, "threshold", 0.7),
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
  if target_dir.length() == 0 || not(validate_path(target_dir)) {
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
  if target_dir.length() == 0 || not(validate_path(target_dir)) {
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
    if not(validate_path(dir)) {
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
  if target_dir.length() == 0 || not(validate_path(target_dir)) {
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
  if not(validate_path(target_dir)) {
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
    plans_dir: json_string(json, "plansDir", ".indexion/plans"),
  }
  match @plan_readme.run_to_string(readme_config) {
    Some(result) => send_json_ok(conn, Json::string(result).stringify(), cors)
    None => send_json_error(conn, 404, "No results", cors)
  }
}
