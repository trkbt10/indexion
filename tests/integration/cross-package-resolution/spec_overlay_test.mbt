///|
/// Snapshot for fixtures/project/spec-overlay.
///
/// Pins spec inheritance and project-local overlays end to end. The fixture
/// carries `.indexion/kgfs/python-strict.kgf`, a four-line spec whose whole
/// content is `extends: python` plus a `sources:` line claiming `.pyx`:
///
///   * the OVERLAY must be discovered from the analysed directory rather than
///     from the repository the test runs in — `.indexion` is itself a project
///     root marker, so the walk stops at the fixture;
///   * `extends:` must then pull the lexer, grammar, semantics and resolver
///     from the base `python` spec, since the overlay declares none of them;
///   * `sources:` is the one section inheritance never copies, so `.pyx` is
///     claimed by the overlay alone.
///
/// If any of those fails the fixture's source is simply not a supported file
/// and the graph loses every symbol in it — which is what the snapshot's
/// symbol count and declares edges detect.
test "snapshot: fixtures/project/spec-overlay" {
  let graph = @cross-package-resolution.analyze_fixture(
    "fixtures/project/spec-overlay",
  )
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/spec-overlay.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
