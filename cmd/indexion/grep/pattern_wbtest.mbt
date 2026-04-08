///|
test "parse_pattern treats plain words as normalized text matchers" {
  let parsed = parse_pattern("version")
  assert_eq(parsed.length(), 1)
  match parsed[0] {
    Text(value) => assert_eq(value, "version")
    _ => assert_true(false)
  }
}

///|
test "parse_pattern keeps token kinds and aliases as structural matchers" {
  let aliases : Map[String, String] = { "pub": "KW_pub" }
  let parsed = parse_pattern_with_aliases("pub KW_fn", aliases)
  assert_eq(parsed.length(), 2)
  match parsed[0] {
    Kind(value) => assert_eq(value, "KW_pub")
    _ => assert_true(false)
  }
  match parsed[1] {
    Kind(value) => assert_eq(value, "KW_fn")
    _ => assert_true(false)
  }
}

///|
test "parse_pattern preserves quotes in plain text patterns" {
  let parsed = parse_pattern("\"version\"")
  assert_eq(parsed.length(), 1)
  match parsed[0] {
    Text(value) => assert_eq(value, "\"version\"")
    _ => assert_true(false)
  }
}
