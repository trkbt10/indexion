///|
fn build_code_graph(
  target_dir : String,
  specs_dir : String,
) -> (@registry.KGFRegistry, Array[String], @graph.CodeGraph) {
  let registry = @kgf_features.load_registry_or_empty(specs_dir~, target_dir~)
  let kgf_ignore = registry.collect_ignore_patterns()
  let discover_opts = @pipeline.DiscoverOptions::new(
    kgf_ignore~,
    root_dir=target_dir,
  )
  let discovered_paths = @pipeline.discover_files(
    discovery_roots(target_dir),
    discover_opts,
  )
  let files = @pipeline.collect_supported_files(discovered_paths, registry)
  let specs = registry.to_specs_map()
  let config = @doc_build.DocConfig::new(files, specs, root_path=target_dir)
  let (_output, graph) = @doc_build.build_with_graph(config)
  (registry, discovered_paths, graph)
}

///|
async test "reconcile: fixture typescript project validates cross-package drift detection" {
  let fixture_root = @kgf_fixtures.get_fixtures_dir() +
    "/project/typescript-reconcile"
  let config = {
    ..ReconcileConfig::default(),
    target_dir: fixture_root,
    documents: @config_paths.resolve_reconcile_document_scope(
      "custom",
      doc_paths=["docs/**/*.md"],
      doc_specs=["markdown"],
    ),
    git_preferred: false,
    mtime_fallback: false,
    logical_review_mode: "off",
  }
  let (registry, discovered_paths, graph) = build_code_graph(
    fixture_root,
    @kgf_fixtures.get_kgfs_dir(),
  )
  let units = extract_code_units(graph, registry)
  assert_true(units.iter().any(fn(unit) { unit.name == "buildGraph" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "ReconcileConfig" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "ReportRenderer" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "normalizePath" }))
  assert_false(units.iter().any(fn(unit) { unit.name == "defaultFormat" }))

  let (fragments, _states, used_specs) = collect_document_fragments(
    discovered_paths, config, registry,
  )
  assert_eq(used_specs, ["markdown"])
  assert_eq(fragments.length(), 3)

  let result = build_candidates(units, fragments, config, registry)
  assert_eq(result.candidates.length(), 1)
  assert_eq(result.candidates[0].code_anchor.name, "normalizePath")
  assert_eq(result.candidates[0].status, "missing_doc")
  assert_eq(result.module_covered_symbols, 0)
}
