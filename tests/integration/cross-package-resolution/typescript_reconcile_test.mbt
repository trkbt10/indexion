///|
/// Snapshot for fixtures/project/typescript-reconcile.
///
/// Exercises the KGF + enrichment pipeline against a representative
/// project layout in this ecosystem; the snapshot locks in every
/// moduleDependsOn edge and verifies the structural-completeness
/// invariant on the serialized graph.
test "snapshot: fixtures/project/typescript-reconcile" {
  let graph = @cross-package-resolution.analyze_fixture(
    "fixtures/project/typescript-reconcile",
  )
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/typescript-reconcile.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
