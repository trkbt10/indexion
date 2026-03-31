///|
/// # indexion digest
///
/// Build and query purpose-based function index.
/// Supports TF-IDF (local) and OpenAI embeddings.

///|
/// CLI configuration.
pub(all) struct CliConfig {
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
  api_key_env : String
  api_base_url : String
  model : String
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
    api_key_env: @dconfig.DEFAULT_API_KEY_ENV,
    api_base_url: @dconfig.DEFAULT_API_BASE_URL,
    model: @dconfig.DEFAULT_EMBEDDING_MODEL,
  }
}

///|
/// Create CliConfig from argparse Matches.
pub fn CliConfig::from_matches(matches : @argparse.Matches) -> CliConfig {
  let mut config = CliConfig::default()
  // Global options
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
  match matches.values.get("top-k") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, top_k: @common.parse_int(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("min-score") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, min_score: @common.parse_double(vals[0]) }
      }
    None => ()
  }
  match matches.values.get("index-dir") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, index_dir: vals[0] }
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
  match matches.values.get("specs") {
    Some(vals) =>
      if vals.length() > 0 {
        config = { ..config, specs_dir: vals[0] }
      }
    None => ()
  }
  // Subcommand dispatch
  match matches.subcommand {
    Some((name, sub_matches)) => {
      config = { ..config, command: name }
      match name {
        "build" =>
          match sub_matches.values.get("input") {
            Some(vals) =>
              if vals.length() > 0 {
                config = { ..config, input_path: vals[0] }
              }
            None => ()
          }
        "query" =>
          match sub_matches.values.get("purpose") {
            Some(vals) =>
              if vals.length() > 0 {
                config = { ..config, purpose: vals[0] }
              }
            None => ()
          }
        _ => ()
      }
    }
    None => ()
  }
  config
}

