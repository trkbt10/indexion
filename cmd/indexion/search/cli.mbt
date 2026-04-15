///|
/// # indexion search
///
/// Semantic search across code, wiki, and documentation.
/// Automatically detects content type from KGF spec features.
/// Filter results by node attributes (node_type, language, etc.).
///
/// ## Usage
///
/// ```bash
/// indexion search "error handling" src/
/// indexion search "SemanticSearch" .indexion/wiki/
/// indexion search "query" --filter="node_type:code" src/ .indexion/wiki/
/// indexion search "parser" --filter="language:moonbit" src/
/// ```

///|
pub(all) struct SearchConfig {
  query : String
  paths : Array[String]
  top_k : Int
  min_score : Double
  includes : Array[String]
  excludes : Array[String]
  specs_dir : String
  files_only : Bool
  json_output : Bool
  filter_str : String
  provider_name : String
  api_key_env : String
  model : String
  base_url : String
  dim : Int
}

///|
pub fn SearchConfig::from_matches(matches : @argparse.Matches) -> SearchConfig {
  let get_str = fn(key : String, default_ : String) -> String {
    match matches.values.get(key) {
      Some(arr) => if arr.length() > 0 { arr[0] } else { default_ }
      None => default_
    }
  }
  let get_all = fn(key : String) -> Array[String] {
    match matches.values.get(key) {
      Some(arr) => arr
      None => []
    }
  }
  let get_flag = fn(key : String) -> Bool {
    match matches.flags.get(key) {
      Some(v) => v
      None => false
    }
  }
  {
    query: get_str("query", ""),
    paths: get_all("paths"),
    top_k: @common.parse_int(get_str("top-k", "20")),
    min_score: @common.parse_double(get_str("min-score", "0.05")),
    includes: get_all("include"),
    excludes: get_all("exclude"),
    specs_dir: get_str("specs-dir", "kgfs"),
    files_only: get_flag("files"),
    json_output: get_flag("json"),
    filter_str: get_str("filter", ""),
    provider_name: get_str("provider", "auto"),
    api_key_env: get_str("api-key-env", @embed_config.DEFAULT_API_KEY_ENV),
    model: get_str("model", @embed_config.DEFAULT_EMBEDDING_MODEL),
    base_url: get_str("base-url", @embed_config.DEFAULT_API_BASE_URL),
    dim: @common.parse_int(
      get_str("dim", @embed_config.DEFAULT_TFIDF_DIM.to_string()),
    ),
  }
}

///|
pub fn command() -> @argparse.Command {
  @argparse.Command::new(
    "search",
    about="Semantic search across code, wiki, and documentation",
    flags=[
      @argparse.FlagArg::new("files", about="Show matching file paths only"),
      @argparse.FlagArg::new("json", about="Output as JSON"),
    ],
    options=[
      @argparse.OptionArg(
        "top-k",
        short='k',
        about="Number of results (default: 20)",
        default_values=["20"],
      ),
      @argparse.OptionArg(
        "min-score",
        about="Minimum similarity threshold (default: 0.05)",
        default_values=["0.05"],
      ),
      @argparse.OptionArg("include", action=Append, about=@help.include_pattern),
      @argparse.OptionArg("exclude", action=Append, about=@help.exclude_pattern),
      @argparse.OptionArg("specs-dir", about=@help.specs_dir, default_values=[
        "kgfs",
      ]),
      @argparse.OptionArg(
        "filter",
        short='f',
        about="Filter by attributes (e.g. node_type:code, language:moonbit). Comma-separated.",
      ),
      @argparse.OptionArg(
        "provider",
        about="Embedding provider: tfidf | openai | auto (default: auto)",
        default_values=["auto"],
      ),
      @argparse.OptionArg(
        "api-key-env",
        about="Environment variable name for OpenAI API key",
        default_values=[@embed_config.DEFAULT_API_KEY_ENV],
      ),
      @argparse.OptionArg("model", about="Embedding model name", default_values=[
        @embed_config.DEFAULT_EMBEDDING_MODEL,
      ]),
      @argparse.OptionArg("base-url", about="Embedding API base URL", default_values=[
        @embed_config.DEFAULT_API_BASE_URL,
      ]),
      @argparse.OptionArg("dim", about="Embedding dimension", default_values=[
        @embed_config.DEFAULT_TFIDF_DIM.to_string(),
      ]),
    ],
    positionals=[
      @argparse.PositionArg("query", about="Natural language search query"),
      @argparse.PositionArg(
        "paths",
        about="Paths to search (default: current directory)",
        num_args=@argparse.ValueRange(lower=0),
      ),
    ],
  )
}

