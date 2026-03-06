///|
/// Test that default config skips VCS and hidden directories.
test "discover_files: default skips VCS and hidden" {
  let filter = @filter.FilterConfig::new()
  // VCS directories always skipped
  assert_true(filter.should_skip_dir(".git"))
  assert_true(filter.should_skip_dir(".svn"))
  assert_true(filter.should_skip_dir(".hg"))
  // Hidden directories skipped
  assert_true(filter.should_skip_dir(".vscode"))
  // Normal directories allowed
  assert_false(filter.should_skip_dir("src"))
  assert_false(filter.should_skip_dir("lib"))
  // Build dirs NOT skipped by default (come from KGF specs)
  assert_false(filter.should_skip_dir("_build"))
  assert_false(filter.should_skip_dir("target"))
  assert_false(filter.should_skip_dir("node_modules"))
}

///|
/// Test that KGF ignore patterns skip build directories.
test "discover_files: KGF patterns skip build dirs" {
  let filter = @filter.FilterConfig::new().with_kgf_ignore(
    ["_build/", "target/", "node_modules/"],
    "test",
  )
  assert_true(filter.should_skip_dir("_build"))
  assert_true(filter.should_skip_dir("target"))
  assert_true(filter.should_skip_dir("node_modules"))
  // Normal dirs still allowed
  assert_false(filter.should_skip_dir("src"))
}
