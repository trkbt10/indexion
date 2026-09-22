///|
/// Snapshot for fixtures/project/gradle-multimodule.
///
/// A multi-project Gradle build (`settings.gradle.kts` with `include(":core")`
/// and `include(":app")`, one `build.gradle.kts` per module). It pins the
/// anchoring rule of the `source_roots` resolver step: a module's source roots
/// are found from the NEAREST build manifest, not the repository's. So
/// `core/.../Money.kt` reaches `core/src/main/java/.../CurrencyCodes.kt` --
/// its own module's second source root -- while `app/.../Main.kt` importing
/// `com.example.core.*` finds nothing under `app/`'s roots and keeps the
/// `maven:` fallback, which is what a Gradle `project(":core")` dependency
/// looks like to a resolver that does not read project dependencies.
test "snapshot: fixtures/project/gradle-multimodule" {
  let graph = @cross-package-resolution.analyze_fixture(
    "fixtures/project/gradle-multimodule",
  )
  let actual = @cross-package-resolution.snapshot_of(graph)
  let snapshot_path = "tests/integration/cross-package-resolution/gradle-multimodule.snapshot.json"
  @cross-package-resolution.assert_snapshot_matches(snapshot_path, actual)
  assert_eq(@cross-package-resolution.count_unresolved_structural(graph), 0)
}
