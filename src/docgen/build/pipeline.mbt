// Main documentation build pipeline.

///|
/// Build documentation from configuration.
/// This is the main entry point for documentation generation.
pub fn build(config : DocConfig) -> @render.DocOutput {
  // Phase 1: Analyze each file with appropriate KGF spec
  let graphs = analyze_files(config.files, config.specs)
  // Phase 2: Merge all graphs
  let merged = merge_graphs(graphs)
  // Phase 3: Render based on format
  match config.options.format {
    @render.Markdown => @render.render_markdown(merged, config.options)
    @render.Json => @render.DocOutput::with_json(@render.render_json(merged))
  }
}

///|
/// Build documentation and return both the output and the merged graph.
pub fn build_with_graph(
  config : DocConfig,
) -> (@render.DocOutput, @graph.CodeGraph) {
  build_with_graph_progress(config, None)
}

///|
/// Build documentation with progress callback.
pub fn build_with_graph_progress(
  config : DocConfig,
  on_progress : ProgressCallback?,
) -> (@render.DocOutput, @graph.CodeGraph) {
  let graphs = analyze_files_with_progress(
    config.files,
    config.specs,
    on_progress,
  )
  let merged = merge_graphs(graphs)
  let output = match config.options.format {
    @render.Markdown => @render.render_markdown(merged, config.options)
    @render.Json => @render.DocOutput::with_json(@render.render_json(merged))
  }
  (output, merged)
}

///|
/// Build registry from specs map.
fn build_registry(
  specs : Map[String, @kgf_types.KGFSpec],
) -> @registry.KGFRegistry {
  let registry = @registry.KGFRegistry::new()
  for entry in specs {
    registry.register_spec(entry.1)
  }
  registry
}

///|
/// Progress callback type for file analysis.
pub struct ProgressCallback(((Int, Int, String)) -> Unit)

///|
/// Create a progress callback.
pub fn ProgressCallback::new(
  callback : ((Int, Int, String)) -> Unit,
) -> ProgressCallback {
  ProgressCallback(callback)
}

///|
/// Analyze files with their corresponding KGF specs.
fn analyze_files(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
) -> Array[@graph.CodeGraph] {
  analyze_files_with_progress(files, specs, None)
}

///|
/// Analyze files with progress callback.
pub fn analyze_files_with_progress(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
  on_progress : ProgressCallback?,
) -> Array[@graph.CodeGraph] {
  // Build registry for language/spec detection
  let registry = build_registry(specs)
  // Build a set of known file paths for resolution
  let known_paths : Map[String, Bool] = {}
  for entry in files {
    known_paths.set(entry.0, true)
  }
  // Create a file_exists function that checks against known paths
  let file_exists = fn(path : String) -> Bool { known_paths.contains(path) }
  // Use empty root - paths are already relative to working directory
  let root = ""
  let active_rules_cache : Map[String, @hashset.HashSet[String]] = Map::new()
  let peg_cache : Map[String, @kgf_peg.PEG] = Map::new()
  let lexer_cache : Map[String, @kgf_lexer.Lexer] = Map::new()
  let graphs : Array[@graph.CodeGraph] = []
  let total = files.length()
  for i, entry in files {
    let path = entry.0
    let content = entry.1
    // Report progress
    match on_progress {
      Some(ProgressCallback(callback)) => callback((i + 1, total, path))
      None => ()
    }
    // Detect language and get spec name using registry
    let file_info = @analyze.analyze_file_with_registry(registry, path, content)
    let spec_name = file_info.get_spec_name()
    // Try to get the spec
    match specs.get(spec_name) {
      Some(spec) => {
        let active_rules = match active_rules_cache.get(spec_name) {
          Some(cached) => cached
          None => {
            let built = @kgf_peg.collect_active_rules(spec)
            active_rules_cache.set(spec_name, built)
            built
          }
        }
        let lexer = get_or_build_lexer(spec_name, spec, lexer_cache)
        match get_or_build_peg(spec_name, spec, peg_cache) {
          Some(peg) => {
            let graph = analyze_with_spec(
              path, content, spec, active_rules, root, file_exists, lexer, peg,
            )
            graphs.push(graph)
          }
          None => {
            let graph = @graph.CodeGraph::new()
            let _ = graph.get_or_add_module(path, file=Some(path))
            graphs.push(graph)
          }
        }
      }
      None => {
        // No spec available, create minimal graph with just the module
        let graph = @graph.CodeGraph::new()
        let _ = graph.get_or_add_module(path, file=Some(path))
        graphs.push(graph)
      }
    }
  }
  graphs
}

///|
fn get_or_build_lexer(
  spec_name : String,
  spec : @kgf_types.KGFSpec,
  cache : Map[String, @kgf_lexer.Lexer],
) -> @kgf_lexer.Lexer {
  match cache.get(spec_name) {
    Some(lexer) => lexer
    None => {
      let built = @kgf_lexer.Lexer::new(spec.get_tokens())
      cache.set(spec_name, built)
      built
    }
  }
}

///|
fn get_or_build_peg(
  spec_name : String,
  spec : @kgf_types.KGFSpec,
  cache : Map[String, @kgf_peg.PEG],
) -> @kgf_peg.PEG? {
  match cache.get(spec_name) {
    Some(peg) => Some(peg)
    None => {
      let built = Some(@kgf_peg.build_peg(spec)) catch { _ => None }
      match built {
        Some(peg) => {
          cache.set(spec_name, peg)
          Some(peg)
        }
        None => None
      }
    }
  }
}

