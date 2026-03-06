///|
/// # indexion digest
///
/// Build and query purpose-based function index.
/// Supports TF-IDF (local) and OpenAI embeddings.

///|
/// CLI configuration.
pub struct CliConfig {
  command : String
  input_path : String
  purpose : String
  index_dir : String
  provider : String
  dim : Int
  strategy : String
  top_k : Int
  min_score : Double
  specs_dir : String
  show_help : Bool
}

///|
/// Create default configuration.
pub fn CliConfig::default() -> CliConfig {
  {
    command: "",
    input_path: "",
    purpose: "",
    index_dir: @dconfig.DEFAULT_INDEX_DIR,
    provider: "auto",
    dim: @dconfig.DEFAULT_TFIDF_DIM,
    strategy: "hnsw",
    top_k: 10,
    min_score: 0.1,
    specs_dir: "kgfs",
    show_help: false,
  }
}

///|
fn get_arg_value(arg : String, prefix_len : Int) -> String {
  let chars = arg.to_array()
  if prefix_len >= chars.length() {
    return ""
  }
  let result : Array[Char] = []
  for i = prefix_len; i < chars.length(); i = i + 1 {
    result.push(chars[i])
  }
  String::from_array(result)
}

///|
fn parse_int(s : String) -> Int {
  let chars = s.to_array()
  let mut result = 0
  for c in chars {
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
  }
  result
}

///|
fn parse_double(s : String) -> Double {
  let chars = s.to_array()
  if chars.length() == 0 {
    return 0.0
  }
  let mut result = 0.0
  let mut decimal_place = 0
  for c in chars {
    if c == '.' {
      decimal_place = 1
    } else if c >= '0' && c <= '9' {
      if decimal_place == 0 {
        result = result * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      } else {
        let digit = (c.to_int() - '0'.to_int()).to_double()
        let mut divisor = 1.0
        for _i = 0; _i < decimal_place; _i = _i + 1 {
          divisor = divisor * 10.0
        }
        result = result + digit / divisor
        decimal_place = decimal_place + 1
      }
    }
  }
  result
}

///|
/// Parse CLI arguments.
pub fn parse_args(args : Array[String], start_idx : Int) -> CliConfig {
  let mut config = CliConfig::default()
  let positional : Array[String] = []
  for i = start_idx; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      config = { ..config, show_help: true }
    } else if arg.has_prefix("--dim=") {
      let value = get_arg_value(arg, 6)
      config = { ..config, dim: parse_int(value) }
    } else if arg.has_prefix("--strategy=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, strategy: value }
    } else if arg.has_prefix("--top-k=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, top_k: parse_int(value) }
    } else if arg.has_prefix("--min-score=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, min_score: parse_double(value) }
    } else if arg.has_prefix("--index-dir=") {
      let value = get_arg_value(arg, 12)
      config = { ..config, index_dir: value }
    } else if arg.has_prefix("--provider=") {
      let value = get_arg_value(arg, 11)
      config = { ..config, provider: value }
    } else if arg.has_prefix("--specs=") {
      let value = get_arg_value(arg, 8)
      config = { ..config, specs_dir: value }
    } else if not(arg.has_prefix("-")) {
      positional.push(arg)
    }
  }
  // Parse positional arguments
  if positional.length() >= 1 {
    config = { ..config, command: positional[0] }
  }
  if positional.length() >= 2 {
    if config.command == "build" {
      config = { ..config, input_path: positional[1] }
    } else if config.command == "query" {
      config = { ..config, purpose: positional[1] }
    }
  }
  config
}

///|
/// Write progress message (TODO: use stderr when available).
fn log_progress(msg : String) -> Unit {
  println(msg)
}

///|
/// Write error message (TODO: use stderr when available).
fn log_error(msg : String) -> Unit {
  println("Error: " + msg)
}

