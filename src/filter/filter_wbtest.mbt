///|
test "FilterConfig: default excludes VCS only" {
  // Default excludes only contain VCS directories
  let config = FilterConfig::new()
  // VCS should be excluded
  let git_result = config.should_include(".git/config", false)
  assert_true(git_result is FilterResult::Exclude(_))
  // Build dirs are NOT excluded by default (they come from KGF specs)
  let build_result = config.should_include("_build/output.js", false)
  assert_eq(build_result, FilterResult::Include)
}

///|
test "FilterConfig: KGF ignore patterns" {
  // Test that KGF ignore patterns work
  let config = FilterConfig::new().with_kgf_ignore(
    ["_build/", "node_modules/"],
    "moonbit",
  )
  // Now _build should be excluded
  let result = config.should_include("_build/output.js", false)
  assert_true(result is FilterResult::Exclude(_))
}

///|
test "FilterConfig: includes normal files" {
  let config = FilterConfig::new()
  let result = config.should_include("src/main.mbt", false)
  assert_eq(result, FilterResult::Include)
}

///|
test "FilterConfig: user exclude overrides" {
  let config = FilterConfig::new().with_excludes(["*.log"])
  let result = config.should_include("debug.log", false)
  assert_true(result is FilterResult::Exclude(_))
}

///|
test "FilterConfig: user include allows" {
  let config = FilterConfig::new().with_includes(["*.mbt"])
  let result = config.should_include("src/main.mbt", false)
  assert_eq(result, FilterResult::Include)
}

///|
test "FilterConfig: user include excludes non-matching" {
  let config = FilterConfig::new().with_includes(["*.mbt"])
  // Non-matching files should be excluded when --include is specified
  let result = config.should_include("src/main.txt", false)
  assert_true(result is FilterResult::Exclude(_))
}

///|
test "FilterConfig: user include excludes moon.pkg" {
  let config = FilterConfig::new().with_includes(["*.mbt"])
  // moon.pkg should be excluded when --include=*.mbt
  let result = config.should_include("src/moon.pkg", false)
  assert_true(result is FilterResult::Exclude(_))
}

///|
test "FilterConfig: include and exclude combined" {
  let config = FilterConfig::new()
    .with_includes(["*.mbt"])
    .with_excludes(["*_wbtest.mbt"])
  // Matching include but also matching exclude -> Exclude wins
  let test_result = config.should_include("src/foo_wbtest.mbt", false)
  assert_true(test_result is FilterResult::Exclude(_))
  // Matching include, not matching exclude -> Include
  let main_result = config.should_include("src/main.mbt", false)
  assert_eq(main_result, FilterResult::Include)
}

///|
test "FilterConfig: no include means include all" {
  let config = FilterConfig::new()
  // Without --include, all files should be included (unless excluded)
  let txt_result = config.should_include("src/readme.txt", false)
  assert_eq(txt_result, FilterResult::Include)
  let mbt_result = config.should_include("src/main.mbt", false)
  assert_eq(mbt_result, FilterResult::Include)
}

///|
test "should_skip_dir: skips hidden" {
  let config = FilterConfig::new()
  assert_true(config.should_skip_dir(".git"))
  assert_true(config.should_skip_dir(".vscode"))
}

///|
test "should_skip_dir: skips VCS" {
  let config = FilterConfig::new()
  assert_true(config.should_skip_dir(".git"))
  assert_true(config.should_skip_dir(".svn"))
  assert_true(config.should_skip_dir(".hg"))
}

///|
test "should_skip_dir: with KGF patterns" {
  let config = FilterConfig::new().with_kgf_ignore(
    ["node_modules/", "_build/", "target/"],
    "test",
  )
  assert_true(config.should_skip_dir("node_modules"))
  assert_true(config.should_skip_dir("_build"))
  assert_true(config.should_skip_dir("target"))
}

///|
test "should_skip_dir: allows normal dirs" {
  let config = FilterConfig::new()
  assert_false(config.should_skip_dir("src"))
  assert_false(config.should_skip_dir("lib"))
  assert_false(config.should_skip_dir("cmd"))
}
