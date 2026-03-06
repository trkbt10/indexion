///|
test "glob_match: basic wildcard" {
  assert_true(glob_match("foo.txt", "*.txt"))
  assert_true(glob_match("bar.txt", "*.txt"))
  assert_true(glob_match(".txt", "*.txt"))
  assert_false(glob_match("foo.js", "*.txt"))
}

///|
test "glob_match: question mark" {
  assert_true(glob_match("a.txt", "?.txt"))
  assert_true(glob_match("b.txt", "?.txt"))
  assert_false(glob_match("ab.txt", "?.txt"))
  assert_false(glob_match("/a.txt", "?.txt"))
}

///|
test "glob_match: double star basic" {
  assert_true(glob_match("a/b/c.txt", "**/c.txt"))
  assert_true(glob_match("c.txt", "**/c.txt"))
  assert_true(glob_match("x/y/z/c.txt", "**/c.txt"))
}

///|
test "glob_match: double star with prefix" {
  assert_true(glob_match("a/b/c.txt", "a/**/c.txt"))
  assert_true(glob_match("a/c.txt", "a/**/c.txt"))
  assert_false(glob_match("b/c.txt", "a/**/c.txt"))
}

///|
test "glob_match: character class" {
  assert_true(glob_match("a.txt", "[abc].txt"))
  assert_true(glob_match("b.txt", "[abc].txt"))
  assert_true(glob_match("c.txt", "[abc].txt"))
  assert_false(glob_match("d.txt", "[abc].txt"))
}

///|
test "glob_match: negated character class" {
  assert_false(glob_match("a.txt", "[!abc].txt"))
  assert_true(glob_match("d.txt", "[!abc].txt"))
}

///|
test "glob_match: character range" {
  assert_true(glob_match("5.txt", "[0-9].txt"))
  assert_false(glob_match("a.txt", "[0-9].txt"))
}

///|
test "glob_match_anywhere: unanchored pattern" {
  assert_true(glob_match_anywhere("a/b/node_modules/c.js", "node_modules"))
  assert_true(glob_match_anywhere("node_modules/c.js", "node_modules"))
  assert_true(glob_match_anywhere("node_modules", "node_modules"))
}

///|
test "parse_ignore_file: basic patterns" {
  let content = "*.txt\nfoo/\n!important.txt\n"
  let patterns = parse_ignore_file(content, GITIGNORE_FILENAME)
  assert_eq(patterns.length(), 3)
  assert_eq(patterns[0].pattern, "*.txt")
  assert_false(patterns[0].negated)
  assert_eq(patterns[1].pattern, "foo")
  assert_true(patterns[1].directory_only)
  assert_eq(patterns[2].pattern, "important.txt")
  assert_true(patterns[2].negated)
}

///|
test "parse_ignore_file: comments and blanks" {
  let content = "# comment\n\n*.txt\n   \n# another\nfoo\n"
  let patterns = parse_ignore_file(content, GITIGNORE_FILENAME)
  assert_eq(patterns.length(), 2)
  assert_eq(patterns[0].pattern, "*.txt")
  assert_eq(patterns[1].pattern, "foo")
}

///|
test "parse_ignore_file: anchored patterns" {
  let content = "/root-only\ndir/specific\neverywhere\n"
  let patterns = parse_ignore_file(content, GITIGNORE_FILENAME)
  assert_eq(patterns.length(), 3)
  assert_true(patterns[0].anchored)
  assert_eq(patterns[0].pattern, "root-only")
  assert_true(patterns[1].anchored) // Contains /
  assert_false(patterns[2].anchored)
}

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