///|
/// Main entry point (async to support OpenAI embeddings).
pub async fn run(args : Array[String], start_idx : Int) -> Unit {
  let config = parse_args(args, start_idx)
  if config.show_help || config.command == "" {
    show_help()
    return
  }
  match config.command {
    "build" => run_build_async(config)
    "query" => run_query_async(config)
    "stats" => run_stats(config)
    "help" => show_help()
    _ => {
      println("Unknown command: " + config.command)
      println("")
      show_help()
    }
  }
}

///|
/// Resolve embedding provider from CLI config.
fn resolve_provider(config : CliConfig) -> @dconfig.EmbeddingProvider {
  match config.provider {
    "openai" =>
      match @sys.get_env_var("OPENAI_API_KEY") {
        Some(key) => @dconfig.OpenAI(key)
        None => {
          log_error(
            "OPENAI_API_KEY environment variable required for --provider=openai",
          )
          @dconfig.TfIdf(config.dim)
        }
      }
    "tfidf" => @dconfig.TfIdf(config.dim)
    "auto" | "" =>
      // Auto-detect: use OpenAI if API key present
      match @sys.get_env_var("OPENAI_API_KEY") {
        Some(key) => @dconfig.OpenAI(key)
        None => @dconfig.TfIdf(config.dim)
      }
    _ => {
      log_error("Unknown provider: " + config.provider + ", using tfidf")
      @dconfig.TfIdf(config.dim)
    }
  }
}

///|
/// Build DigestConfig from CLI config.
fn build_digest_config(config : CliConfig) -> @dconfig.DigestConfig {
  let provider = resolve_provider(config)
  let vcdb_strategy = match config.strategy {
    "bruteforce" => @dconfig.BruteForce
    "ivf" => @dconfig.Ivf
    _ => @dconfig.Hnsw
  }
  {
    embedding_source: @dconfig.Raw,
    embedding_provider: provider,
    vcdb_strategy,
    include_external: false,
    exclude_kinds: @dconfig.default_exclude_kinds(),
    index_dir: config.index_dir,
    llm_config: None,
  }
}

///|
/// Get provider display name.
fn provider_name(provider : @dconfig.EmbeddingProvider) -> String {
  match provider {
    @dconfig.TfIdf(dim) => "TF-IDF (local, " + dim.to_string() + " dims)"
    @dconfig.OpenAI(_) => "OpenAI text-embedding-3-small (1536 dims)"
    @dconfig.Precomputed(_) => "Precomputed embeddings"
  }
}

///|
/// Build graph from source directory.
fn build_graph_from_source(
  source_dir : String,
  specs_dir : String,
) -> @graph.CodeGraph? {
  log_progress("Loading language specs...")
  let registry = @registry.KGFRegistry::load_from_dir(specs_dir)
  log_progress("Collecting files...")
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(kgf_ignore~)
  let paths = @pipeline.discover_files([source_dir], discover_opts)
  if paths.length() == 0 {
    log_error("No files found in: " + source_dir)
    return None
  }
  let files = @pipeline.collect_supported_files(paths, registry)
  if files.length() == 0 {
    log_error("No supported files found")
    return None
  }
  log_progress("Found " + files.length().to_string() + " files to analyze.")
  // Build graph with progress callback
  let progress_fn : ((Int, Int, String)) -> Unit = fn(info) {
    let (current, total, path) = info
    log_progress(
      "[" +
      current.to_string() +
      "/" +
      total.to_string() +
      "] Analyzing: " +
      path,
    )
  }
  let progress_callback = @build.ProgressCallback::new(progress_fn)
  let doc_config = @build.DocConfig::new(files, registry.to_specs_map())
  let (_, graph) = @build.build_with_graph_progress(
    doc_config,
    Some(progress_callback),
  )
  log_progress("Analysis complete.")
  Some(graph)
}

///|
/// Load graph from JSON file.
fn load_graph_from_file(path : String) -> @graph.CodeGraph? {
  let content = @fs.read_file_to_string(path) catch {
    e => {
      log_error("Reading file: " + e.to_string())
      return None
    }
  }
  match @graph.CodeGraph::from_json_string(content) {
    Some(g) => Some(g)
    None => {
      log_error("Failed to parse graph JSON")
      None
    }
  }
}

