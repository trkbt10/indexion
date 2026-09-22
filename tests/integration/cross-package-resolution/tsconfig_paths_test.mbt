///|
/// Snapshot for fixtures/project/tsconfig-paths.
///
/// Pins the resolver's `namespace_map` step against a TypeScript project
/// that declares its aliases the way real projects do — in tsconfig's
/// `compilerOptions.paths`, stated relative to `baseUrl` — rather than
/// relying on the spec's static `@/` convention:
///
///   * `@app/*` and `@domain/*`, the wildcard alias shape;
///   * `shared/*`, a plain prefix with no sigil, which must not be mistaken
///     for a bare npm package;
///   * a nested `scripts/` sub-project whose own jsconfig.json declares
///     `~/*`, which proves the map is read from the NEAREST manifest above
///     the importing file rather than from the project root.
///
/// Every one of those must land on a file in the fixture, so the snapshot's
/// `moduleDependsOn` targets are all internal paths and the structural
/// invariant holds with zero unresolved edges.
test "snapshot: fixtures/project/tsconfig-paths" {
  let graph = @cross-package-resolution.analyze_fixture(
    "fixtures/project/tsconfig-paths",
  )
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/tsconfig-paths.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
