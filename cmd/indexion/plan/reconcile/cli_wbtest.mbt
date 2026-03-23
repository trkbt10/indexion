///|
fn document_symbol_kinds_for_path(
  path : String,
  registry : @registry.KGFRegistry,
) -> Map[String, Bool] {
  let fallback = default_document_symbol_kinds()
  match registry.detect_from_path(path) {
    Some(lang) =>
      match registry.get_spec(lang) {
        Some(spec) =>
          match spec.get_feature("document_symbol_kinds") {
            Some(values) => {
              let configured : Map[String, Bool] = {}
              for value in values {
                let normalized = lower_string(@common.trim_ascii_spaces(value))
                if normalized.length() > 0 {
                  configured.set(normalized, true)
                }
              }
              if configured.is_empty() {
                fallback
              } else {
                configured
              }
            }
            None => fallback
          }
        None => fallback
      }
    None => fallback
  }
}

///|
fn should_include_symbol(
  kind : String,
  module_path : String,
  registry : @registry.KGFRegistry,
) -> Bool {
  document_symbol_kinds_for_path(module_path, registry).contains(
    lower_string(kind),
  )
}

///|
fn extract_code_units(
  graph : @graph.CodeGraph,
  registry : @registry.KGFRegistry,
) -> Array[CodeUnit] {
  let units : Array[CodeUnit] = []
  for entry in graph.get_symbols() {
    let symbol = entry.1
    let module_path = match graph.get_module(symbol.module_id) {
      Some(module_node) =>
        match module_node.file {
          Some(file) => file
          None => symbol.module_id
        }
      None => symbol.module_id
    }
    if not(should_include_symbol(symbol.kind, module_path, registry)) {
      continue
    }
    let code_hash = make_hash([
      symbol.id,
      symbol.name,
      symbol.kind,
      symbol.ns,
      module_path,
      match symbol.doc {
        Some(doc) => doc
        None => ""
      },
    ])
    units.push({
      symbol_id: symbol.id,
      name: symbol.name,
      kind: symbol.kind,
      ns: symbol.ns,
      module_id: symbol.module_id,
      module_path,
      inline_doc: symbol.doc,
      code_hash,
    })
  }
  units.sort_by(fn(a, b) { a.symbol_id.compare(b.symbol_id) })
  units
}

///|
fn match_fragment(
  unit : CodeUnit,
  _fragment : DocFragment,
  signals : FragmentMatchSignals,
  allow_file_fallback : Bool,
) -> (Int, String, Array[String]) {
  match_fragment_with_terms(
    unit,
    unit_match_terms(unit),
    signals,
    allow_file_fallback,
  )
}

///|
fn temp_reconcile_dir(prefix : String) -> String {
  prefix + @env.now().to_string()
}

///|
fn load_test_registry() -> @registry.KGFRegistry {
  @kgf_features.load_registry_or_empty(target_dir=".")
}

///|
fn remove_file_if_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn remove_dir_if_exists(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_dir(path) catch {
      _ => ()
    }
  }
}

///|
test "reconcile: resolve_config keeps default index dir under target root" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-default-")
  @config_paths.ensure_dir_recursive(dir)
  let matches = try! command().parse(argv=[dir][:], env={})
  let config = resolve_config_from_matches(matches)
  assert_eq(config.target_dir, dir)
  assert_eq(config.index_dir, dir + "/.indexion/cache/reconcile")
  remove_dir_if_exists(dir)
}

///|
test "reconcile: resolve_config applies package-docs preset" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-scope-package-")
  @config_paths.ensure_dir_recursive(dir)
  let matches = try! command().parse(argv=["--scope=package-docs", dir][:], env={})
  let config = resolve_config_from_matches(matches)
  assert_eq(config.documents.scope_name, "package-docs")
  assert_eq(config.documents.doc_paths, ["README.md", "docs/**/*.md"])
  assert_eq(config.documents.doc_specs, ["markdown"])
  assert_true(config.documents.path_scope.matches_path("README.md"))
  remove_dir_if_exists(dir)
}

///|
test "reconcile: explicit doc filters override scope preset defaults" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-scope-explicit-")
  @config_paths.ensure_dir_recursive(dir)
  let matches = try! command().parse(
    argv=[
        "--scope=tree-docs", "--doc=notes/**/*.txt", "--doc-spec=plaintext", dir,
      ][:],
    env={},
  )
  let config = resolve_config_from_matches(matches)
  assert_eq(config.documents.scope_name, "tree-docs")
  assert_eq(config.documents.doc_paths, ["notes/**/*.txt"])
  assert_eq(config.documents.doc_specs, ["plaintext"])
  remove_dir_if_exists(dir)
}