///|
/// Load the digest index from the project's .indexion/digest/ directory.
/// Returns None if no index exists.
fn load_digest_index(workspace_dir : String) -> @index.DigestIndex? {
  let index_dir = match
    @config.resolve_project_indexion_dir(workspace_dir, "digest") {
    Some(dir) => dir
    None => return None
  }
  let mp = @dconfig.manifest_path(index_dir)
  let gp = @dconfig.graph_path(index_dir)
  if !@fs.path_exists(mp) || !@fs.path_exists(gp) {
    return None
  }
  let embed_file_config = @digest_cli.load_embedding_file_config()
  let digest_config = @digest_cli.build_digest_config(
    {
      command: "",
      input_path: workspace_dir,
      purpose: "",
      index_dir,
      provider: "auto",
      dim: @dconfig.DEFAULT_TFIDF_DIM,
      strategy: "hnsw",
      specs_dir: "kgfs",
      api_key_env: @dconfig.DEFAULT_API_KEY_ENV,
      api_base_url: @dconfig.DEFAULT_API_BASE_URL,
      model: @dconfig.DEFAULT_EMBEDDING_MODEL,
      source_dir: workspace_dir,
      top_k: 10,
      min_score: 0.1,
      no_update: false,
      file_providers: embed_file_config.providers,
    },
    file_providers=embed_file_config.providers,
  )
  let graph_json = @fs.read_file_to_string(gp) catch { _ => return None }
  let graph = match @graph.CodeGraph::from_json_string(graph_json) {
    Some(g) => g
    None => return None
  }
  Some(@index.DigestIndex::load_with_graph(index_dir, digest_config, graph))
}

///|
/// Query the digest index and convert results to SearchHits.
fn query_digest_index(
  index : @index.DigestIndex,
  query : String,
  top_k : Int,
  min_score : Double,
) -> Array[@search_engine.SearchHit] {
  let digest_hits = index.query(query, top_k)
  let hits : Array[@search_engine.SearchHit] = []
  for dh in digest_hits {
    if dh.score < min_score {
      continue
    }
    let func = dh.function
    let summary = match func.symbol.doc {
      Some(doc) => doc
      None =>
        match func.impression {
          Some(imp) => imp.summary
          None => ""
        }
    }
    let doc_attrs : Map[String, String] = {}
    doc_attrs["node_type"] = @kgf_features.node_type_code
    doc_attrs["node_kind"] = func.symbol.kind
    if summary.length() > 0 {
      doc_attrs["summary"] = summary
    }
    let doc : @search_engine.SearchDocument = {
      id: func.symbol.id,
      text: "",
      title: func.name(),
      source: func.module_id,
      line: 0,
      kind: func.symbol.kind,
      attrs: doc_attrs,
    }
    hits.push({ document: doc, score: dh.score })
  }
  hits
}

///|
/// Run search and return results as JSON string.
/// For use by `indexion serve` API endpoint.
pub async fn run_to_json(config : SearchConfig) -> String? {
  if config.query.length() == 0 {
    return None
  }
  let paths = if config.paths.is_empty() { ["."] } else { config.paths }
  // Pre-built wiki index path
  match load_prebuilt_wiki_index(paths) {
    Some(wiki_idx) => {
      let wiki_hits = wiki_idx.search(
        config.query,
        top_k=config.top_k,
        min_score=config.min_score,
      ) catch {
        _ => []
      }
      let hits = wiki_hits_to_search_hits(wiki_hits)
      return Some(hits_to_json(hits))
    }
    None => ()
  }
  // Use the pre-built digest index (SoT).
  let workspace = graph_target_dir(paths)
  match load_digest_index(workspace) {
    Some(index) => {
      let hits = query_digest_index(
        index,
        config.query,
        config.top_k,
        config.min_score,
      )
      Some(hits_to_json(hits))
    }
    None => Some("[]")
  }
}

