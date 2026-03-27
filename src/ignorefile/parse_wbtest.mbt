///|
test "parse: basic patterns" {
  let content = "*.txt\nfoo/\n!important.txt\n"
  let patterns = parse(content, ".gitignore")
  assert_eq(patterns.length(), 3)
  assert_eq(patterns[0].pattern, "*.txt")
  assert_false(patterns[0].negated)
  assert_eq(patterns[1].pattern, "foo")
  assert_true(patterns[1].directory_only)
  assert_eq(patterns[2].pattern, "important.txt")
  assert_true(patterns[2].negated)
}

///|
test "parse: comments and blanks" {
  let content = "# comment\n\n*.txt\n   \n# another\nfoo\n"
  let patterns = parse(content, ".gitignore")
  assert_eq(patterns.length(), 2)
  assert_eq(patterns[0].pattern, "*.txt")
  assert_eq(patterns[1].pattern, "foo")
}

///|
test "parse: anchored patterns" {
  let content = "/root-only\ndir/specific\neverywhere\n"
  let patterns = parse(content, ".gitignore")
  assert_eq(patterns.length(), 3)
  assert_true(patterns[0].anchored)
  assert_eq(patterns[0].pattern, "root-only")
  assert_true(patterns[1].anchored)
  assert_false(patterns[2].anchored)
}
