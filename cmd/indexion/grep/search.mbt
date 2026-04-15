///|
/// Search engine — file discovery, tokenization, and output formatting.

///|
/// Load KGF registry and collect files, or print error and return None.
fn load_registry_and_files(
  paths : Array[String],
  config : GrepConfig,
) -> (@kgf_registry.KGFRegistry?, Array[(String, String)])? {
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=paths,
  )
  match registry {
    Some(reg) => Some((registry, collect_search_files(paths, config, reg)))
    None => {
      println("Error: No KGF specs found")
      None
    }
  }
}

///|
/// Run token pattern search across files.
pub fn run_pattern_search(
  paths : Array[String],
  matchers : Array[TokenMatcher],
  config : GrepConfig,
) -> Unit {
  let (registry, files) = match load_registry_and_files(paths, config) {
    Some(r) => r
    None => return
  }
  if files.length() == 0 {
    return
  }
  let mut total_matches = 0
  let mut total_files = 0
  for file in files {
    let (path, content) = file
    let spec = match registry {
      Some(reg) =>
        match reg.detect_from_path(path) {
          Some(lang) => reg.get_spec(lang)
          None => None
        }
      None => None
    }
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = find_matches(tokens, matchers, path, content, spec~)
    if matches.length() == 0 {
      continue
    }
    total_files += 1
    total_matches += matches.length()
    if config.files_only {
      println(path)
      continue
    }
    if config.count_only {
      println(path + ":" + matches.length().to_string())
      continue
    }
    let lines = @common.split_lines(content)
    for m in matches {
      print_match(m, lines, config.context_lines)
    }
  }
  if !config.files_only && !config.count_only {
    println("")
    println(
      total_matches.to_string() +
      " matches in " +
      total_files.to_string() +
      " files",
    )
  }
}

///|
/// Run a semantic query search across files.
pub fn run_semantic_search(
  paths : Array[String],
  query : SemanticQuery,
  config : GrepConfig,
) -> Unit {
  // Vector similarity search has its own corpus-level flow
  match query {
    Similar(query_text, top_k) => {
      run_similar_search(paths, query_text, top_k, config)
      return
    }
    _ => ()
  }
  let (registry, files) = match load_registry_and_files(paths, config) {
    Some(r) => r
    None => return
  }
  let mut total_matches = 0
  let mut total_files = 0
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = run_semantic_query_on_file(
      query, tokens, path, content, registry,
    )
    if matches.length() == 0 {
      continue
    }
    total_files += 1
    total_matches += matches.length()
    if config.files_only {
      println(path)
      continue
    }
    if config.count_only {
      println(path + ":" + matches.length().to_string())
      continue
    }
    for m in matches {
      println(
        m.file +
        ":" +
        m.line.to_string() +
        ": " +
        m.kind +
        " " +
        m.name +
        "  (" +
        m.detail +
        ")",
      )
    }
  }
  println("")
  println(
    total_matches.to_string() +
    " matches in " +
    total_files.to_string() +
    " files",
  )
}

///|
/// Collect files for searching, applying includes/excludes and KGF ignore patterns.
fn collect_search_files(
  paths : Array[String],
  config : GrepConfig,
  registry : @kgf_registry.KGFRegistry,
) -> Array[(String, String)] {
  @common.collect_files(
    paths,
    includes=config.includes,
    excludes=config.excludes,
    registry=Some(registry),
  )
}

///|
/// Run token pattern search and return matches as JSON string.
/// For use by `indexion serve` API endpoint.
pub fn run_pattern_search_json(
  paths : Array[String],
  matchers : Array[TokenMatcher],
  config : GrepConfig,
) -> String? {
  let (registry, files) = match load_registry_and_files(paths, config) {
    Some(r) => r
    None => return None
  }
  if files.length() == 0 {
    return Some("[]")
  }
  let results : Array[Json] = []
  for file in files {
    let (path, content) = file
    let spec = match registry {
      Some(reg) =>
        match reg.detect_from_path(path) {
          Some(lang) => reg.get_spec(lang)
          None => None
        }
      None => None
    }
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = find_matches(tokens, matchers, path, content, spec~)
    for m in matches {
      let obj : Map[String, Json] = {}
      obj["file"] = m.file.to_json()
      obj["line"] = m.line.to_json()
      obj["matched"] = m.matched_text.to_json()
      results.push(Json::object(obj))
    }
  }
  Some(Json::array(results).stringify(indent=2))
}

