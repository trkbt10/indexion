///|
/// Search engine — file discovery, tokenization, and output formatting.

///|
/// Run token pattern search across files.
pub fn run_pattern_search(
  paths : Array[String],
  matchers : Array[TokenMatcher],
  config : GrepConfig,
) -> Unit {
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=paths,
  )
  let reg = match registry {
    Some(r) => r
    None => {
      println("Error: No KGF specs found")
      return
    }
  }
  let files = collect_search_files(paths, config, reg)
  if files.length() == 0 {
    return
  }
  let mut total_matches = 0
  let mut total_files = 0
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = find_matches(tokens, matchers, path, content)
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
  if !(config.files_only) && !(config.count_only) {
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
  let registry = @kgf_features.load_registry(
    specs_dir=config.specs_dir,
    target_dirs=paths,
  )
  let reg = match registry {
    Some(r) => r
    None => {
      println("Error: No KGF specs found")
      return
    }
  }
  let files = collect_search_files(paths, config, reg)
  let mut total_matches = 0
  let mut total_files = 0
  for file in files {
    let (path, content) = file
    let tokens = match @kgf_features.tokenize_source(content, path, registry) {
      Some(t) => t
      None => continue
    }
    let matches = run_semantic_query_on_file(query, tokens, path, content, registry)
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
        m.file + ":" + m.line.to_string() + ": " + m.kind + " " + m.name +
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
    excludes=config.excludes,
    kgf_ignore~,
  )
  let candidate_paths = @pipeline.discover_files(paths, discover_opts)
  let extensions = registry.get_extensions()
  let results : Array[(String, String)] = []
  for path in candidate_paths {
    // Check include patterns
    if config.includes.length() > 0 {
      let mut matched = false
      for inc in config.includes {
        if @glob.glob_match(path, inc) {
          matched = true
          break
        }
      }
      if !(matched) {
        continue
      }
    }
    // Check file has a registered extension
    let mut has_ext = false
    for ext in extensions {
      if path.has_suffix(ext) {
        has_ext = true
        break
      }
    }
    if !(has_ext) {
      continue
    }
    try {
      let content = @fs.read_file_to_string(path)
      results.push((path, content))
    } catch {
      _ => ()
    }
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
