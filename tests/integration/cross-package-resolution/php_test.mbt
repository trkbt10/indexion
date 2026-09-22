///|
/// Snapshot for fixtures/project/php.
///
/// Exercises the KGF + enrichment pipeline against a representative
/// project layout in this ecosystem; the snapshot locks in every
/// moduleDependsOn edge and verifies the structural-completeness
/// invariant on the serialized graph.
///
/// The composer.json carries a map with more than one entry, which is what
/// pins the `namespace_map` step's precedence rule:
///
///   * `App\` maps to `src/`, and the longer `App\Billing\` maps OUTSIDE it,
///     to `modules/billing/src/`. `App\Billing\Invoice` matches both keys, so
///     resolving it to the billing module rather than to `src/Billing/` is
///     the observable proof that the longest key wins. A shortest-match or
///     first-match rule would send it to a path that holds no file.
///   * `autoload.psr-0` declares the older spelling alongside psr-4, so both
///     map shapes are read from one manifest.
test "snapshot: fixtures/project/php" {
  let graph = @cross-package-resolution.analyze_fixture("fixtures/project/php")
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/php.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
