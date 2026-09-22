///|
/// Cross-package resolution snapshot for the npm fixture
/// (fixtures/project/npm).
///
/// Locks in:
///   * every `moduleDependsOn` edge produced for a TS/JS package,
///   * the set of discovered modules (canonicalization inputs + outputs),
///   * the structural-completeness invariant (no dangling endpoints).
test "snapshot: fixtures/project/npm" {
  let graph = @cross-package-resolution.analyze_fixture("fixtures/project/npm")
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/npm.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  // Redundant but explicit: the structural invariant is part of the contract
  // we want future refactors to preserve.
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
