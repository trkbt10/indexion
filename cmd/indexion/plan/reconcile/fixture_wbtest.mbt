///|
fn get_fixtures_dir() -> String {
  let paths = [
    "fixtures", "../fixtures", "../../fixtures", "../../../fixtures", "../../../../fixtures",
    "../../../../../fixtures",
  ]
  for path in paths {
    try {
      if @fs.is_dir(path) {
        return path
      }
    } catch {
      _ => continue
    }
  }
  "fixtures"
}

///|
test "reconcile: fixture typescript project validates cross-package drift detection" {
  let fixture_root = get_fixtures_dir() + "/project/typescript-reconcile"
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
    fixture_root, "kgfs",
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
