///|
fn source_test_file(
  path : String,
  content : String,
  content_type? : String? = None,
) -> @pipeline.SupportedFile {
  { path, content, language: "moonbit", content_type }
}

///|
fn repeated_source_text(seed : String, count : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<count {
    out.write_string(seed)
  }
  out.to_string()
}

///|
fn single_file_graph(path : String) -> @graph.CodeGraph {
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let _ = graph.get_or_add_symbol(
    path + "::refresh_cache",
    name="refresh_cache",
    kind="Function",
    ns=path,
    module_id=path,
    doc=Some("updates bounded cache records"),
  )
  graph.add_note("module_doc", "cache source module documentation", path)
  graph
}

///|
fn empty_orient_status() -> @types.AgentOrientMapStatus {
  {
    total_files: 0,
    total_owners: 0,
    total_doc_sources: 0,
    changed_files: [],
    new_files: [],
    deleted_files: [],
    knowledge_changed: false,
    refreshed_owners: [],
    reused_owners: [],
  }
}

///|
test "agent orient source: code briefs use bounded cache summaries" {
  let sentinel = "UNBOUNDED_SENTINEL_AFTER_LIMIT"
  let content = repeated_source_text("let noisy_cache_value = 42\n", 40) +
    sentinel
  let file = source_test_file(
    "src/agent/orient/source/cache_input.mbt", content,
  )
  let graph = single_file_graph(file.path)
  let briefs = build_file_briefs([file], graph, None)
  assert_eq(briefs.length(), 1)
  let brief = briefs[0]
  assert_eq(brief.path, file.path)
  assert_eq(brief.role, "implementation")
  assert_true(brief.structural_summary.contains("refresh_cache"))
  assert_true(
    brief.structural_summary.contains("cache source module documentation"),
  )
  assert_true(brief.summary.length() <= @cache.summary_preview_limit)
  assert_false(brief.summary.contains(sentinel))
  assert_false(brief.summary.contains(content))
  assert_false(brief.summary_terms.contains("sentinel"))
}

///|
test "agent orient source: cached code briefs are re-bounded before reuse" {
  let sentinel = "CACHED_UNBOUNDED_SENTINEL_AFTER_LIMIT"
  let content = repeated_source_text("fn cached_value() -> Int { 1 }\n", 40) +
    sentinel
  let file = source_test_file(
    "src/agent/orient/source/cached_input.mbt", content,
  )
  let source_hash = @cas_hash.compute_hash(file.content).to_string()
  let cached_file : @types.AgentOrientMapFile = {
    path: file.path,
    role: "implementation",
    source_hash,
    owner: owner_dir(file.path),
    structural_summary: "cached structure for " + file.path,
    summary: file.path + "\n" + content,
  }
  let cached_map : @types.AgentOrientMap = {
    version: "agent-orient-v1",
    knowledge_hash: "",
    files: [cached_file],
    owners: [],
    status: empty_orient_status(),
  }
  let briefs = build_file_briefs(
    [file],
    single_file_graph(file.path),
    Some(cached_map),
  )
  assert_eq(briefs.length(), 1)
  let brief = briefs[0]
  assert_eq(brief.structural_summary, cached_file.structural_summary)
  assert_eq(brief.role, cached_file.role)
  assert_true(brief.summary.length() <= @cache.summary_preview_limit)
  assert_false(brief.summary.contains(sentinel))
  assert_false(brief.summary.contains(cached_file.summary))
}

///|
test "agent orient source: documentation briefs keep full summary text" {
  let sentinel = "DOCUMENTATION_FULL_TEXT_SENTINEL"
  let content = "# Orient cache notes\n\n" +
    repeated_source_text("Detailed persistence note.\n", 30) +
    sentinel
  let file = source_test_file(
    "docs/orient-cache-notes.md",
    content,
    content_type=Some("document"),
  )
  let briefs = build_file_briefs([file], single_file_graph(file.path), None)
  assert_eq(briefs.length(), 1)
  let brief = briefs[0]
  assert_eq(brief.role, "documentation")
  assert_true(brief.summary.contains(content))
  assert_true(brief.summary.contains(sentinel))
  assert_true(brief.summary_terms.contains("sentinel"))
}

///|
test "agent orient source: role and owner signals survive bounded summaries" {
  let file = source_test_file(
    "cmd/indexion/agent/orient_cli.mbt",
    repeated_source_text("fn main() { run() }\n", 40),
  )
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(file.path, file=Some(file.path))
  let attrs : Map[String, String] = {}
  attrs.set("via", "argparse")
  graph.add_edge(
    @graph.EdgeKind::from_string("moduleDependsOn"),
    file.path,
    "pkg:moonbitlang/argparse",
    attrs~,
  )
  let briefs = build_file_briefs([file], graph, None)
  assert_eq(briefs.length(), 1)
  assert_eq(briefs[0].role, "cli-consumer")
  assert_eq(owner_dir(briefs[0].path), "cmd/indexion/agent")
}

///|
test "agent orient source: graph discovery returns graph-only data" {
  let registry = @kgf_registry.KGFRegistry::new()
  let file = source_test_file(
    "virtual/render-heavy.mbt",
    repeated_source_text("fn rendered_symbol() -> Int { 1 }\n", 100),
  )
  let graph = build_graph([file], registry)
  assert_eq(graph.module_count(), 1)
  assert_true(graph.get_module(file.path) is Some(_))
}