///|
/// Check if path is a directory.
fn is_directory(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// Load existing index or create new one.
fn load_or_create_index(
  index_dir : String,
  digest_config : @dconfig.DigestConfig,
) -> @index.DigestIndex {
  let manifest_path = index_dir + "/manifest.json"
  let vectors_path = index_dir + "/vectors.db"
  // Try to load existing index
  let manifest_exists = @fs.path_exists(manifest_path)
  let vectors_exists = @fs.path_exists(vectors_path)
  if manifest_exists && vectors_exists {
    let manifest_content = @fs.read_file_to_string(manifest_path) catch {
      _ => return @index.DigestIndex::with_config(digest_config)
    }
    let manifest = match
      @manifest.DigestManifest::from_json_string(manifest_content) {
      Some(m) => m
      None => return @index.DigestIndex::with_config(digest_config)
    }
    // Check if provider matches
    let current_provider = match digest_config.embedding_provider {
      @dconfig.TfIdf(_) => "tfidf"
      @dconfig.OpenAI(_) => "openai"
      @dconfig.Precomputed(_) => "precomputed"
    }
    if manifest.embedding_provider != current_provider {
      log_progress(
        "Provider changed (" +
        manifest.embedding_provider +
        " -> " +
        current_provider +
        "), rebuilding index...",
      )
      return @index.DigestIndex::with_config(digest_config)
    }
    // Load vectors database
    let db_bytes = @fs.read_file_to_bytes(vectors_path) catch {
      _ => return @index.DigestIndex::with_config(digest_config)
    }
    log_progress("Loading existing index...")
    @index.DigestIndex::from_manifest(manifest, db_bytes)
  } else {
    @index.DigestIndex::with_config(digest_config)
  }
}

///|
/// Ensure directory exists, creating parent directories as needed.
fn ensure_dir_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  // Simple approach: try to create parent (.indexion) then target
  // For path like ".indexion/digest", create ".indexion" first
  let chars = path.to_array()
  let mut last_slash = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash > 0 {
    let parent = path[0:last_slash].to_string() catch { _ => "" }
    if not(@fs.path_exists(parent)) {
      @fs.create_dir(parent) catch {
        _ => ()
      }
    }
  }
  if not(@fs.path_exists(path)) {
    @fs.create_dir(path) catch {
      _ => ()
    }
  }
}

///|
/// Build index from source directory or graph file.
async fn run_build_async(config : CliConfig) -> Unit {
  if config.input_path == "" {
    log_error("Input path required (source directory or graph.json)")
    println("")
    println("Usage: indexion digest build <path>")
    return
  }
  let digest_config = build_digest_config(config)
  log_progress("Building digest index from: " + config.input_path)
  log_progress("Provider: " + provider_name(digest_config.embedding_provider))
  // Detect input type and build graph
  let graph = if is_directory(config.input_path) {
    match build_graph_from_source(config.input_path, config.specs_dir) {
      Some(g) => g
      None => return
    }
  } else {
    match load_graph_from_file(config.input_path) {
      Some(g) => g
      None => return
    }
  }
  log_progress("Loaded graph: " + graph.symbol_count().to_string() + " symbols")
  // Load existing index if available, otherwise create new
  let index = load_or_create_index(config.index_dir, digest_config)
  // Build with appropriate method based on provider
  let result = index.build_with_config(graph, digest_config) catch {
    @embed.ParseError(msg) => {
      log_error("Parse error: " + msg)
      return
    }
    @embed.ApiError(code, msg) => {
      log_error("API error (" + code.to_string() + "): " + msg)
      return
    }
    @embed.NoResult => {
      log_error("No embedding result")
      return
    }
  }
  println("")
  println("Build complete:")
  println("  Indexed: " + result.indexed_count.to_string())
  println("  Skipped: " + result.skipped_count.to_string() + " (unchanged)")
  println("  Removed: " + result.removed_count.to_string() + " (deleted)")
  // Ensure index directory exists
  ensure_dir_exists(config.index_dir)
  // Save index
  let (manifest_json, db_bytes) = index.serialize()
  @fs.write_string_to_file(config.index_dir + "/manifest.json", manifest_json) catch {
    e => {
      log_error("Saving manifest: " + e.to_string())
      return
    }
  }
  @fs.write_bytes_to_file(config.index_dir + "/vectors.db", db_bytes) catch {
    e => {
      log_error("Saving vectors: " + e.to_string())
      return
    }
  }
  // Save graph for query time
  let graph_json = graph.to_json_string()
  @fs.write_string_to_file(config.index_dir + "/graph.json", graph_json) catch {
    e => {
      log_error("Saving graph: " + e.to_string())
      return
    }
  }
  println("")
  println("Index saved to: " + config.index_dir)
}