///|
test "reconcile: explicit cli filters win over file config filters" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-precedence-")
  @config_paths.ensure_dir_recursive(dir)
  let config_path = dir + "/.indexion.toml"
  let config_content =
    #|[reconcile]
    #|doc_scope = "package-docs"
    #|doc_paths = ["docs/**/*.md"]
    #|doc_specs = ["markdown"]
    #|threshold_seconds = 120
  @fs.write_string_to_file(config_path, config_content) catch {
    _ => ()
  }
  let matches = try! command().parse(
    argv=[
        "--scope=tree-docs", "--doc=notes/**/*.txt", "--doc-spec=plaintext", "--threshold-seconds=30",
        dir,
      ][:],
    env={},
  )
  let config = resolve_config_from_matches(matches)
  assert_eq(config.documents.scope_name, "tree-docs")
  assert_eq(config.documents.doc_paths, ["notes/**/*.txt"])
  assert_eq(config.documents.doc_specs, ["plaintext"])
  assert_eq(config.threshold_seconds, 30)
  remove_file_if_exists(config_path)
  remove_dir_if_exists(dir)
}

///|
test "reconcile: explicit cli filters clear implicit file scope label" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-scope-clear-")
  @config_paths.ensure_dir_recursive(dir)
  let config_path = dir + "/.indexion.toml"
  let config_content =
    #|[reconcile]
    #|doc_scope = "package-docs"
  @fs.write_string_to_file(config_path, config_content) catch {
    _ => ()
  }
  let matches = try! command().parse(argv=["--doc=notes/**/*.txt", dir][:], env={})
  let config = resolve_config_from_matches(matches)
  assert_eq(config.documents.scope_name, "custom")
  assert_eq(config.documents.doc_paths, ["notes/**/*.txt"])
  remove_file_if_exists(config_path)
  remove_dir_if_exists(dir)
}

///|
test "reconcile: document path selection uses shared scope matcher" {
  let config = {
    ..ReconcileConfig::default(),
    target_dir: "pkg",
    documents: @config_paths.resolve_reconcile_document_scope("custom", doc_paths=[
      "docs/**/README.[mdt][xd]",
    ]),
  }
  let registry = load_test_registry()
  assert_true(is_document_path("pkg/docs/api/README.md", config, registry))
  assert_false(is_document_path("pkg/notes/README.txt", config, registry))
}

///|
test "reconcile: resolve_config rebases config-relative paths" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-file-")
  @config_paths.ensure_dir_recursive(dir)
  let config_path = dir + "/.indexion.toml"
  let config_content =
    #|[reconcile]
    #|index_dir = ".cache/reconcile-db"
    #|review_results_path = ".indexion/reconcile/reviews.json"
  @fs.write_string_to_file(config_path, config_content) catch {
    _ => ()
  }
  let matches = try! command().parse(argv=[dir][:], env={})
  let config = resolve_config_from_matches(matches)
  assert_eq(config.config_path, config_path)
  assert_eq(config.index_dir, dir + "/.cache/reconcile-db")
  assert_eq(
    config.review_results_path,
    dir + "/.indexion/reconcile/reviews.json",
  )
  remove_file_if_exists(config_path)
  remove_dir_if_exists(dir)
}

///|
test "reconcile: resolve_config rebases cli relative paths to target root" {
  let dir = temp_reconcile_dir(".indexion/reconcile-config-cli-")
  @config_paths.ensure_dir_recursive(dir)
  let matches = try! command().parse(
    argv=[
        "--index-dir=.cache/reconcile-db", "--review-results=.indexion/reconcile/reviews.json",
        dir,
      ][:],
    env={},
  )
  let config = resolve_config_from_matches(matches)
  assert_eq(config.index_dir, dir + "/.cache/reconcile-db")
  assert_eq(
    config.review_results_path,
    dir + "/.indexion/reconcile/reviews.json",
  )
  remove_dir_if_exists(dir)
}