///|
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = SearchConfig::from_matches(matches)
  if config.query.length() == 0 {
    println("Error: Search query required.")
    return
  }
  let paths = if config.paths.is_empty() { ["."] } else { config.paths }
  // When targeting a single wiki directory with a pre-built vector index,
  // use the full WikiSearchIndex (engine + sections map) to resolve hits.
  match load_prebuilt_wiki_index(paths) {
    Some(wiki_idx) => {
      let wiki_hits = wiki_idx.search(
        config.query,
        top_k=config.top_k,
        min_score=config.min_score,
      ) catch {
        @embed.ParseError(msg) => {
          println("Warning: wiki search error: " + msg)
          []
        }
        @embed.ApiError(code, msg) => {
          println(
            "Warning: wiki search API error (" + code.to_string() + "): " + msg,
          )
          []
        }
        @embed.NoResult => {
          println("Warning: wiki search returned no embedding result")
          []
        }
      }
      let hits = wiki_hits_to_search_hits(wiki_hits)
      if config.json_output {
        format_json(hits)
      } else {
        format_text(hits, config.files_only)
      }
      return
    }
    None => ()
  }
  // Use the pre-built digest index (SoT).
  let workspace = graph_target_dir(paths)
  match load_digest_index(workspace) {
    Some(index) => {
      let hits = query_digest_index(
        index,
        config.query,
        config.top_k,
        config.min_score,
      )
      if hits.is_empty() {
        println("No results found.")
      } else if config.json_output {
        format_json(hits)
      } else {
        format_text(hits, config.files_only)
      }
    }
    None => println(@digest_cli.build_hint())
  }
}

///|
/// Convert WikiSearchHit array to SearchHit array for unified output.
fn wiki_hits_to_search_hits(
  wiki_hits : Array[@wiki_search.WikiSearchHit],
) -> Array[@search_engine.SearchHit] {
  let hits : Array[@search_engine.SearchHit] = []
  for wh in wiki_hits {
    let s = wh.section
    let kind_str = if s.level == 1 { "page" } else { "section" }
    let doc_attrs : Map[String, String] = {}
    doc_attrs["parent"] = s.page_id
    let doc : @search_engine.SearchDocument = {
      id: s.id,
      text: s.content,
      title: s.title,
      source: s.page_id,
      line: 0,
      kind: kind_str,
      attrs: doc_attrs,
    }
    hits.push({ document: doc, score: wh.score })
  }
  hits
}

///|
/// Parse filter string into FilterExpr.
/// Format: "key:value,key2:value2" → Must([match_(key, value), ...])
/// Empty string → None (no filter).
pub fn parse_filter(filter_str : String) -> @vcdb_filter.FilterExpr? {
  if filter_str.length() == 0 {
    return None
  }
  let parts = @common.split_by_char(filter_str, ',')
  let exprs : Array[@vcdb_filter.FilterExpr] = []
  for part in parts {
    let kv = @common.split_by_char(part, ':')
    if kv.length() == 2 {
      let key = @common.trim_ascii_spaces(kv[0])
      let value = @common.trim_ascii_spaces(kv[1])
      if key.length() > 0 && value.length() > 0 {
        exprs.push(
          @vcdb_filter.FilterExpr::match_(key, @vcdb_core.String(value)),
        )
      }
    }
  }
  if exprs.is_empty() {
    None
  } else if exprs.length() == 1 {
    Some(exprs[0])
  } else {
    Some(@vcdb_filter.FilterExpr::must(exprs))
  }
}
