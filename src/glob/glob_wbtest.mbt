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