///|
test "reconcile: inherited global paths rebase to global config dir" {
  let resolved = resolve_inherited_config_path(
    "/workspace/demo",
    ".cache/reconcile-db",
    None,
    "",
    Some(".cache/reconcile-db"),
    Some("/Users/demo/.config/indexion/config.toml"),
    "/workspace/demo/.indexion/cache/reconcile",
  )
  assert_eq(resolved, "/Users/demo/.config/indexion/.cache/reconcile-db")
}

///|
test "reconcile: project config paths keep project-local base" {
  let resolved = resolve_inherited_config_path(
    "/workspace/demo",
    ".cache/reconcile-db",
    Some(".cache/reconcile-db"),
    "/workspace/demo/.indexion.toml",
    Some(".global-cache/reconcile-db"),
    Some("/Users/demo/.config/indexion/config.toml"),
    "/workspace/demo/.indexion/cache/reconcile",
  )
  assert_eq(resolved, "/workspace/demo/.cache/reconcile-db")
}

///|
test "reconcile: extract_markdown_fragments keeps headings and paragraphs" {
  let input =
    #|# API
    #|
    #|`buildGraph` collects modules.
    #|
    #|## Notes
    #|The CLI prints json.
  let fragments = extract_markdown_fragments("README.md", "markdown", input)
  assert_true(fragments.length() >= 3)
  assert_eq(fragments[0].kind, "heading")
  assert_eq(fragments[1].kind, "paragraph")
  assert_true(fragments[1].content.contains("buildGraph"))
}

///|
test "reconcile: extract_toml_fragments keeps section keys" {
  let input =
    #|[project]
    #|name = "demo"
    #|description = "Build graph"
  let fragments = extract_toml_fragments("pyproject.toml", "toml", input)
  assert_true(fragments.length() >= 3)
  assert_eq(fragments[0].kind, "section")
  assert_eq(fragments[1].title, "project.name")
}

///|
async test "reconcile: build_candidates reports stale and missing docs" {
  let config = {
    ..ReconcileConfig::default(),
    target_dir: ".",
    threshold_seconds: 10,
  }
  let units : Array[CodeUnit] = [
    {
      symbol_id: "sym:buildGraph",
      name: "buildGraph",
      kind: "function",
      ns: "pkg.graph",
      module_id: "pkg.graph",
      module_path: "src/engine.mbt",
      inline_doc: None,
      code_hash: "code-1",
    },
    {
      symbol_id: "sym:noDoc",
      name: "noDoc",
      kind: "function",
      ns: "pkg.graph",
      module_id: "pkg.graph",
      module_path: "src/engine.mbt",
      inline_doc: None,
      code_hash: "code-2",
    },
  ]
  let fragments : Array[DocFragment] = [
    make_fragment(
      "docs/api.md", "markdown", "paragraph", "API", "The `buildGraph` helper renders output.",
    ),
  ]
  let result = build_candidates(units, fragments, config, load_test_registry())
  assert_true(result.candidates.length() >= 1)
  assert_true(
    result.candidates
    .iter()
    .any(fn(candidate) {
      candidate.symbol_id == "sym:noDoc" && candidate.status == "missing_doc"
    }),
  )
}

///|
async test "reconcile: build_candidates suppresses missing_doc when module docs cover the file" {
  let dir = temp_reconcile_dir(".indexion/reconcile-module-coverage-")
  @config_paths.ensure_dir_recursive(dir)
  let module_path = dir + "/config.mbt"
  let module_source =
    #|fn resolve_config() -> Unit { ignore(()) }
    #|fn parse_args() -> Unit { ignore(()) }
    #|let doc_paths = ""
    #|let doc_specs = ""
    #|let index_dir = ""
    #|let review_results_path = ""
  @fs.write_string_to_file(module_path, module_source) catch {
    _ => ()
  }
  let config = {
    ..ReconcileConfig::default(),
    target_dir: dir,
    threshold_seconds: 10,
  }
  let units : Array[CodeUnit] = [
    {
      symbol_id: "sym:resolve_config",
      name: "resolve_config",
      kind: "function",
      ns: "pkg.reconcile",
      module_id: "pkg.reconcile.config",
      module_path,
      inline_doc: None,
      code_hash: "code-1",
    },
    {
      symbol_id: "sym:parse_args",
      name: "parse_args",
      kind: "function",
      ns: "pkg.reconcile",
      module_id: "pkg.reconcile.config",
      module_path,
      inline_doc: None,
      code_hash: "code-2",
    },
  ]
  let fragments : Array[DocFragment] = [
    make_fragment(
      dir + "/README.md",
      "markdown",
      "paragraph",
      "Configuration",
      "The configuration supports doc_paths, doc_specs, index_dir, and review_results_path.",
    ),
  ]
  let result = build_candidates(units, fragments, config, load_test_registry())
  assert_eq(result.candidates.length(), 0)
  assert_eq(result.module_covered_symbols, 2)
  remove_file_if_exists(module_path)
  remove_dir_if_exists(dir)
}

