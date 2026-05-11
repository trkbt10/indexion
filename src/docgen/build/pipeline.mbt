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
  let merged = build_graph_only_progress(config, on_progress)
  let output = match config.options.format {
    @render.Markdown => @render.render_markdown(merged, config.options)
    @render.Json => @render.DocOutput::with_json(@render.render_json(merged))
  }
  (output, merged)
}

///|
/// Build the enriched merged graph without rendering documentation. Callers
/// that only need the graph (e.g. agent orient discovery) must use this to
/// avoid the large-string overhead of rendering Markdown/JSON.
pub fn build_graph_only(config : DocConfig) -> @graph.CodeGraph {
  build_graph_only_progress(config, None)
}

///|
fn build_graph_only_progress(
  config : DocConfig,
  on_progress : ProgressCallback?,
) -> @graph.CodeGraph {
  let (graphs, file_tokens) = analyze_files_collect(
    config.files,
    config.specs,
    on_progress,
  )
  let merged = merge_graphs(graphs)
  enrich_graph(merged, file_tokens, config.specs)
  merged
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
  let (graphs, _) = analyze_files_collect(files, specs, on_progress)
  graphs
}

///|
/// Per-file tokens captured during analysis. `spec_name` enables a second pass
/// (enrichment) to know which language the file was parsed with without having
/// to re-detect it.
pub struct FileTokens {
  path : String
  spec_name : String
  tokens : Array[@kgf_types.Tok]
}

///|
pub fn FileTokens::new(
  path : String,
  spec_name : String,
  tokens : Array[@kgf_types.Tok],
) -> FileTokens {
  { path, spec_name, tokens }
}

///|
pub fn FileTokens::get_path(self : FileTokens) -> String {
  self.path
}

///|
pub fn FileTokens::get_spec_name(self : FileTokens) -> String {
  self.spec_name
}

///|
pub fn FileTokens::get_tokens(self : FileTokens) -> Array[@kgf_types.Tok] {
  self.tokens
}

///|
/// Analyze files and also collect per-file tokens. Tokens feed the post-merge
/// enrichment pass which emits cross-package edges that grammar-level analysis
/// cannot produce on its own (e.g. MoonBit `@alias` usages resolved via the
/// sibling `moon.pkg`).
pub fn analyze_files_collect(
  files : Array[(String, String)],
  specs : Map[String, @kgf_types.KGFSpec],
  on_progress : ProgressCallback?,
) -> (Array[@graph.CodeGraph], Array[FileTokens]) {
  let registry = build_registry(specs)
  let known_paths : Map[String, Bool] = {}
  for entry in files {
    known_paths.set(entry.0, true)
  }
  let file_exists = fn(path : String) -> Bool {
    known_paths.contains(path) || (@fs.is_file(path) catch { _ => false })
  }
  let read_file = fn(path : String) -> String? {
    Some(@fs.read_file_to_string(path)) catch {
      _ => None
    }
  }
  let root = ""
  let active_rules_cache : Map[String, @hashset.HashSet[String]] = Map::new()
  let peg_cache : Map[String, @kgf_peg.PEG] = Map::new()
  let lexer_cache : Map[String, @kgf_toolkit.LanguageToolkit] = Map::new()
  let graphs : Array[@graph.CodeGraph] = []
  let file_tokens : Array[FileTokens] = []
  let total = files.length()
  for i, entry in files {
    let path = entry.0
    let content = entry.1
    match on_progress {
      Some(ProgressCallback(callback)) => callback((i + 1, total, path))
      None => ()
    }
    let file_info = @analyze.analyze_file_with_registry(registry, path, content)
    let spec_name = file_info.get_spec_name()
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
            let (graph, tokens) = analyze_with_spec_collect(
              path, content, spec, active_rules, root, file_exists, read_file, lexer,
              peg,
            )
            graphs.push(graph)
            file_tokens.push(FileTokens::new(path, spec_name, tokens))
          }
          None => {
            let graph = @graph.CodeGraph::new()
            let _ = graph.get_or_add_module(path, file=Some(path))
            graphs.push(graph)
            file_tokens.push(FileTokens::new(path, spec_name, []))
          }
        }
      }
      None => {
        let graph = @graph.CodeGraph::new()
        let _ = graph.get_or_add_module(path, file=Some(path))
        graphs.push(graph)
        file_tokens.push(FileTokens::new(path, spec_name, []))
      }
    }
  }
  (graphs, file_tokens)
}

///|
/// Get or build a lexer for a spec, using ToolkitRegistry's built-in cache.
fn get_or_build_lexer(
  spec_name : String,
  _spec : @kgf_types.KGFSpec,
  toolkit_cache : Map[String, @kgf_toolkit.LanguageToolkit],
) -> @kgf_lexer.Lexer {
  match toolkit_cache.get(spec_name) {
    Some(toolkit) => toolkit.get_lexer()
    None => {
      let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(_spec)
      toolkit_cache.set(spec_name, toolkit)
      toolkit.get_lexer()
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
/// Analyze a single file with a KGF spec, returning the per-file graph and the
/// tokenization so downstream enrichment passes can run token-level queries
/// (e.g. PackageRef scans) without re-tokenizing.
fn analyze_with_spec_collect(
  path : String,
  content : String,
  spec : @kgf_types.KGFSpec,
  active_rules : @hashset.HashSet[String],
  root : String,
  file_exists : (String) -> Bool,
  read_file : (String) -> String?,
  lexer : @kgf_lexer.Lexer,
  peg : @kgf_peg.PEG,
) -> (@graph.CodeGraph, Array[@kgf_types.Tok]) {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let tokens = lexer.tokenize(content)
  let start_rule = spec.get_start_rule()
  let parse_result = @kgf_peg.run_parse_filtered(
    peg, spec, start_rule, tokens, active_rules,
  )
  match parse_result {
    Some(eval_result) => {
      let ctx = @kgf_semantics.SemEvalCtx::new(
        spec,
        graph,
        path,
        root,
        spec.get_language(),
        file_exists,
        read_file~,
      )
      for event in eval_result.get_events() {
        let rule_name = event.0
        let labels = event.1
        @kgf_semantics.eval_rule_semantics(rule_name, labels, ctx)
      }
    }
    None => ()
  }
  (graph, tokens)
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
