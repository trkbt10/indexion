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
pub struct SearchConfig {
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
pub async fn run_matches(matches : @argparse.Matches) -> Unit {
  let config = SearchConfig::from_matches(matches)
  if config.query.length() == 0 {
    println("Error: Search query required.")
    return
  }
  let paths = if config.paths.is_empty() { ["."] } else { config.paths }
  let documents = build_corpus(paths, config)
  if documents.is_empty() {
    println("No searchable content found.")
    return
  }
  let engine = @search_engine.SearchEngine::build(documents) catch {
    @embed.ParseError(msg) => {
      println("Error: " + msg + ". Falling back to TF-IDF...")
      @search_engine.SearchEngine::build(documents) catch {
        _ => {
          println("Error: Failed to build search index.")
          return
        }
      }
    }
    @embed.ApiError(code, msg) => {
      println(
        "API error (" +
        code.to_string() +
        "): " +
        msg +
        ". Falling back to TF-IDF...",
      )
      @search_engine.SearchEngine::build(documents) catch {
        _ => {
          println("Error: Failed to build search index.")
          return
        }
      }
    }
    @embed.NoResult => {
      println("No embedding result. Falling back to TF-IDF...")
      @search_engine.SearchEngine::build(documents) catch {
        _ => {
          println("Error: Failed to build search index.")
          return
        }
      }
    }
  }
  let filter = parse_filter(config.filter_str)
  let hits = engine.search(
    config.query,
    top_k=config.top_k,
    min_score=config.min_score,
    filter~,
  )
  if config.json_output {
    format_json(hits)
  } else {
    format_text(hits, config.files_only)
  }
}

///|
/// Parse filter string into FilterExpr.
/// Format: "key:value,key2:value2" → Must([match_(key, value), ...])
/// Empty string → None (no filter).
fn parse_filter(filter_str : String) -> @vcdb_filter.FilterExpr? {
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