///|
/// Query index by purpose.
async fn run_query_async(config : CliConfig) -> Unit {
  if config.purpose == "" {
    log_error("Purpose query required")
    println("")
    println("Usage: indexion digest query \"<purpose>\"")
    return
  }
  // Check if index exists
  let manifest_path = config.index_dir + "/manifest.json"
  let graph_path = config.index_dir + "/graph.json"
  let manifest_exists = @fs.is_file(manifest_path) catch { _ => false }
  if not(manifest_exists) {
    log_error("No index found at " + config.index_dir)
    println("Run 'indexion digest build <path>' first.")
    return
  }
  // Load manifest to detect provider
  let manifest_content = @fs.read_file_to_string(manifest_path) catch {
    e => {
      log_error("Reading manifest: " + e.to_string())
      return
    }
  }
  let manifest = match
    @manifest.DigestManifest::from_json_string(manifest_content) {
    Some(m) => m
    None => {
      log_error("Invalid manifest.json")
      return
    }
  }
  // Auto-detect provider from manifest if not explicitly specified
  let provider = if config.provider != "auto" && config.provider != "" {
    resolve_provider(config)
    // Use saved provider type
  } else if manifest.embedding_provider == "openai" {
    match @sys.get_env_var("OPENAI_API_KEY") {
      Some(key) => @dconfig.OpenAI(key)
      None => {
        log_error("Index was built with OpenAI. Set OPENAI_API_KEY to query.")
        return
      }
    }
  } else {
    @dconfig.TfIdf(manifest.embedding_dim)
  }
  // Load graph
  let graph_content = @fs.read_file_to_string(graph_path) catch {
    e => {
      log_error("Reading graph: " + e.to_string())
      return
    }
  }
  let graph = match @graph.CodeGraph::from_json_string(graph_content) {
    Some(g) => g
    None => {
      log_error("Failed to parse graph JSON")
      return
    }
  }
  // Build DigestConfig
  let digest_config = @dconfig.DigestConfig::default()
    .with_provider(provider)
    .with_index_dir(config.index_dir)
  // Create and rebuild index (in memory)
  let index = @index.DigestIndex::with_config(digest_config)
  let _ = index.build_with_config(graph, digest_config) catch {
    @embed.ParseError(msg) => {
      log_error("Parse error: " + msg)
      return
    }
    @embed.ApiError(code, msg) => {
      log_error("API error (" + code.to_string() + "): " + msg)
      return
    }
    @embed.NoResult => {
      log_error("No embedding result")
      return
    }
  }
  // Query
  println("Query: " + config.purpose)
  println("")
  // Use appropriate query method based on provider
  let hits = match provider {
    @dconfig.OpenAI(api_key) =>
      index.query_native(config.purpose, config.top_k, api_key) catch {
        @embed.ParseError(msg) => {
          log_error("Parse error: " + msg)
          return
        }
        @embed.ApiError(code, msg) => {
          log_error("API error (" + code.to_string() + "): " + msg)
          return
        }
        @embed.NoResult => {
          log_error("No embedding result")
          return
        }
      }
    _ => {
      let options = @types.QueryOptions::with_top_k(config.top_k)
      @query.query_by_purpose(index, config.purpose, options)
    }
  }
  println(@query.format_results(hits))
}

