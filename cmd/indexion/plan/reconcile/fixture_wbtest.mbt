///|
async fn fixture_collect_document_fragments(
  discovered_files : Array[@pipeline.SupportedFile],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
) -> (Array[DocFragment], Array[FileState], Array[String]) {
  @reconcile_plan.collect_document_fragments(discovered_files, config, registry)
}

///|
async fn fixture_build_candidates(
  units : Array[CodeUnit],
  fragments : Array[DocFragment],
  config : ReconcileConfig,
  registry : @kgf_registry.KGFRegistry,
) -> @reconcile_plan.CandidateBuildResult {
  @reconcile_plan.build_candidates(units, fragments, config, registry)
}

///|
fn build_code_graph(
  target_dir : String,
  specs_dir : String,
) -> (
  @kgf_registry.KGFRegistry,
  Array[String],
  Array[@pipeline.SupportedFile],
  @graph.CodeGraph,
) {
  let registry = @kgf_features.load_registry_or_empty(specs_dir~, target_dir~)
  let kgf_ignore = registry.collect_ignore_patterns()
  // root_dir is intentionally empty: fixture directories live inside
  // the project tree, so hoisting the project's .indexionignore
  // (which excludes fixtures/) would filter out the test target itself.
  let discover_opts = @pipeline.DiscoverOptions::new(kgf_ignore~)
  let discovered_paths = @pipeline.discover_files(
    @reconcile_plan.discovery_roots(target_dir),
    discover_opts,
  )
  let discovered_files = @pipeline.load_supported_file_info(
    discovered_paths, registry,
  )
  let files = discovered_files.map(fn(file) { (file.path, file.content) })
  let specs = registry.to_specs_map()
  let config = @doc_build.DocConfig::new(files, specs, root_path=target_dir)
  let (_output, graph) = @doc_build.build_with_graph(config)
  (registry, discovered_paths, discovered_files, graph)
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
  let kgfs_dir = @kgf_fixtures.get_kgfs_dir()
  let (registry, discovered_paths, discovered_files, graph) = build_code_graph(
    fixture_root, kgfs_dir,
  )
  // Preconditions: verify registry loaded and files discovered
  assert_true(
    registry.spec_count() > 0,
    msg="registry is empty — kgfs dir '" + kgfs_dir + "' may not exist",
  )
  assert_true(
    discovered_paths.length() > 0,
    msg="no files discovered in '" + fixture_root + "'",
  )
  let units = extract_code_units(graph, registry)
  assert_true(
    units.length() > 0,
    msg="no code units extracted (discovered " +
      discovered_paths.length().to_string() +
      " files, " +
      registry.spec_count().to_string() +
      " specs)",
  )
  assert_true(units.iter().any(fn(unit) { unit.name == "buildGraph" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "ReconcileConfig" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "ReportRenderer" }))
  assert_true(units.iter().any(fn(unit) { unit.name == "normalizePath" }))
  assert_false(units.iter().any(fn(unit) { unit.name == "defaultFormat" }))

  let (fragments, _states, used_specs) = fixture_collect_document_fragments(
    discovered_files, config, registry,
  )
  assert_eq(used_specs, ["markdown"])
  assert_eq(fragments.length(), 3)

  let result = fixture_build_candidates(units, fragments, config, registry)
  assert_eq(result.candidates.length(), 1)
  assert_eq(result.candidates[0].code_anchor.name, "normalizePath")
  assert_eq(result.candidates[0].status, "missing_doc")
  assert_eq(result.module_covered_symbols, 0)
}