///|
async test "reconcile: module coverage does not bleed across sibling cli modules" {
  let dir = temp_reconcile_dir(".indexion/reconcile-module-siblings-")
  @config_paths.ensure_dir_recursive(dir + "/reconcile")
  @config_paths.ensure_dir_recursive(dir + "/solid")
  let reconcile_path = dir + "/reconcile/cli.mbt"
  let solid_path = dir + "/solid/cli.mbt"
  let source =
    #|fn render_output() -> Unit { ignore(()) }
    #|let output = ""
    #|let format = ""
    #|let json = ""
    #|let markdown = ""
  @fs.write_string_to_file(reconcile_path, source) catch {
    _ => ()
  }
  @fs.write_string_to_file(solid_path, source) catch {
    _ => ()
  }
  let config = {
    ..ReconcileConfig::default(),
    target_dir: dir,
    threshold_seconds: 10,
  }
  let units : Array[CodeUnit] = [
    {
      symbol_id: "sym:reconcile",
      name: "render_output",
      kind: "function",
      ns: "pkg.reconcile",
      module_id: "pkg.reconcile.cli",
      module_path: reconcile_path,
      inline_doc: None,
      code_hash: "code-reconcile",
    },
    {
      symbol_id: "sym:solid",
      name: "render_output",
      kind: "function",
      ns: "pkg.solid",
      module_id: "pkg.solid.cli",
      module_path: solid_path,
      inline_doc: None,
      code_hash: "code-solid",
    },
  ]
  let fragments : Array[DocFragment] = [
    make_fragment(
      dir + "/reconcile/README.md",
      "markdown",
      "paragraph",
      "Output",
      "The reconcile command renders markdown or json output.",
    ),
  ]
  let result = build_candidates(units, fragments, config, load_test_registry())
  assert_eq(result.module_covered_symbols, 1)
  assert_eq(result.candidates.length(), 1)
  assert_eq(result.candidates[0].symbol_id, "sym:solid")
  assert_eq(result.candidates[0].status, "missing_doc")
  remove_file_if_exists(reconcile_path)
  remove_file_if_exists(solid_path)
  remove_dir_if_exists(dir + "/reconcile")
  remove_dir_if_exists(dir + "/solid")
  remove_dir_if_exists(dir)
}

///|
test "reconcile: match_fragment requires exact token for plain symbol names" {
  let generic_unit : CodeUnit = {
    symbol_id: "sym:run",
    name: "run",
    kind: "function",
    ns: "pkg.reconcile",
    module_id: "pkg.reconcile.cli",
    module_path: "src/cli.mbt",
    inline_doc: None,
    code_hash: "code-run",
  }
  let rerun_fragment = make_fragment(
    "README.md", "markdown", "paragraph", "Workflow", "Re-running reconcile reuses pending tasks.",
  )
  let default_fragment = make_fragment(
    "README.md", "markdown", "paragraph", "Configuration", "[reconcile.output] default_format = \"json\"",
  )
  let default_column_fragment = make_fragment(
    "README.md", "markdown", "paragraph", "Options", "| Option | Purpose | Default |",
  )
  let registry = load_test_registry()
  let markdown_signals = build_fragment_match_signals(
    [rerun_fragment, default_fragment, default_column_fragment],
    registry,
  )
  assert_eq(
    match_fragment(
      generic_unit,
      rerun_fragment,
      markdown_signals.get(rerun_fragment.id).unwrap(),
      true,
    ).0,
    0,
  )
  assert_eq(
    match_fragment(
      { ..generic_unit, name: "default" },
      default_fragment,
      markdown_signals.get(default_fragment.id).unwrap(),
      true,
    ).0,
    0,
  )
  assert_eq(
    match_fragment(
      { ..generic_unit, name: "default" },
      default_column_fragment,
      markdown_signals.get(default_column_fragment.id).unwrap(),
      true,
    ).0,
    0,
  )
  let structured_unit : CodeUnit = {
    ..generic_unit,
    symbol_id: "sym:parse_args",
    name: "parse_args",
  }
  let exact_fragment = make_fragment(
    "settings.toml", "toml", "entry", "reconcile.parse_args", "parse_args = true",
  )
  let toml_signals = build_fragment_match_signals([exact_fragment], registry)
  let matched = match_fragment(
    structured_unit,
    exact_fragment,
    toml_signals.get(exact_fragment.id).unwrap(),
    true,
  )
  assert_eq(matched.0, 85)
  assert_eq(matched.1, "symbol_name")
}