///|
/// Show index statistics.
fn run_stats(config : CliConfig) -> Unit {
  let manifest_path = config.index_dir + "/manifest.json"
  let manifest_exists = @fs.is_file(manifest_path) catch { _ => false }
  if not(manifest_exists) {
    log_error("No index found at " + config.index_dir)
    println("Run 'indexion digest build <path>' first.")
    return
  }
  // Load manifest
  let manifest_content = @fs.read_file_to_string(manifest_path) catch {
    e => {
      log_error("Reading manifest: " + e.to_string())
      return
    }
  }
  let manifest = match
    @manifest.DigestManifest::from_json_string(manifest_content) {
    Some(m) => m
    None => {
      log_error("Invalid manifest.json")
      return
    }
  }
  let graph_path = config.index_dir + "/graph.json"
  let graph_content = @fs.read_file_to_string(graph_path) catch {
    e => {
      log_error("Reading graph: " + e.to_string())
      return
    }
  }
  let graph = match @graph.CodeGraph::from_json_string(graph_content) {
    Some(g) => g
    None => {
      log_error("Failed to parse graph JSON")
      return
    }
  }
  println("Index statistics:")
  println("  Index directory: " + config.index_dir)
  println("  Provider: " + manifest.embedding_provider)
  println("  Embedding dim: " + manifest.embedding_dim.to_string())
  println("  Indexed functions: " + manifest.functions.length().to_string())
  println("  Total symbols: " + graph.symbol_count().to_string())
  println("  Total modules: " + graph.module_count().to_string())
  println("  Total edges: " + graph.edge_count().to_string())
}

///|
/// Show help.
fn show_help() -> Unit {
  println("indexion digest - Purpose-based function index")
  println("")
  println("USAGE:")
  println("  indexion digest build [options] <path>")
  println("  indexion digest query [options] \"<purpose>\"")
  println("  indexion digest stats")
  println("")
  println("COMMANDS:")
  println("  build   Build/update index from source directory or graph.json")
  println("  query   Search functions by purpose")
  println("  stats   Show index statistics")
  println("")
  println("OPTIONS:")
  println(
    "  --provider=NAME    Embedding provider: tfidf, openai, auto (default: auto)",
  )
  println("  --index-dir=DIR    Index directory (default: .indexion/digest)")
  println(
    "  --dim=INT          TF-IDF dimension (default: 256, ignored for openai)",
  )
  println("  --strategy=NAME    vcdb: bruteforce, hnsw, ivf (default: hnsw)")
  println("  --specs=DIR        KGF specs directory (default: kgfs)")
  println("  --top-k=INT        Number of results (default: 10)")
  println("  --min-score=FLOAT  Minimum similarity score (default: 0.1)")
  println("  -h, --help         Show this help")
  println("")
  println("EXAMPLES:")
  println("  # Build with TF-IDF (fast, local)")
  println("  indexion digest build src/")
  println("")
  println("  # Build with OpenAI embeddings (better quality)")
  println("  export OPENAI_API_KEY=sk-...")
  println("  indexion digest build src/ --provider=openai")
  println("")
  println("  # Build from existing graph.json")
  println("  indexion digest build graph.json")
  println("")
  println("  # Query (auto-detects provider from index)")
  println("  indexion digest query \"read file contents\"")
  println("")
  println("PROVIDER SELECTION:")
  println("  auto     Use OpenAI if OPENAI_API_KEY is set, else TF-IDF")
  println("  tfidf    Local TF-IDF (fast, no API key needed)")
  println("  openai   OpenAI text-embedding-3-small (requires OPENAI_API_KEY)")
}
