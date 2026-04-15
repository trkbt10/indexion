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

///|
test "matches_pattern: doublestar matches direct and nested descendants" {
  assert_true(matches_pattern("docs/api.md", "docs/**/*.md"))
  assert_true(matches_pattern("docs/reference/api.md", "docs/**/*.md"))
  assert_false(matches_pattern("README.md", "docs/**/*.md"))
}

// ─── Integration tests: discover_files respects ignore files ────────

///|
fn make_test_dir(label : String) -> String {
  let dir = "/tmp/indexion-discover/" + label + "-" + @env.now().to_string()
  @config.ensure_dir_recursive(dir)
  dir
}

///|
fn write_test_file(path : String, content : String) -> Unit {
  // Ensure parent directory exists
  let chars = path.to_array()
  let mut last_sep = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last_sep = i
    }
  }
  if last_sep > 0 {
    let parent = String::from_array(chars[:last_sep])
    @config.ensure_dir_recursive(parent)
  }
  @fs.write_string_to_file(path, content) catch {
    _ => panic()
  }
}

///|
fn paths_contain(paths : Array[String], suffix : String) -> Bool {
  for p in paths {
    if p.has_suffix(suffix) {
      return true
    }
  }
  false
}

///|
test "discover_files: respects .indexionignore" {
  let root = make_test_dir("indexionignore")
  // Create files
  write_test_file(root + "/src/main.mbt", "fn main() {}")
  write_test_file(root + "/src/lib.mbt", "fn lib() {}")
  write_test_file(root + "/_build/out.mbt", "fn out() {}")
  write_test_file(root + "/node_modules/dep.mbt", "fn dep() {}")
  write_test_file(root + "/fixtures/big.mbt", "fn big() {}")
  // Create .indexionignore
  write_test_file(
    root + "/.indexionignore",
    "_build/\nnode_modules/\nfixtures/\n",
  )
  // Discover with root_dir set
  let opts = DiscoverOptions::new(root_dir=root)
  let paths = discover_files([root], opts)
  // src/ files should be included
  assert_true(paths_contain(paths, "/src/main.mbt"))
  assert_true(paths_contain(paths, "/src/lib.mbt"))
  // Ignored directories should be excluded
  assert_false(paths_contain(paths, "/_build/out.mbt"))
  assert_false(paths_contain(paths, "/node_modules/dep.mbt"))
  assert_false(paths_contain(paths, "/fixtures/big.mbt"))
}

///|
test "discover_files: respects .gitignore" {
  let root = make_test_dir("gitignore")
  write_test_file(root + "/src/app.mbt", "fn app() {}")
  write_test_file(root + "/dist/bundle.js", "var x;")
  write_test_file(root + "/coverage/report.json", "{}")
  // Create .gitignore
  write_test_file(root + "/.gitignore", "dist/\ncoverage/\n")
  let opts = DiscoverOptions::new(root_dir=root)
  let paths = discover_files([root], opts)
  assert_true(paths_contain(paths, "/src/app.mbt"))
  assert_false(paths_contain(paths, "/dist/bundle.js"))
  assert_false(paths_contain(paths, "/coverage/report.json"))
}

///|
test "discover_files: nested indexionignore is loaded during directory traversal" {
  let root = make_test_dir("nested-ignore")
  write_test_file(root + "/src/main.mbt", "fn main() {}")
  write_test_file(root + "/_build/out.mbt", "fn out() {}")
  write_test_file(root + "/.indexionignore", "_build/\n")
  // .indexionignore in the traversed directory is loaded during directory walk.
  let opts = DiscoverOptions::new(root_dir=root)
  let paths = discover_files([root], opts)
  assert_true(paths_contain(paths, "/src/main.mbt"))
  assert_false(paths_contain(paths, "/_build/out.mbt"))
}

///|
test "discover_files: hidden dirs excluded by default, .github included with include_hidden" {
  let root = make_test_dir("hidden")
  write_test_file(root + "/src/main.mbt", "fn main() {}")
  write_test_file(root + "/.github/workflows/ci.yml", "name: CI")
  write_test_file(root + "/.vscode/settings.json", "{}")
  // Default: hidden dirs excluded
  let opts_default = DiscoverOptions::new(root_dir=root)
  let paths_default = discover_files([root], opts_default)
  assert_true(paths_contain(paths_default, "/src/main.mbt"))
  assert_false(paths_contain(paths_default, "/.github/workflows/ci.yml"))
  assert_false(paths_contain(paths_default, "/.vscode/settings.json"))
  // With include_hidden: hidden dirs included
  let opts_hidden = DiscoverOptions::new(root_dir=root, include_hidden=true)
  let paths_hidden = discover_files([root], opts_hidden)
  assert_true(paths_contain(paths_hidden, "/src/main.mbt"))
  assert_true(paths_contain(paths_hidden, "/.github/workflows/ci.yml"))
  assert_true(paths_contain(paths_hidden, "/.vscode/settings.json"))
}

///|
test "discover_files: include_hidden still respects .indexionignore and .gitignore" {
  let root = make_test_dir("hidden-ignore")
  write_test_file(root + "/src/main.mbt", "fn main() {}")
  write_test_file(root + "/.github/workflows/ci.yml", "name: CI")
  write_test_file(root + "/node_modules/dep/index.js", "module.exports = {}")
  write_test_file(root + "/_build/out.mbt", "fn out() {}")
  write_test_file(root + "/.indexionignore", "_build/\nnode_modules/\n")
  // include_hidden=true should include .github but still exclude
  // directories matched by .indexionignore
  let opts = DiscoverOptions::new(root_dir=root, include_hidden=true)
  let paths = discover_files([root], opts)
  assert_true(paths_contain(paths, "/src/main.mbt"))
  assert_true(paths_contain(paths, "/.github/workflows/ci.yml"))
  assert_false(paths_contain(paths, "/node_modules/dep/index.js"))
  assert_false(paths_contain(paths, "/_build/out.mbt"))
}