///|
test "reconcile: strong doc_newer match is treated as in_sync" {
  let result = classify_match_result("doc_newer", 92, "inline_symbol")
  assert_eq(result.0, "in_sync")
  assert_eq(result.1, "")
}

///|
test "reconcile: weak doc_newer match still requires review" {
  let result = classify_match_result("doc_newer", 45, "file_name")
  assert_eq(result.0, "review_both")
  assert_eq(result.1, "review_both")
}

///|
test "reconcile: extract_code_units uses KGF document_symbol_kinds when available" {
  let registry = load_test_registry()
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module("src/demo.mbt", file=Some("src/demo.mbt"))
  let _ = graph.get_or_add_symbol(
    "src/demo.mbt::value:build_graph",
    name="build_graph",
    kind="Function",
    ns="value",
    module_id="src/demo.mbt",
  )
  let _ = graph.get_or_add_symbol(
    "src/demo.mbt::value:default_format",
    name="default_format",
    kind="Variable",
    ns="value",
    module_id="src/demo.mbt",
  )
  let units = extract_code_units(graph, registry)
  assert_true(
    units
    .iter()
    .any(fn(unit) { unit.symbol_id == "src/demo.mbt::value:build_graph" }),
  )
  assert_true(
    not(
      units
      .iter()
      .any(fn(unit) { unit.symbol_id == "src/demo.mbt::value:default_format" }),
    ),
  )
}

///|
test "reconcile: extract_code_units falls back for unknown specs" {
  let registry = load_test_registry()
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(
    "src/demo.unknown",
    file=Some("src/demo.unknown"),
  )
  let _ = graph.get_or_add_symbol(
    "src/demo.unknown::value:build_graph",
    name="build_graph",
    kind="Function",
    ns="value",
    module_id="src/demo.unknown",
  )
  let units = extract_code_units(graph, registry)
  assert_true(
    units
    .iter()
    .any(fn(unit) { unit.symbol_id == "src/demo.unknown::value:build_graph" }),
  )
}

///|
test "reconcile: discovery_roots expands current directory instead of '.'" {
  let roots = discovery_roots(".")
  assert_true(roots.length() > 0)
  assert_true(not(contains_string(roots, ".")))
}

///|
test "reconcile: git query path strips target root prefix" {
  assert_eq(
    @git.query_path(
      "cmd/indexion/plan/reconcile", "cmd/indexion/plan/reconcile/cli.mbt",
    ),
    "cli.mbt",
  )
  assert_eq(
    @git.query_path(".", "cmd/indexion/plan/reconcile/cli.mbt"),
    "cmd/indexion/plan/reconcile/cli.mbt",
  )
}

///|
test "reconcile: cleanup_stale_index removes dead index.json" {
  let dir = temp_reconcile_dir(".indexion/reconcile-cleanup-")
  @config_paths.ensure_dir_recursive(dir)
  @fs.write_string_to_file(dir + "/index.json", "{}") catch {
    _ => ()
  }
  cleanup_stale_index(dir)
  assert_true(not(@fs.path_exists(dir + "/index.json")))
  remove_dir_if_exists(dir)
}

///|
fn sample_code_anchor() -> CodeAnchor {
  {
    symbol_id: "sym:buildGraph",
    name: "buildGraph",
    kind: "function",
    ns: "pkg.graph",
    module_path: "src/graph.mbt",
    inline_doc: None,
  }
}

///|
fn sample_doc_anchor() -> DocAnchor {
  {
    fragment_id: "frag:api",
    path: "docs/api.md",
    spec: "markdown",
    kind: "paragraph",
    title: "API",
    preview: "The `buildGraph` helper renders the graph.",
  }
}

