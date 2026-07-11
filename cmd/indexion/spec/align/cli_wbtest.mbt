///|
fn fixture_spec_dir() -> String {
  "fixtures/project/spec-align-basic/spec"
}

///|
fn fixture_impl_dir() -> String {
  "fixtures/project/spec-align-basic/moonbit"
}

///|
let shared_test_registry : @registry.KGFRegistry = @kgf_features.load_registry_or_empty(
  specs_dir="kgfs",
  target_dir=".",
)

///|
fn task_render_config(agent : String) -> @spec_align.SpecAlignConfig {
  {
    ..@spec_align.SpecAlignConfig::default(),
    subcommand: "suggest",
    spec_path: fixture_spec_dir(),
    impl_path: fixture_impl_dir(),
    specs_dir: "kgfs",
    format: "tasks",
    agent,
    threshold: 0.35,
  }
}

///|
async test "spec align cli: claude task format is structured" {
  let rendered = match
    run_to_string_with_registry(
      task_render_config("claude"),
      shared_test_registry,
    ) {
    Some(value) => value
    None => fail("expected rendered task output")
  }
  assert_true(rendered.contains("# Claude Tasks"))
  assert_true(rendered.contains("## Task 1:"))
}

///|
async test "spec align cli: copilot task format is checklist based" {
  let rendered = match
    run_to_string_with_registry(
      task_render_config("copilot"),
      shared_test_registry,
    ) {
    Some(value) => value
    None => fail("expected rendered task output")
  }
  assert_true(rendered.contains("# Copilot Tasks"))
  assert_true(rendered.contains("- [ ]"))
}

///|
async test "spec align cli: watch mode emits a first diff snapshot and exits at limit" {
  let output = "/tmp/indexion-spec-align-watch-" +
    @env.now().to_string() +
    ".md"
  let matches = try! command().parse(
    argv=[
        "watch",
        "--mode=diff",
        "--format=markdown",
        "--limit=1",
        "--output=" + output,
        fixture_spec_dir(),
        fixture_impl_dir(),
      ][:],
    env={},
  )
  run_matches(matches)
  let rendered = @fs.read_file_to_string(output) catch {
    _ => fail("expected watch output file")
  }
  assert_true(rendered.contains("# Spec Align Diff Report"))
}
