///|
test "api: find_pattern_captures returns groups" {
  let matches = find_pattern_captures("(foo)=(\\d+)", "foo=10\nfoo=20")
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].text, "foo=10")
  assert_eq(matches[0].captures, ["foo", "10"])
  assert_eq(matches[1].captures, ["foo", "20"])
}

///|
test "api: find_pattern_captures supports case insensitive" {
  let matches = find_pattern_captures(
    "(reserved)",
    "RESERVED reserved",
    case_insensitive=true,
  )
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].captures[0], "RESERVED")
  assert_eq(matches[1].captures[0], "reserved")
}

///|
test "api: capture literals from normative lines" {
  let content = "## Timeout\nThe value MUST be `36`.\nFor example, `99` is shown.\nThe response SHALL return `200`.\n"
  let numeric = find_pattern_captures(
    "^(?![^\\n]*(?:for example|e\\.g\\.|suppose|consider ))[^\\n]*(?:\\bmust\\b|\\bshall\\b|\\bshould\\b|\\brequired\\b|=|\\|)[^\\n]*\\b([0-9]{1,})\\b",
    content,
    case_insensitive=true,
  )
  let quoted = find_pattern_captures(
    "^(?![^\\n]*(?:for example|e\\.g\\.|suppose|consider ))[^\\n]*(?:\\bmust\\b|\\bshall\\b|\\bshould\\b|\\brequired\\b|=|\\|)[^\\n]*`([^`\\n]+)`",
    content,
    case_insensitive=true,
  )
  assert_eq(numeric.map(fn(m) { m.captures[0] }), ["36", "200"])
  assert_eq(quoted.map(fn(m) { m.captures[0] }), ["36", "200"])
}

///|
test "api: capture section refs and pipe table pairs" {
  let content = "6. CHIMP Specification\nSee sections 6.1 and 6.2.\n| 7 | REQUEST_STOP |\n"
  let refs1 = find_pattern_captures(
    "^((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?[ \\t]",
    content,
    case_insensitive=true,
  )
  let refs2 = find_pattern_captures(
    "\\bsections?\\s+((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?\\b",
    content,
    case_insensitive=true,
  )
  let refs3 = find_pattern_captures(
    "\\b(?:and|or)\\s+((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?\\b",
    content,
    case_insensitive=true,
  )
  let pairs = find_pattern_captures(
    "\\|\\s*([0-9]+(?:\\.[0-9]+)*)\\s*\\|\\s*([A-Za-z][A-Za-z0-9 /'_-]*[A-Za-z0-9/_-])\\s*\\|",
    content,
  )
  assert_eq(refs1.map(fn(m) { m.captures[0] }), ["6"])
  assert_eq(refs2.map(fn(m) { m.captures[0] }), ["6.1"])
  assert_eq(refs3.map(fn(m) { m.captures[0] }), ["6.2"])
  assert_eq(pairs.length(), 1)
  assert_eq(pairs[0].captures, ["7", "REQUEST_STOP"])
}

///|
test "api: matches_at convenience" {
  assert_eq(matches_at("\\d+", "abc123", 3), true)
  assert_eq(matches_at("\\d+", "abc123", 0), false)
}

///|
test "api: compile_pattern returns None for invalid" {
  // Unclosed character class
  let result = compile_pattern("[abc")
  assert_true(result is None)
}

///|
test "api: find_pattern_captures empty input" {
  let matches = find_pattern_captures("\\d+", "")
  assert_eq(matches.length(), 0)
}

///|
test "api: find_pattern_captures no match" {
  let matches = find_pattern_captures("\\d+", "abc def")
  assert_eq(matches.length(), 0)
}

///|
test "api: find_pattern_captures multiple non-overlapping" {
  let matches = find_pattern_captures("\\d+", "a1b22c333d")
  assert_eq(matches.length(), 3)
  assert_eq(matches[0].text, "1")
  assert_eq(matches[1].text, "22")
  assert_eq(matches[2].text, "333")
}

///|
test "api: CompiledPattern::literal_text recovers single-literal patterns" {
  // Punctuation-style patterns whose entire regex reduces to a fixed
  // string — possibly with escaped meta characters — must report that
  // string. Lets KGF tooling map `TOKEN LPAREN /\(/` to `"("` without
  // re-implementing regex parsing outside this package.
  let cases : Array[(String, String)] = [
    ("\\(", "("),
    ("\\)", ")"),
    ("\\{", "{"),
    ("\\}", "}"),
    ("\\[", "["),
    ("\\]", "]"),
    ("\\.", "."),
    ("\\|", "|"),
    ("\\?", "?"),
    ("\\*", "*"),
    ("\\+", "+"),
    ("::", "::"),
    (":", ":"),
    (",", ","),
    ("=", "="),
    ("=>", "=>"),
    ("->", "->"),
    (";", ";"),
    ("~", "~"),
    ("!", "!"),
    ("@", "@"),
    ("&", "&"),
  ]
  for case in cases {
    let (pattern, expected) = case
    let compiled = match compile_pattern(pattern) {
      Some(c) => c
      None => {
        println("expected to compile pattern: " + pattern)
        assert_true(false)
        return
      }
    }
    match compiled.literal_text() {
      Some(value) => assert_eq(value, expected)
      None => {
        println("expected Some literal for pattern: " + pattern)
        assert_true(false)
      }
    }
  }
}

///|
test "api: CompiledPattern::literal_text rejects non-literal patterns" {
  // Anything with quantifiers, alternation, character classes, anchors,
  // capture groups, shortcut escapes, or case-insensitivity must report
  // None — otherwise consumers would extract bogus literals from
  // structural patterns like identifier classes or keyword forms.
  let non_literals = [
    "[A-Z][A-Za-z0-9_]*", // identifier class
     "\\r?\\n", // newline pattern
     "[ \\t]+", // whitespace run
     "\\d+", // shortcut escape
     "\\s+", // shortcut escape
     "pub\\b", // keyword with word boundary
     "<<=|>>=|==", // alternation
     "0x[0-9a-fA-F_]+", // mixed
     "\\/\\/[^\\r\\n]*", // line comment
  ]
  for pattern in non_literals {
    let compiled = match compile_pattern(pattern) {
      Some(c) => c
      None => continue
    }
    match compiled.literal_text() {
      None => ()
      Some(value) => {
        println(
          "expected None for non-literal pattern: " +
          pattern +
          ", got: " +
          value,
        )
        assert_true(false)
      }
    }
  }
}

///|
test "api: CompiledPattern::literal_text returns None for case-insensitive patterns" {
  let compiled = match compile_pattern("abc", case_insensitive=true) {
    Some(c) => c
    None => {
      println("expected pattern to compile")
      assert_true(false)
      return
    }
  }
  match compiled.literal_text() {
    None => ()
    Some(_) => {
      println("expected None for case-insensitive pattern")
      assert_true(false)
    }
  }
}