///|
fn sample_timestamp(epoch_seconds : Int) -> TimestampInfo {
  { epoch_seconds: Some(epoch_seconds), source: "git", is_dirty: false }
}

///|
fn sample_candidate() -> ReconcileCandidate {
  {
    id: "cand:buildGraph",
    symbol_id: "sym:buildGraph",
    status: "stale_doc",
    time_relation: "doc_older",
    mapping_confidence: 95,
    recommended_action: "update_doc",
    mechanical_digest: "",
    code_anchor: sample_code_anchor(),
    doc_anchor: Some(sample_doc_anchor()),
    evidence: {
      matched_terms: ["buildGraph"],
      match_kind: "inline_symbol",
      reason: "Implementation appears newer than the mapped document fragment.",
      code_time: sample_timestamp(200),
      doc_time: sample_timestamp(100),
    },
    logical_review_key: None,
    logical_review_status: "pending",
    logical_review_reused: false,
    needs_logical_review: true,
  }
}

///|
fn sample_candidate_for(
  symbol_id : String,
  name : String,
  module_path : String,
  doc_path? : String = "",
) -> ReconcileCandidate {
  {
    ..sample_candidate(),
    id: "cand:" + name,
    symbol_id,
    code_anchor: { ..sample_code_anchor(), symbol_id, name, module_path },
    doc_anchor: if doc_path.length() > 0 {
      Some({ ..sample_doc_anchor(), path: doc_path })
    } else {
      None
    },
  }
}

///|
fn sample_fragment_for(
  path : String,
  preview? : String = "project docs",
) -> DocFragment {
  {
    id: "frag:" + @cas_hash.compute_hash(path).to_string(),
    path,
    spec: "markdown",
    kind: "paragraph",
    title: "Docs",
    content: preview,
    preview,
    fragment_hash: @cas_hash.compute_hash(path + ":" + preview).to_string(),
  }
}

///|
test "reconcile: build_aggregate_suggestions groups module and project candidates" {
  let dir = temp_reconcile_dir(".indexion/reconcile-aggregate-")
  let package_dir = dir + "/pkg"
  @config_paths.ensure_dir_recursive(package_dir)
  @fs.write_string_to_file(package_dir + "/package.json", "{}") catch {
    _ => ()
  }
  let module_a = package_dir + "/a.mbt"
  let module_b = package_dir + "/b.mbt"
  @fs.write_string_to_file(module_a, "fn a() -> Unit { ignore(()) }") catch {
    _ => ()
  }
  @fs.write_string_to_file(module_b, "fn b() -> Unit { ignore(()) }") catch {
    _ => ()
  }
  let groups = build_aggregate_suggestions(
    [
      sample_candidate_for(
        "sym:a1",
        "build_graph",
        module_a,
        doc_path=package_dir + "/README.md",
      ),
      sample_candidate_for(
        "sym:a2",
        "render_graph",
        module_a,
        doc_path=package_dir + "/README.md",
      ),
      sample_candidate_for(
        "sym:b1",
        "write_report",
        module_b,
        doc_path=package_dir + "/docs/api.md",
      ),
    ],
    [
      sample_candidate_for(
        "sym:a1",
        "build_graph",
        module_a,
        doc_path=package_dir + "/README.md",
      ),
      sample_candidate_for(
        "sym:a2",
        "render_graph",
        module_a,
        doc_path=package_dir + "/README.md",
      ),
      sample_candidate_for(
        "sym:b1",
        "write_report",
        module_b,
        doc_path=package_dir + "/docs/api.md",
      ),
    ],
    [
      sample_fragment_for(package_dir + "/README.md"),
      sample_fragment_for(package_dir + "/docs/api.md"),
    ],
    dir,
    ["package.json"],
  )
  assert_eq(groups.length(), 2)
  assert_true(
    groups
    .iter()
    .any(fn(group) {
      group.scope == "module" &&
      group.path == "pkg/a.mbt" &&
      group.candidate_count == 2
    }),
  )
  assert_true(
    groups
    .iter()
    .any(fn(group) {
      group.scope == "project" &&
      group.path == "pkg" &&
      group.candidate_count == 3
    }),
  )
  remove_file_if_exists(package_dir + "/package.json")
  remove_file_if_exists(module_a)
  remove_file_if_exists(module_b)
  remove_dir_if_exists(package_dir)
  remove_dir_if_exists(dir)
}