///|
/// Prepare grep search: load registry, collect files, parse pattern.
/// Returns (registry, files, matchers) or None if setup fails.
pub fn prepare_pattern_search(
  paths : Array[String],
  config : GrepConfig,
) -> (@kgf_registry.KGFRegistry?, Array[(String, String)], Array[TokenMatcher])? {
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=paths,
  )
  let aliases = build_alias_table(registry)
  let matchers = parse_pattern_with_aliases(config.pattern, aliases)
  if matchers.length() == 0 {
    return None
  }
  let files = collect_search_files(
    paths,
    config,
    match registry {
      Some(r) => r
      None =>
        @kgf_features.load_registry_or_empty(
          specs_dir=config.specs_dir,
          target_dirs=paths,
        )
    },
  )
  Some((registry, files, matchers))
}

///|
/// Process a single file for grep matches, returning JSON items.
pub fn grep_single_file(
  path : String,
  content : String,
  matchers : Array[TokenMatcher],
  registry : @kgf_registry.KGFRegistry?,
) -> Array[Json] {
  let tokens = match @kgf_features.tokenize_source(content, path, registry) {
    Some(t) => t
    None => return []
  }
  let spec = match registry {
    Some(reg) =>
      match reg.detect_from_path(path) {
        Some(lang) => reg.get_spec(lang)
        None => None
      }
    None => None
  }
  let matches = find_matches(tokens, matchers, path, content, spec~)
  let results : Array[Json] = []
  for m in matches {
    let obj : Map[String, Json] = {}
    obj["file"] = m.file.to_json()
    obj["line"] = m.line.to_json()
    obj["matched"] = m.matched_text.to_json()
    results.push(Json::object(obj))
  }
  results
}

///|
/// Run semantic search and return matches as JSON string.
/// For use by `indexion serve` API endpoint.
pub fn run_semantic_search_json(
  paths : Array[String],
  query : SemanticQuery,
  config : GrepConfig,
) -> String? {
  match query {
    Similar(_, _) => return None // Similar requires async embedding — not supported via grep API
    _ => ()
  }
  let (registry, files) = match load_registry_and_files(paths, config) {
    Some(r) => r
    None => return None
  }
  let results : Array[Json] = []
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = run_semantic_query_on_file(
      query, tokens, path, content, registry,
    )
    for m in matches {
      let obj : Map[String, Json] = {}
      obj["file"] = m.file.to_json()
      obj["line"] = m.line.to_json()
      obj["kind"] = m.kind.to_json()
      obj["name"] = m.name.to_json()
      obj["detail"] = m.detail.to_json()
      results.push(Json::object(obj))
    }
  }
  Some(Json::array(results).stringify(indent=2))
}

///|
fn print_match(m : GrepMatch, lines : Array[String], context : Int) -> Unit {
  let line_idx = m.line - 1
  let start = if line_idx - context < 0 { 0 } else { line_idx - context }
  let end = if line_idx + context + 1 > lines.length() {
    lines.length()
  } else {
    line_idx + context + 1
  }
  if context > 0 {
    for i = start; i < end; i = i + 1 {
      let prefix = if i == line_idx { ">" } else { " " }
      println(
        m.file +
        ":" +
        (i + 1).to_string() +
        ":" +
        prefix +
        (if i < lines.length() { lines[i] } else { "" }),
      )
    }
    println("--")
  } else {
    let line_text = if line_idx < lines.length() { lines[line_idx] } else { "" }
    println(m.file + ":" + m.line.to_string() + ": " + line_text)
  }
}
