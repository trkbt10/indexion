///|
/// Fixture-based tests for filter module.
/// Uses actual filesystem directories to test filtering behavior.

///|
/// Base path for fixtures (relative to project root).
const FIXTURES_BASE : String = "src/filter/fixtures"

///|
/// Test gitignore basic patterns with actual files.
test "fixture: gitignore/basic excludes *.log and temp/" {
  let fixture_path = FIXTURES_BASE + "/gitignore/basic"
  let config = FilterConfig::from_project_root(fixture_path)
  // *.log should be excluded
  let log_result = config.should_include(fixture_path + "/remove.log", false)
  assert_true(log_result is FilterResult::Exclude(_))
  // temp/ directory should be excluded
  assert_true(config.should_skip_dir("temp"))
  // keep.txt should be included
  let keep_result = config.should_include(fixture_path + "/keep.txt", false)
  assert_eq(keep_result, FilterResult::Include)
  // src/main.mbt should be included
  let src_result = config.should_include(fixture_path + "/src/main.mbt", false)
  assert_eq(src_result, FilterResult::Include)
}

///|
/// Test gitignore negation pattern (!pattern).
test "fixture: gitignore/negation respects ! prefix" {
  let fixture_path = FIXTURES_BASE + "/gitignore/negation"
  let config = FilterConfig::from_project_root(fixture_path)
  // debug.log should be excluded (matches *.log)
  let debug_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(debug_result is FilterResult::Exclude(_))
  // important.log should be included (negated by !important.log)
  let important_result = config.should_include(
    fixture_path + "/important.log",
    false,
  )
  assert_eq(important_result, FilterResult::Include)
}

///|
/// Test directory-only patterns (trailing /).
test "fixture: gitignore/directory-only excludes dirs not files" {
  let fixture_path = FIXTURES_BASE + "/gitignore/directory-only"
  let config = FilterConfig::from_project_root(fixture_path)
  // build/ directory should be skipped
  assert_true(config.should_skip_dir("build"))
  // dist/ directory should be skipped
  assert_true(config.should_skip_dir("dist"))
  // src/ directory should NOT be skipped
  assert_false(config.should_skip_dir("src"))
  // build.txt (file, not directory) should be included
  let file_result = config.should_include(fixture_path + "/build.txt", false)
  assert_eq(file_result, FilterResult::Include)
}

///|
/// Test indexionignore basic patterns.
test "fixture: indexionignore/basic excludes patterns" {
  let fixture_path = FIXTURES_BASE + "/indexionignore/basic"
  let config = FilterConfig::from_project_root(fixture_path)
  // *.generated.mbt should be excluded
  let gen_result = config.should_include(
    fixture_path + "/types.generated.mbt",
    false,
  )
  assert_true(gen_result is FilterResult::Exclude(_))
  // _internal/ should be skipped
  assert_true(config.should_skip_dir("_internal"))
  // main.mbt should be included
  let main_result = config.should_include(fixture_path + "/main.mbt", false)
  assert_eq(main_result, FilterResult::Include)
}

///|
/// Test indexionignore overrides gitignore with negation.
test "fixture: indexionignore/negation overrides gitignore" {
  let fixture_path = FIXTURES_BASE + "/indexionignore/negation"
  let config = FilterConfig::from_project_root(fixture_path)
  // debug.log should be excluded (by .gitignore *.log)
  let debug_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(debug_result is FilterResult::Exclude(_))
  // important.log should be included (negated by .indexionignore)
  let important_result = config.should_include(
    fixture_path + "/important.log",
    false,
  )
  assert_eq(important_result, FilterResult::Include)
}

///|
/// Test nested gitignore files are loaded during traversal.
test "fixture: nested/basic loads gitignore per directory" {
  let fixture_path = FIXTURES_BASE + "/nested/basic"
  let root_config = FilterConfig::from_project_root(fixture_path)
  // Root level: *.log excluded
  let root_log = root_config.should_include(fixture_path + "/root.log", false)
  assert_true(root_log is FilterResult::Exclude(_))
  // Subdir: load nested gitignore
  let subdir_config = root_config.with_gitignore_from_dir(
    fixture_path + "/subdir",
  )
  // Subdir: *.log still excluded (inherited)
  let sub_log = subdir_config.should_include(
    fixture_path + "/subdir/sub.log",
    false,
  )
  assert_true(sub_log is FilterResult::Exclude(_))
  // Subdir: *.tmp excluded (from subdir/.gitignore)
  let sub_tmp = subdir_config.should_include(
    fixture_path + "/subdir/sub.tmp",
    false,
  )
  assert_true(sub_tmp is FilterResult::Exclude(_))
  // Subdir: keep.txt included
  let sub_keep = subdir_config.should_include(
    fixture_path + "/subdir/keep.txt",
    false,
  )
  assert_eq(sub_keep, FilterResult::Include)
}

///|
/// Test CLI --exclude overrides all ignore files.
test "fixture: priority/basic CLI exclude overrides gitignore" {
  let fixture_path = FIXTURES_BASE + "/priority/basic"
  let config = FilterConfig::from_project_root(fixture_path).with_excludes([
    "*.txt",
  ]) // CLI exclude
  // debug.log excluded by .gitignore
  let log_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(log_result is FilterResult::Exclude(_))
  // keep.txt now excluded by CLI --exclude (overrides gitignore include)
  let txt_result = config.should_include(fixture_path + "/keep.txt", false)
  assert_true(txt_result is FilterResult::Exclude(_))
}

///|
/// Test CLI --include has highest priority.
test "fixture: priority/basic CLI include overrides all" {
  let fixture_path = FIXTURES_BASE + "/priority/basic"
  let config = FilterConfig::from_project_root(fixture_path).with_includes([
    "*.log",
  ]) // CLI include forces inclusion
  // debug.log should be INCLUDED because CLI --include has highest priority
  let log_result = config.should_include(fixture_path + "/debug.log", false)
  assert_eq(log_result, FilterResult::Include)
}

///|
/// Test KGF ignore patterns work with filter.
test "fixture: kgf patterns exclude build directories" {
  let config = FilterConfig::new().with_kgf_ignore(
    ["_build/", "target/", "node_modules/"],
    "moonbit",
  )
  // Build directories should be skipped
  assert_true(config.should_skip_dir("_build"))
  assert_true(config.should_skip_dir("target"))
  assert_true(config.should_skip_dir("node_modules"))
  // Normal directories should NOT be skipped
  assert_false(config.should_skip_dir("src"))
  assert_false(config.should_skip_dir("lib"))
}

///|
/// Test default excludes (hidden dirs, VCS).
test "fixture: default excludes hidden and VCS" {
  let config = FilterConfig::new()
  // Hidden directories should be skipped
  assert_true(config.should_skip_dir(".git"))
  assert_true(config.should_skip_dir(".svn"))
  assert_true(config.should_skip_dir(".hg"))
  assert_true(config.should_skip_dir(".vscode"))
  // Normal directories should NOT be skipped
  assert_false(config.should_skip_dir("src"))
}
