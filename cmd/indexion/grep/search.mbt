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
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    recursive=true,
    includes=config.includes,
    excludes=config.excludes,
    include_hidden=true,
    kgf_ignore~,
  )
  let results : Array[(String, String)] = []
  let supported = @pipeline.collect_supported_file_info(
    paths, discover_opts, registry,
  )
  for file in supported {
    results.push((file.path, file.content))
  }
  results
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
