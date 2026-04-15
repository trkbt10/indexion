///|
/// # indexion digest
///
/// Build and query purpose-based function index.
/// Supports TF-IDF (local) and remote embedding API.

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
  source_dir : String
  no_update : Bool
  /// Provider entries from config file ([[digest.providers]]).
  file_providers : Array[@config.ProviderFileEntry]
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
    source_dir: "",
    no_update: false,
    file_providers: [],
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
        "query" => {
          match sub_matches.values.get("purpose") {
            Some(vals) =>
              if vals.length() > 0 {
                config = { ..config, purpose: vals[0] }
              }
            None => ()
          }
          match sub_matches.values.get("source") {
            Some(vals) =>
              if vals.length() > 0 {
                config = { ..config, source_dir: vals[0] }
              }
            None => ()
          }
          if sub_matches.flags.get("no-update").unwrap_or(false) {
            config = { ..config, no_update: true }
          }
        }
        "status" | "rebuild" =>
          match sub_matches.values.get("input") {
            Some(vals) =>
              if vals.length() > 0 {
                config = { ..config, input_path: vals[0] }
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
      @argparse.Command(
        "query",
        about="Search functions by purpose (auto-updates index if source changed)",
        positionals=[
          @argparse.PositionArg(
            "purpose",
            about="Purpose query string",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
        options=[
          @argparse.OptionArg(
            "source",
            about="Source directory for auto-update (default: auto-detect)",
          ),
        ],
        flags=[
          @argparse.FlagArg(
            "no-update",
            about="Skip auto-update, use saved index only",
          ),
        ],
      ),
      @argparse.Command("stats", about="Show index statistics"),
      @argparse.Command(
        "status",
        about="Show index status including pending changes",
        positionals=[
          @argparse.PositionArg(
            "input",
            about="Source directory to check against index",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      ),
      @argparse.Command(
        "rebuild",
        about="Full rebuild: delete existing index and re-index from scratch",
        positionals=[
          @argparse.PositionArg(
            "input",
            about="Source directory or graph.json path",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      ),
    ],
  )
}

///|
/// Apply DigestFileConfig from .indexion.toml as defaults.
/// CLI-explicit values (non-default) take precedence over file config.
pub fn CliConfig::apply_embedding_file_config(
  self : CliConfig,
  file : @config.EmbeddingFileConfig,
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
  // Preserve file-level provider entries for build_digest_config
  if file.providers.length() > 0 {
    config = { ..config, file_providers: file.providers }
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
/// Load EmbeddingFileConfig from .indexion.toml in the current directory.
pub fn load_embedding_file_config() -> @config.EmbeddingFileConfig {
  let config_path = @config.find_indexion_config_path(".")
  @config.load_effective_embedding_config(config_path)
}

///|
/// Entry point for the digest subcommand using argparse Matches.
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let embed_file_config = load_embedding_file_config()
  let merged = CliConfig::from_matches(matches).apply_embedding_file_config(
    embed_file_config,
  )
  let config = {
    ..merged,
    index_dir: if merged.index_dir == @dconfig.DEFAULT_INDEX_DIR {
      match @config.resolve_project_indexion_dir(".", "digest") {
        Some(dir) => dir
        None => {
          println("Error: Could not find project root directory.")
          return
        }
      }
    } else {
      merged.index_dir
    },
  }
  match config.command {
    "build" => run_build_async(config)
    "rebuild" => run_rebuild_async(config)
    "query" => run_query_async(config)
    "stats" => run_stats(config)
    "status" => run_status(config)
    _ => {
      println("Unknown command: " + config.command)
      println("")
      println(command().render_help())
    }
  }
}

///|
/// Write progress message (TODO: use stderr when available).

///|
/// Hint message for when a digest index is required but not found.
/// SoT for the build command suggestion across all consumers (search, serve, etc.).
pub fn build_hint() -> String {
  "No digest index found. Build it with:\n\n  indexion digest build .\n"
}

///|
pub fn log_progress(msg : String) -> Unit {
  println(msg)
}

///|
/// Write error message (TODO: use stderr when available).
pub fn log_error(msg : String) -> Unit {
  println("Error: " + msg)
}

///|
/// Resolve embedding provider from CLI config.
/// Delegates to @embed_config.resolve_provider (SoT for provider resolution).
/// dim is adjusted: if still at TF-IDF default and provider=openai, use OPENAI_EMBEDDING_DIM.
/// Raises String with an error message if the provider cannot be resolved.
pub fn resolve_provider(
  config : CliConfig,
) -> @dconfig.EmbeddingProvider raise @embed_config.ProviderError {
  let dim = if config.provider == "openai" &&
    config.dim == @dconfig.DEFAULT_TFIDF_DIM {
    @dconfig.OPENAI_EMBEDDING_DIM
  } else {
    config.dim
  }
  @embed_config.resolve_provider(
    config.provider,
    config.api_key_env,
    config.api_base_url,
    config.model,
    dim,
  )
}

///|
/// Check if the resolved provider matches the requested provider.
/// Returns false when openai was requested but API key is missing.
pub fn is_provider_available(config : CliConfig) -> Bool {
  match config.provider {
    "openai" => @sys.get_env_var(config.api_key_env) is Some(_)
    _ => true
  }
}

///|
/// Build DigestConfig from CLI config and optional file-level providers.
pub fn build_digest_config(
  config : CliConfig,
  file_providers? : Array[@config.ProviderFileEntry] = [],
) -> @dconfig.DigestConfig {
  let vcdb_strategy = match config.strategy {
    "bruteforce" => @embed_config.BruteForce
    "ivf" => @embed_config.Ivf
    _ => @embed_config.Hnsw
  }
  // If file config has explicit providers, use those
  let providers = if file_providers.length() > 0 {
    resolve_file_providers(file_providers, config)
  } else {
    // Fall back to CLI --provider flag
    let provider = resolve_provider(config) catch {
      @embed_config.MissingApiKey(env) => {
        log_error(env + " not set. provider=openai requires an API key.")
        @embed_config.TfIdf(config.dim)
      }
      @embed_config.UnknownProvider(name) => {
        log_error("Unknown provider: " + name + ", using tfidf")
        @embed_config.TfIdf(config.dim)
      }
    }
    @dconfig.DigestConfig::from_provider(provider).providers
  }
  {
    embedding_source: @embed_config.Raw,
    providers,
    vcdb_strategy,
    include_external: false,
    exclude_kinds: @dconfig.default_exclude_kinds(),
    index_dir: config.index_dir,
    llm_config: None,
  }
}

///|
/// Convert file-level provider entries into ProviderConfig array.
fn resolve_file_providers(
  entries : Array[@config.ProviderFileEntry],
  cli_config : CliConfig,
) -> Array[@dconfig.ProviderConfig] {
  let providers : Array[@dconfig.ProviderConfig] = []
  for entry in entries {
    let kind = match entry.kind {
      Some(k) => k
      None => "tfidf"
    }
    if kind == "tfidf" {
      let dim = match entry.dim {
        Some(d) => d
        None => @dconfig.DEFAULT_TFIDF_DIM
      }
      let key = match entry.key {
        Some(k) => k
        None => @dconfig.DEFAULT_TFIDF_KEY
      }
      providers.push({ key, kind: "tfidf", dim, api_config: None })
    } else {
      // Remote provider — resolve API key from env
      let api_key_env = match entry.api_key_env {
        Some(e) => e
        None => cli_config.api_key_env
      }
      let entry_key_display = match entry.key {
        Some(k) => k
        None => "remote"
      }
      let api_key = match @sys.get_env_var(api_key_env) {
        Some(k) => k
        None => {
          log_error(
            api_key_env +
            " not set, skipping provider '" +
            entry_key_display +
            "'",
          )
          continue
        }
      }
      let model = match entry.model {
        Some(m) => m
        None => @dconfig.DEFAULT_EMBEDDING_MODEL
      }
      let base_url = match entry.api_base_url {
        Some(u) => u
        None => @dconfig.DEFAULT_API_BASE_URL
      }
      let dim = match entry.dim {
        Some(d) => d
        None => @dconfig.OPENAI_EMBEDDING_DIM
      }
      let key = match entry.key {
        Some(k) => k
        None => @embed_config.sanitize_provider_key(model)
      }
      let api_config : @dconfig.EmbeddingApiConfig = {
        api_key,
        api_key_env,
        base_url,
        model,
        dim,
      }
      providers.push({ key, kind: "remote", dim, api_config: Some(api_config) })
    }
  } nobreak {
    providers
  }
}

///|
/// Get provider display name from DigestConfig.
fn config_provider_name(config : @dconfig.DigestConfig) -> String {
  let parts : Array[String] = []
  for p in config.providers {
    match p.api_config {
      Some(cfg) =>
        parts.push(
          p.key + " (" + cfg.model + ", " + p.dim.to_string() + " dims)",
        )
      None =>
        parts.push(p.key + " (" + p.kind + ", " + p.dim.to_string() + " dims)")
    }
  }
  if parts.length() == 0 {
    "none"
  } else {
    parts.join(" + ")
  }
}

///|
/// Query with cascade: try remote providers first, fall back to local.
async fn query_with_cascade(
  index : @index.DigestIndex,
  digest_config : @dconfig.DigestConfig,
  purpose : String,
  top_k : Int,
) -> Array[@types.QueryHit] {
  // Try remote providers first (in order)
  for p in digest_config.providers {
    if p.kind == "remote" && index.has_provider(p.key) {
      match p.api_config {
        Some(api_config) => {
          let hits = index.query_api(purpose, top_k, p.key, api_config) catch {
            _ => {
              log_error(
                "Query failed for provider '" + p.key + "', trying next",
              )
              continue
            }
          }
          return hits
        }
        None => ()
      }
    }
  }
  // Fall back to first local (TF-IDF) provider
  for p in digest_config.providers {
    if p.kind == "tfidf" && index.has_provider(p.key) {
      return index.query_local(purpose, top_k, p.key)
    }
  }
  // No provider available
  []
}

///|
/// Result of building a graph from source, including file content hashes.
pub(all) struct GraphBuildResult {
  graph : @graph.CodeGraph
  /// Map of file path -> content hash for all analyzed files.
  file_hashes : Map[String, @cas_types.ContentHash]
}

///|
/// Build graph from source directory.
/// Returns both the CodeGraph and a map of file content hashes for accurate
/// change detection in incremental index updates.
pub fn build_graph_from_source(
  source_dir : String,
  specs_dir : String,
) -> GraphBuildResult? {
  log_progress("Loading language specs...")
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir~,
    target_dir=source_dir,
  )
  log_progress("Collecting files...")
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=source_dir,
  )
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
  // Compute content hashes from file content while it's in memory.
  // This is the single point where file content is available — after graph
  // construction, content is discarded and only structural data remains.
  let file_hashes : Map[String, @cas_types.ContentHash] = {}
  for entry in files {
    let path = entry.0
    let content = entry.1
    file_hashes.set(path, @cas_hash.compute_hash(content))
  }
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
  Some({ graph, file_hashes })
}

///|
/// Load graph from JSON file.
pub fn load_graph_from_file(path : String) -> @graph.CodeGraph? {
  let content = @fs.read_file_to_string(path) catch {
    e => {
      log_error("Reading file: " + @debug.to_string(e))
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

// Index store management is delegated to @index (SoT):
//   @index.DigestIndex::load_or_create(index_dir, config)
//   @index.@index.acquire_build_lock(index_dir)
//   @index.@index.release_build_lock(index_dir)
//   @index.delete_index_files(index_dir)
//   index.save_to_dir(index_dir, graph)

///|
/// Build index from source directory or graph file.
async fn run_build_async(config : CliConfig) -> Unit {
  if config.input_path == "" {
    log_error("Input path required (source directory or graph.json)")
    println("")
    println(build_hint())
    return
  }
  // Acquire build lock to prevent concurrent builds
  if !@index.acquire_build_lock(config.index_dir) {
    log_error(
      "Another build is in progress (lock file: " +
      config.index_dir +
      "/build.lock)",
    )
    println("If this is stale, remove the lock file and retry.")
    return
  }
  // All code paths after lock acquisition must go through this block,
  // with @index.release_build_lock guaranteed at the end.
  run_build_inner(config)
  @index.release_build_lock(config.index_dir)
}

///|
/// Full rebuild: delete existing index and re-index from scratch.
/// Resets vector_id counter and compacts the vector space.
async fn run_rebuild_async(config : CliConfig) -> Unit {
  if config.input_path == "" {
    log_error("Input path required (source directory or graph.json)")
    println("")
    println("Usage: indexion digest rebuild <path>")
    return
  }
  if !@index.acquire_build_lock(config.index_dir) {
    log_error(
      "Another build is in progress (lock file: " +
      config.index_dir +
      "/build.lock)",
    )
    println("If this is stale, remove the lock file and retry.")
    return
  }
  log_progress("Deleting existing index for full rebuild...")
  let digest_config = build_digest_config(
    config,
    file_providers=config.file_providers,
  )
  @index.delete_index_files(config.index_dir, digest_config.provider_keys())
  log_progress("Starting full rebuild...")
  run_build_inner(config)
  @index.release_build_lock(config.index_dir)
}

///|
/// Inner build logic. Separated so that run_build_async can guarantee
/// lock release regardless of how this function exits.
async fn run_build_inner(config : CliConfig) -> Unit {
  let digest_config = build_digest_config(
    config,
    file_providers=config.file_providers,
  )
  log_progress("Building digest index from: " + config.input_path)
  log_progress("Provider: " + config_provider_name(digest_config))
  // Detect input type and build graph.
  // When building from source directory, file content hashes are computed at
  // collection time (the only point where file content is in memory) and passed
  // through to enable accurate file-level change detection.
  let (graph, file_hashes) : (
    @graph.CodeGraph,
    Map[String, @cas_types.ContentHash]?,
  ) = if @common.is_directory(config.input_path) {
    match build_graph_from_source(config.input_path, config.specs_dir) {
      Some(r) => (r.graph, Some(r.file_hashes))
      None => return
    }
  } else {
    match load_graph_from_file(config.input_path) {
      Some(g) => (g, None) // graph.json has no file content → no file hashes
      None => return
    }
  }
  log_progress("Loaded graph: " + graph.symbol_count().to_string() + " symbols")
  let index = @index.DigestIndex::load_or_create(
    config.index_dir,
    digest_config,
  )
  // Build with file-level change detection when file hashes are available
  let result = index.build_with_config(graph, digest_config, file_hashes~)
  println("")
  println("Build complete:")
  println("  Indexed: " + result.indexed_count.to_string())
  println("  Skipped: " + result.skipped_count.to_string() + " (unchanged)")
  println("  Removed: " + result.removed_count.to_string() + " (deleted)")
  // Save index to disk
  let save_errors = index.save_to_dir(config.index_dir, graph)
  for err in save_errors {
    log_error(err)
  }
  if save_errors.length() == 0 {
    println("")
    println("Index saved to: " + config.index_dir)
  }
}

///|
/// Detect source directory for auto-update.
/// Priority: --source flag > input_path from build > "." (current directory).
fn detect_source_dir(config : CliConfig) -> String {
  if config.source_dir.length() > 0 {
    return config.source_dir
  }
  if config.input_path.length() > 0 && @common.is_directory(config.input_path) {
    return config.input_path
  }
  "."
}

///|
/// Query index by purpose.
/// When --no-update is not set and a source directory is available,
/// automatically performs an incremental build before querying.
async fn run_query_async(config : CliConfig) -> Unit {
  if config.purpose == "" {
    log_error("Purpose query required")
    println("")
    println("Usage: indexion digest query \"<purpose>\"")
    return
  }
  let digest_config = build_digest_config(
    config,
    file_providers=config.file_providers,
  )
  // Auto-update: rebuild index if source has changed, unless --no-update
  if !config.no_update {
    let source_dir = detect_source_dir(config)
    if @common.is_directory(source_dir) {
      // Build graph and file hashes from source
      match build_graph_from_source(source_dir, config.specs_dir) {
        Some(build_result) => {
          let index = @index.DigestIndex::load_or_create(
            config.index_dir,
            digest_config,
          )
          let file_hashes : Map[String, @cas_types.ContentHash]? = Some(
            build_result.file_hashes,
          )
          let result = index.build_with_config(
            build_result.graph,
            digest_config,
            file_hashes~,
          )
          if result.indexed_count > 0 || result.removed_count > 0 {
            log_progress(
              "Auto-update: " +
              result.indexed_count.to_string() +
              " indexed, " +
              result.removed_count.to_string() +
              " removed",
            )
            let _ = index.save_to_dir(config.index_dir, build_result.graph)
          }
        }
        None => () // Source analysis failed — proceed with saved index
      }
    }
  }
  // Load the (potentially just-updated) index
  let index = @index.DigestIndex::load_or_create(
    config.index_dir,
    digest_config,
  )
  if index.manifest.functions.length() == 0 {
    log_error("No index found at " + config.index_dir)
    println("Run 'indexion digest build <path>' first.")
    return
  }
  // Load graph for unit resolution
  let graph_path = @dconfig.graph_path(config.index_dir)
  let graph_content = @fs.read_file_to_string(graph_path) catch {
    e => {
      log_error("Reading graph: " + @debug.to_string(e))
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
  let extract_config = digest_config.to_extract_config()
  index.restore_units_from_graph(graph, extract_config)
  // Query: cascade through providers (remote first, then local)
  println("Query: " + config.purpose)
  println("")
  let hits = query_with_cascade(
    index,
    digest_config,
    config.purpose,
    config.top_k,
  )
  println(@query.format_results(hits))
}

///|
/// Show index statistics.
fn run_stats(config : CliConfig) -> Unit {
  let mp = @dconfig.manifest_path(config.index_dir)
  let manifest_exists = @fs.is_file(mp) catch { _ => false }
  if !manifest_exists {
    log_error("No index found at " + config.index_dir)
    println("Run 'indexion digest build <path>' first.")
    return
  }
  // Load manifest
  let manifest_content = @fs.read_file_to_string(mp) catch {
    e => {
      log_error("Reading manifest: " + @debug.to_string(e))
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
  let graph_path = @dconfig.graph_path(config.index_dir)
  let graph_content = @fs.read_file_to_string(graph_path) catch {
    e => {
      log_error("Reading graph: " + @debug.to_string(e))
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
  println("  Provider: " + manifest.provider_description())
  println("  Indexed functions: " + manifest.functions.length().to_string())
  println("  Total symbols: " + graph.symbol_count().to_string())
  println("  Total modules: " + graph.module_count().to_string())
  println("  Total edges: " + graph.edge_count().to_string())
}

///|
/// Show index status including pending changes.
fn run_status(config : CliConfig) -> Unit {
  let mp = @dconfig.manifest_path(config.index_dir)
  let manifest_exists = @fs.is_file(mp) catch { _ => false }
  if !manifest_exists {
    println("No index found at " + config.index_dir)
    println("Run 'indexion digest build <path>' to create one.")
    return
  }
  let manifest_content = @fs.read_file_to_string(mp) catch {
    e => {
      log_error("Reading manifest: " + @debug.to_string(e))
      return
    }
  }
  let manifest = match
    @manifest.DigestManifest::from_json_string(manifest_content) {
    Some(m) => m
    None => {
      println("Invalid or incompatible manifest (version mismatch).")
      println("Run 'indexion digest rebuild <path>' to recreate.")
      return
    }
  }
  // Basic index info
  println("Index status:")
  println("  Directory:  " + config.index_dir)
  println("  Version:    " + manifest.version.to_string())
  println("  Provider:   " + manifest.provider_description())
  println("  Functions:  " + manifest.functions.length().to_string())
  println("  Files:      " + manifest.files.length().to_string())
  println("")
  // Check for source changes if a source directory is available
  let source_dir = if config.input_path.length() > 0 &&
    @common.is_directory(config.input_path) {
    config.input_path
  } else {
    "."
  }
  if !@common.is_directory(source_dir) {
    println("No source directory specified. Use: indexion digest status <path>")
    return
  }
  println("Scanning " + source_dir + " for changes...")
  match build_graph_from_source(source_dir, config.specs_dir) {
    Some(build_result) => {
      let file_hashes = build_result.file_hashes
      // Compare file hashes against manifest
      let mut modified_files = 0
      let mut new_files = 0
      let modified_list : Array[String] = []
      for entry in file_hashes {
        let path = entry.0
        let hash = entry.1
        if manifest.files.contains(path) {
          if !manifest.is_file_unchanged(path, hash) {
            modified_files += 1
            if modified_list.length() < 10 {
              modified_list.push(path)
            }
          }
        } else {
          new_files += 1
        }
      }
      // Detect deleted files
      let mut deleted_files = 0
      for entry in manifest.files {
        if !file_hashes.contains(entry.0) {
          deleted_files += 1
        }
      }
      // Count affected functions
      let mut affected_functions = 0
      for entry in manifest.files {
        let file_path = entry.0
        let file_entry = entry.1
        match file_hashes.get(file_path) {
          Some(current_hash) =>
            if !manifest.is_file_unchanged(file_path, current_hash) {
              affected_functions += file_entry.functions.length()
            }
          None => affected_functions += file_entry.functions.length()
        }
      }
      println("")
      println("Changes detected:")
      println(
        "  Modified files: " +
        modified_files.to_string() +
        " / " +
        manifest.files.length().to_string(),
      )
      for path in modified_list {
        println("    " + path)
      }
      if modified_files > 10 {
        println("    ... and " + (modified_files - 10).to_string() + " more")
      }
      println("  New files:      " + new_files.to_string())
      println("  Deleted files:  " + deleted_files.to_string())
      println(
        "  Affected functions: ~" +
        affected_functions.to_string() +
        " / " +
        manifest.functions.length().to_string(),
      )
      if modified_files > 0 || new_files > 0 || deleted_files > 0 {
        println("")
        println("Run 'indexion digest build " + source_dir + "' to update.")
      } else {
        println("")
        println("Index is up to date.")
      }
    }
    None => log_error("Failed to scan source directory: " + source_dir)
  }
}