///|
test "reconcile: collapse_aggregate_only_candidates hides symbol flood when project docs exist" {
  let dir = temp_reconcile_dir(".indexion/reconcile-collapse-")
  let project_dir = dir + "/pkg"
  @config_paths.ensure_dir_recursive(project_dir)
  @fs.write_string_to_file(project_dir + "/package.json", "{}") catch {
    _ => ()
  }
  let module_a = project_dir + "/a.mbt"
  let module_b = project_dir + "/b.mbt"
  @fs.write_string_to_file(module_a, "fn a() -> Unit { ignore(()) }") catch {
    _ => ()
  }
  @fs.write_string_to_file(module_b, "fn b() -> Unit { ignore(()) }") catch {
    _ => ()
  }
  let raw_candidates : Array[ReconcileCandidate] = [
    {
      ..sample_candidate_for("sym:a1", "build_graph", module_a),
      status: "missing_doc",
      doc_anchor: None,
    },
    {
      ..sample_candidate_for("sym:a2", "render_graph", module_a),
      status: "missing_doc",
      doc_anchor: None,
    },
    {
      ..sample_candidate_for("sym:b1", "write_report", module_b),
      status: "missing_doc",
      doc_anchor: None,
    },
  ]
  let aggregate_suggestions = build_aggregate_suggestions(
    raw_candidates,
    [],
    [sample_fragment_for(project_dir + "/README.md")],
    dir,
    ["package.json"],
  )
  let collapsed = collapse_aggregate_only_candidates(
    raw_candidates,
    aggregate_suggestions,
    dir,
    ["package.json"],
  )
  assert_eq(collapsed.length(), 0)
  remove_file_if_exists(project_dir + "/package.json")
  remove_file_if_exists(module_a)
  remove_file_if_exists(module_b)
  remove_dir_if_exists(project_dir)
  remove_dir_if_exists(dir)
}

///|
test "reconcile: sync_candidates_with_index reuses pending logical review tasks" {
  let first = sync_candidates_with_index(
    [sample_candidate()],
    ReconcileManifest::empty(),
    @vcdb.VectorDB::with_dim(1),
    "queue",
    1000,
  )
  assert_eq(first.logical_reviews.length(), 1)
  assert_eq(first.logical_reviews[0].status, "pending")
  assert_true(not(first.logical_reviews[0].reused))
  assert_eq(first.reused_logical_reviews, 0)

  let second = sync_candidates_with_index(
    [sample_candidate()],
    first.manifest,
    first.db,
    "queue",
    1100,
  )
  assert_eq(second.logical_reviews.length(), 1)
  assert_true(second.logical_reviews[0].reused)
  assert_eq(second.reused_logical_reviews, 1)
  assert_eq(second.candidates[0].logical_review_status, "pending")
  assert_true(second.candidates[0].logical_review_reused)
  assert_true(second.candidates[0].needs_logical_review)

  let summary = build_summary(
    [],
    [],
    second.candidates,
    [],
    0,
    second.logical_reviews,
    second.reused_logical_reviews,
  )
  assert_eq(summary.new_logical_reviews, 0)
  assert_eq(summary.reused_logical_reviews, 1)
  assert_eq(summary.pending_logical_reviews, 1)
  assert_eq(summary.total_aggregate_suggestions, 0)
}

///|
test "reconcile: apply_review_decisions closes pending logical review" {
  let first = sync_candidates_with_index(
    [sample_candidate()],
    ReconcileManifest::empty(),
    @vcdb.VectorDB::with_dim(1),
    "queue",
    1000,
  )
  let review_key = first.logical_reviews[0].review_key
  let decisions : Array[ReviewDecisionInput] = [
    { review_key, status: "accepted", verdict: Some("document needs update") },
  ]
  let (manifest_after_review, db_after_review) = apply_review_decisions(
    first.manifest,
    first.db,
    decisions,
    1200,
  )
  let second = sync_candidates_with_index(
    [sample_candidate()],
    manifest_after_review,
    db_after_review,
    "queue",
    1300,
  )
  assert_eq(second.logical_reviews.length(), 0)
  assert_eq(second.reused_logical_reviews, 0)
  assert_eq(second.candidates[0].logical_review_key, Some(review_key))
  assert_eq(second.candidates[0].logical_review_status, "accepted")
  assert_true(second.candidates[0].logical_review_reused)
  assert_true(not(second.candidates[0].needs_logical_review))
}
