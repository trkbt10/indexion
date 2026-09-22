///|
/// Snapshot for fixtures/project/npm-circular.
///
/// Exercises the KGF + enrichment pipeline against a representative
/// project layout in this ecosystem; the snapshot locks in every
/// moduleDependsOn edge and verifies the structural-completeness
/// invariant on the serialized graph.
test "snapshot: fixtures/project/npm-circular" {
  let graph = @cross-package-resolution.analyze_fixture(
    "fixtures/project/npm-circular",
  )
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/npm-circular.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
