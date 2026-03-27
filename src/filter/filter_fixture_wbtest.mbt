///|
/// Fixture-based tests for filter module.
/// Uses actual filesystem directories to test filtering behavior.

///|
/// Base path for fixtures (relative to project root).
const FIXTURES_BASE : String = "fixtures/filter"

///|
/// Build a FilterConfig from a fixture directory by directly loading
/// .gitignore and .indexionignore from that directory (no hoisting).
fn filter_from_fixture(fixture_path : String) -> FilterConfig {
  let git_patterns = @ignorefile.load_from_dir(
    fixture_path,
    @vcs_git.GITIGNORE_FILENAME,
  )
  let ixn_patterns = @ignorefile.load_from_dir(
    fixture_path,
    @config.INDEXIONIGNORE_FILENAME,
  )
  let config = FilterConfig::new()
  let config = config.with_gitignore_patterns(git_patterns)
  config.with_indexionignore_patterns(ixn_patterns)
}

///|
test "fixture: gitignore/basic excludes *.log and temp/" {
  let fixture_path = FIXTURES_BASE + "/gitignore/basic"
  let config = filter_from_fixture(fixture_path)
  let log_result = config.should_include(fixture_path + "/remove.log", false)
  assert_true(log_result is FilterResult::Exclude(_))
  assert_true(config.should_skip_dir("temp"))
  let keep_result = config.should_include(fixture_path + "/keep.txt", false)
  assert_eq(keep_result, FilterResult::Include)
  let src_result = config.should_include(fixture_path + "/src/main.mbt", false)
  assert_eq(src_result, FilterResult::Include)
}

///|
test "fixture: gitignore/negation respects ! prefix" {
  let fixture_path = FIXTURES_BASE + "/gitignore/negation"
  let config = filter_from_fixture(fixture_path)
  let debug_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(debug_result is FilterResult::Exclude(_))
  let important_result = config.should_include(
    fixture_path + "/important.log",
    false,
  )
  assert_eq(important_result, FilterResult::Include)
}

///|
test "fixture: gitignore/directory-only excludes dirs not files" {
  let fixture_path = FIXTURES_BASE + "/gitignore/directory-only"
  let config = filter_from_fixture(fixture_path)
  assert_true(config.should_skip_dir("build"))
  assert_true(config.should_skip_dir("dist"))
  assert_false(config.should_skip_dir("src"))
  let file_result = config.should_include(fixture_path + "/build.txt", false)
  assert_eq(file_result, FilterResult::Include)
}

///|
test "fixture: indexionignore/basic excludes patterns" {
  let fixture_path = FIXTURES_BASE + "/indexionignore/basic"
  let config = filter_from_fixture(fixture_path)
  let gen_result = config.should_include(
    fixture_path + "/types.generated.mbt",
    false,
  )
  assert_true(gen_result is FilterResult::Exclude(_))
  assert_true(config.should_skip_dir("_internal"))
  let main_result = config.should_include(fixture_path + "/main.mbt", false)
  assert_eq(main_result, FilterResult::Include)
}

///|
test "fixture: indexionignore/negation overrides gitignore" {
  let fixture_path = FIXTURES_BASE + "/indexionignore/negation"
  let config = filter_from_fixture(fixture_path)
  let debug_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(debug_result is FilterResult::Exclude(_))
  let important_result = config.should_include(
    fixture_path + "/important.log",
    false,
  )
  assert_eq(important_result, FilterResult::Include)
}

///|
test "fixture: nested/basic loads gitignore per directory" {
  let fixture_path = FIXTURES_BASE + "/nested/basic"
  let root_config = filter_from_fixture(fixture_path)
  let root_log = root_config.should_include(fixture_path + "/root.log", false)
  assert_true(root_log is FilterResult::Exclude(_))
  let subdir_config = root_config.with_gitignore_from_dir(
    fixture_path + "/subdir",
    @vcs_git.GITIGNORE_FILENAME,
  )
  let sub_log = subdir_config.should_include(
    fixture_path + "/subdir/sub.log",
    false,
  )
  assert_true(sub_log is FilterResult::Exclude(_))
  let sub_tmp = subdir_config.should_include(
    fixture_path + "/subdir/sub.tmp",
    false,
  )
  assert_true(sub_tmp is FilterResult::Exclude(_))
  let sub_keep = subdir_config.should_include(
    fixture_path + "/subdir/keep.txt",
    false,
  )
  assert_eq(sub_keep, FilterResult::Include)
}

///|
test "fixture: priority/basic CLI exclude overrides gitignore" {
  let fixture_path = FIXTURES_BASE + "/priority/basic"
  let config = filter_from_fixture(fixture_path).with_excludes(["*.txt"])
  let log_result = config.should_include(fixture_path + "/debug.log", false)
  assert_true(log_result is FilterResult::Exclude(_))
  let txt_result = config.should_include(fixture_path + "/keep.txt", false)
  assert_true(txt_result is FilterResult::Exclude(_))
}

///|
test "fixture: priority/basic CLI include overrides all" {
  let fixture_path = FIXTURES_BASE + "/priority/basic"
  let config = filter_from_fixture(fixture_path).with_includes(["*.log"])
  let log_result = config.should_include(fixture_path + "/debug.log", false)
  assert_eq(log_result, FilterResult::Include)
}

///|
test "fixture: kgf patterns exclude build directories" {
  let config = FilterConfig::new().with_kgf_ignore(
    ["_build/", "target/", "node_modules/"],
    "moonbit",
  )
  assert_true(config.should_skip_dir("_build"))
  assert_true(config.should_skip_dir("target"))
  assert_true(config.should_skip_dir("node_modules"))
  assert_false(config.should_skip_dir("src"))
  assert_false(config.should_skip_dir("lib"))
}

///|
test "fixture: default excludes hidden and VCS" {
  let config = FilterConfig::new()
  assert_true(config.should_skip_dir(".git"))
  assert_true(config.should_skip_dir(".svn"))
  assert_true(config.should_skip_dir(".hg"))
  assert_true(config.should_skip_dir(".vscode"))
  assert_false(config.should_skip_dir("src"))
}