///|
/// Define the digest command for argparse.
pub fn command() -> @argparse.Command {
  let dim_default = @dconfig.DEFAULT_TFIDF_DIM.to_string()
  @argparse.Command(
    "digest",
    about="Purpose-based function index",
    arg_required_else_help=true,
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "provider",
        about="Embedding provider: tfidf, openai, auto",
        default_values=["auto"],
        global=true,
      ),
      @argparse.OptionArg(
        "index-dir",
        about="Index directory",
        default_values=[@dconfig.DEFAULT_INDEX_DIR],
        global=true,
      ),
      @argparse.OptionArg(
        "dim",
        about="Embedding dimension (default: 256 for tfidf, 1536 for openai)",
        default_values=[dim_default],
        global=true,
      ),
      @argparse.OptionArg(
        "strategy",
        about="vcdb: bruteforce, hnsw, ivf",
        default_values=["hnsw"],
        global=true,
      ),
      @argparse.OptionArg(
        "specs",
        about=@help.specs_dir,
        default_values=["kgfs"],
        global=true,
      ),
      @argparse.OptionArg(
        "top-k",
        about="Number of results",
        default_values=["10"],
        global=true,
      ),
      @argparse.OptionArg(
        "min-score",
        about="Minimum similarity score",
        default_values=["0.1"],
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command(
        "build",
        about="Build/update index from source directory or graph.json",
        positionals=[
          @argparse.PositionArg(
            "input",
            about="Source directory or graph.json path",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      ),
      @argparse.Command("query", about="Search functions by purpose", positionals=[
        @argparse.PositionArg(
          "purpose",
          about="Purpose query string",
          num_args=@argparse.ValueRange::single(),
        ),
      ]),
      @argparse.Command("stats", about="Show index statistics"),
    ],
  )
}

///|
/// Apply DigestFileConfig from .indexion.toml as defaults.
/// CLI-explicit values (non-default) take precedence over file config.
pub fn CliConfig::apply_file_config(
  self : CliConfig,
  file : @config.DigestFileConfig,
) -> CliConfig {
  let defaults = CliConfig::default()
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
/// Load DigestFileConfig from .indexion.toml in the current directory.
pub fn load_digest_file_config() -> @config.DigestFileConfig {
  let config_path = @config.find_indexion_config_path(".")
  @config.load_effective_digest_config(config_path)
}

///|
/// Entry point for the digest subcommand using argparse Matches.
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = CliConfig::from_matches(matches).apply_file_config(
    load_digest_file_config(),
  )
  match config.command {
    "build" => run_build_async(config)
    "query" => run_query_async(config)
    "stats" => run_stats(config)
    _ => {
      println("Unknown command: " + config.command)
      println("")
      println(command().render_help())
    }
  }
}

///|
/// Write progress message (TODO: use stderr when available).
pub fn log_progress(msg : String) -> Unit {
  println(msg)
}

///|
/// Write error message (TODO: use stderr when available).
pub fn log_error(msg : String) -> Unit {
  println("Error: " + msg)
}

///|
/// Build EmbeddingApiConfig from CLI config and resolved API key.
fn build_api_config(
  config : CliConfig,
  api_key : String,
) -> @dconfig.EmbeddingApiConfig {
  // If dim was not explicitly configured (still at TF-IDF default),
  // use the OpenAI default dimension for API providers.
  let dim = if config.dim == @dconfig.DEFAULT_TFIDF_DIM {
    @dconfig.OPENAI_EMBEDDING_DIM
  } else {
    config.dim
  }
  {
    api_key,
    api_key_env: config.api_key_env,
    base_url: config.api_base_url,
    model: config.model,
    dim,
  }
}

///|
/// Resolve embedding provider from CLI config.
pub fn resolve_provider(config : CliConfig) -> @dconfig.EmbeddingProvider {
  let env_name = config.api_key_env
  match config.provider {
    "openai" =>
      match @sys.get_env_var(env_name) {
        Some(key) => @dconfig.OpenAI(build_api_config(config, key))
        None => {
          log_error(
            env_name + " environment variable required for --provider=openai",
          )
          @dconfig.TfIdf(config.dim)
        }
      }
    "tfidf" => @dconfig.TfIdf(config.dim)
    "auto" | "" =>
      // Auto-detect: use embedding API if key present
      match @sys.get_env_var(env_name) {
        Some(key) => @dconfig.OpenAI(build_api_config(config, key))
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
pub fn build_digest_config(config : CliConfig) -> @dconfig.DigestConfig {
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
    @dconfig.OpenAI(cfg) =>
      cfg.model + " (" + cfg.dim.to_string() + " dims, " + cfg.base_url + ")"
    @dconfig.Precomputed(_) => "Precomputed embeddings"
  }
}

///|
/// Build graph from source directory.
pub fn build_graph_from_source(
  source_dir : String,
  specs_dir : String,
) -> @graph.CodeGraph? {
  log_progress("Loading language specs...")
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir~,
    target_dir=source_dir,
  )
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
pub fn load_graph_from_file(path : String) -> @graph.CodeGraph? {
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

// use @common (SoT) — is_directory

///|
/// Load existing index or create new one.
pub fn load_or_create_index(
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
pub fn ensure_dir_exists(path : String) -> Unit {
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
    let parent = path[0:last_slash].to_string()
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
  let graph = if @common.is_directory(config.input_path) {
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
  let env_name = config.api_key_env
  let provider = if config.provider != "auto" && config.provider != "" {
    resolve_provider(config)
  } else if manifest.embedding_provider == "openai" {
    match @sys.get_env_var(env_name) {
      Some(key) => @dconfig.OpenAI(build_api_config(config, key))
      None => {
        log_error(
          "Index was built with OpenAI-compatible API. Set " +
          env_name +
          " to query.",
        )
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
    @dconfig.OpenAI(api_config) =>
      index.query_native(config.purpose, config.top_k, api_config) catch {
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
