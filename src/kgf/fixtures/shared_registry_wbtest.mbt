///|
/// KGF fixture tests only read registered specs, so load each registry once
/// per white-box test process instead of reparsing every KGF file per case.
let shared_fixture_registry : @registry.KGFRegistry = @registry.KGFRegistry::load_from_dir(
  get_kgfs_dir(),
)

///|
fn get_fixture_registry() -> @registry.KGFRegistry {
  shared_fixture_registry
}

///|
/// Story fixtures intentionally use the narrower registry to preserve the
/// original test scope and extension-resolution behavior.
let shared_story_fixture_registry : @registry.KGFRegistry = @registry.KGFRegistry::load_from_dir(
  get_kgfs_dir() + "/story",
)

///|
fn get_story_fixture_registry() -> @registry.KGFRegistry {
  shared_story_fixture_registry
}