///|
/// Find common root directory from file paths.
fn find_common_root(files : Array[(String, String)]) -> String {
  if files.length() == 0 {
    return ""
  }
  let first_path = files[0].0
  let parts = split_path(first_path)
  let mut common_len = parts.length() - 1 // Exclude filename
  for entry in files {
    let p = split_path(entry.0)
    let limit = if p.length() - 1 < common_len {
      p.length() - 1
    } else {
      common_len
    }
    let mut match_len = 0
    for i = 0; i < limit; i = i + 1 {
      if parts[i] == p[i] {
        match_len = i + 1
      } else {
        break
      }
    }
    common_len = match_len
  }
  if common_len == 0 {
    return ""
  }
  let result : Array[String] = []
  for i = 0; i < common_len; i = i + 1 {
    result.push(parts[i])
  }
  join_path_parts(result)
}

///|
/// Split path into parts.
fn split_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for c in path {
    if c == '/' {
      if current.length() > 0 {
        parts.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if current.length() > 0 {
    parts.push(String::from_array(current))
  }
  parts
}

///|
/// Join path parts with '/'.
fn join_path_parts(parts : Array[String]) -> String {
  if parts.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, part in parts {
    if i > 0 {
      result.push('/')
    }
    for c in part {
      result.push(c)
    }
  }
  String::from_array(result)
}

///|
/// Analyze a single file with a KGF spec.
fn analyze_with_spec(
  path : String,
  content : String,
  spec : @kgf_types.KGFSpec,
  active_rules : @hashset.HashSet[String],
  root : String,
  file_exists : (String) -> Bool,
  lexer : @kgf_lexer.Lexer,
  peg : @kgf_peg.PEG,
) -> @graph.CodeGraph {
  let graph = @graph.CodeGraph::new()
  // Create module node for the file
  let _ = graph.get_or_add_module(path, file=Some(path))
  // Tokenize using cached lexer.
  let tokens = lexer.tokenize(content)
  // Get start rule
  let start_rule = spec.get_start_rule()
  // Run parse
  let parse_result = @kgf_peg.run_parse_filtered(
    peg, spec, start_rule, tokens, active_rules,
  )
  // Evaluate semantics for all matched rules (via events)
  match parse_result {
    Some(eval_result) => {
      let ctx = @kgf_semantics.SemEvalCtx::new(
        spec,
        graph,
        path,
        root,
        spec.get_language(),
        file_exists,
      )
      // Process all rule match events for semantic evaluation
      for event in eval_result.get_events() {
        let rule_name = event.0
        let labels = event.1
        @kgf_semantics.eval_rule_semantics(rule_name, labels, ctx)
      }
    }
    None => ()
  }
  graph
}

///|
/// Merge multiple graphs into one.
pub fn merge_graphs(graphs : Array[@graph.CodeGraph]) -> @graph.CodeGraph {
  if graphs.length() == 0 {
    return @graph.CodeGraph::new()
  }
  if graphs.length() == 1 {
    return graphs[0]
  }
  let merged = @graph.CodeGraph::new()
  for graph in graphs {
    // Merge modules
    for entry in graph.get_modules() {
      let m = entry.1
      let _ = merged.get_or_add_module(m.id, file=m.file)
    }
    // Merge symbols
    for entry in graph.get_symbols() {
      let s = entry.1
      let _ = merged.get_or_add_symbol(
        s.id,
        name=s.name,
        kind=s.kind,
        ns=s.ns,
        module_id=s.module_id,
        doc=s.doc,
      )
    }
    // Merge edges
    for edge in graph.get_edges() {
      merged.add_edge(edge.kind, edge.from, edge.to, attrs=edge.attrs)
    }
  }
  merged
}

///|
/// Quick build from files without explicit spec loading.
/// Uses spec name detection to select appropriate specs.
pub fn quick_build(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
) -> @render.DocOutput {
  let config = DocConfig::new(files, specs)
  build(config)
}

///|
/// Build and return markdown string.
pub fn build_markdown(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
) -> String {
  let config = DocConfig::new(
    files,
    specs,
    options=@render.RenderOptions::with_format(@render.OutputFormat::markdown()),
  )
  let output = build(config)
  output.to_markdown()
}

///|
/// Build and return JSON string.
pub fn build_json(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
) -> String {
  let config = DocConfig::new(
    files,
    specs,
    options=@render.RenderOptions::with_format(@render.OutputFormat::json()),
  )
  let output = build(config)
  output.json_data.unwrap_or("")
}

// Legacy compatibility functions

///|
/// Group symbols by file.
pub fn group_by_file(
  symbols : Array[@analyze.DocSymbol],
) -> Map[String, Array[@analyze.DocSymbol]] {
  let result : Map[String, Array[@analyze.DocSymbol]] = {}
  for sym in symbols {
    let file = sym.get_file()
    match result.get(file) {
      Some(arr) => arr.push(sym)
      None => result.set(file, [sym])
    }
  }
  result
}

///|
/// Group symbols by kind.
pub fn group_by_kind(
  symbols : Array[@analyze.DocSymbol],
) -> Map[String, Array[@analyze.DocSymbol]] {
  let result : Map[String, Array[@analyze.DocSymbol]] = {}
  for sym in symbols {
    let kind = sym.get_kind()
    match result.get(kind) {
      Some(arr) => arr.push(sym)
      None => result.set(kind, [sym])
    }
  }
  result
}

///|
/// Generate markdown from analysis result.
/// Legacy function for backward compatibility.
pub fn generate_markdown(result : @analyze.AnalysisResult) -> String {
  let graph = result.get_graph()
  let options = @render.RenderOptions::default()
  let output = @render.render_markdown(graph, options)
  output.to_markdown()
}
