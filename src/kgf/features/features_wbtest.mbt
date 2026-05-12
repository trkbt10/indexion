///|
fn test_registry() -> @kgf_registry.KGFRegistry {
  load_registry_or_empty(specs_dir="kgfs", target_dir=".")
}

///|
test "extract_literal_from_pattern recognizes pure-literal regex patterns" {
  // Punctuation tokens whose entire regex pattern is a literal — possibly
  // with escaped meta characters — should yield the literal text. This is
  // what lets grep build punctuation aliases from a KGF spec without
  // hardcoding any name→literal mapping.
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
    match extract_literal_from_pattern(pattern) {
      Some(value) => assert_eq(value, expected)
      None => {
        println("expected Some literal for pattern: " + pattern)
        assert_true(false)
      }
    }
  }
}

///|
test "extract_literal_from_pattern rejects patterns with regex operators" {
  // Patterns containing quantifiers, alternation, character classes, or
  // shortcut escapes are NOT literals and must return None — otherwise the
  // alias table would invent bogus literals from things like keywords with
  // word boundaries or identifier classes.
  let non_literals = [
    "[A-Z][A-Za-z0-9_]*", // identifier class
    "\\r?\\n", // NL pattern
    "[ \\t]+", // whitespace run
    "\\d+", // shortcut escape
    "\\s+", // shortcut escape
    "pub\\b", // keyword with word boundary
    "<<=|>>=|==", // alternation
    "0x[0-9a-fA-F_]+", // mixed
    "\\/\\/[^\\r\\n]*", // line comment
    "", // empty pattern
  ]
  for pattern in non_literals {
    match extract_literal_from_pattern(pattern) {
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
test "pattern_is_whitespace_only detects newline and indentation patterns" {
  let whitespace_patterns = [
    "\\r?\\n", // MoonBit/Rust/Go NL
    "\\r?\\n[ \\t]+", // Python NL_INDENT
    "[ \\t]+", // generic WS
    "\\s+", // shortcut WS
    " ", // literal space
  ]
  for pattern in whitespace_patterns {
    assert_true(pattern_is_whitespace_only(pattern))
  }
  let non_ws = [
    "[A-Z][A-Za-z0-9_]*",
    "\\(", // punctuation
    "pub\\b", // keyword
    "0x[0-9a-fA-F_]+",
    "\\d+",
    "",
  ]
  for pattern in non_ws {
    assert_false(pattern_is_whitespace_only(pattern))
  }
}

///|
test "build_insignificant_token_set covers Python NL and NL_INDENT" {
  // Regression: grep used to hardcode the names NL/WS/SKIP for the filter
  // applied to token streams before pattern matching, so Python's
  // NL_INDENT was treated as a significant token and broke patterns that
  // tried to skip across indented newlines. With KGF-driven detection,
  // both newline kinds in python.kgf must be classified insignificant.
  let registry = test_registry()
  let spec = match registry.get_spec("python") {
    Some(s) => s
    None => {
      println("python KGF spec not loaded — skipping assertion")
      return
    }
  }
  let set = build_insignificant_token_set(spec~)
  assert_true(set.contains("NL"))
  assert_true(set.contains("NL_INDENT"))
  // Significant kinds — identifiers, numbers, strings — must NOT be in
  // the insignificant set, otherwise grep would silently skip them.
  assert_false(set.contains("Ident"))
  assert_false(set.contains("Number"))
}

///|
test "is_document_file detects markdown and code separately" {
  let registry = test_registry()
  assert_eq(is_document_file("README.md", Some(registry)), Some(true))
  assert_eq(is_document_file("src/main.ts", Some(registry)), Some(false))
  assert_eq(
    content_type_for_file("README.md", Some(registry)),
    Some("document"),
  )
  assert_eq(content_type_for_file("src/main.ts", Some(registry)), None)
}

///|
test "is_document_file supports rfc plaintext fixture suffix" {
  let registry = test_registry()
  assert_eq(
    is_document_file("fixtures/spec/rfc2795.rfc.txt", Some(registry)),
    Some(true),
  )
}

///|
test "content_type_for_file resolves structured config and script files" {
  let registry = test_registry()
  assert_eq(
    content_type_for_file("moon.mod.json", Some(registry)),
    Some("config"),
  )
  assert_eq(
    content_type_for_file(".github/workflows/release.yml", Some(registry)),
    Some("config"),
  )
  assert_eq(
    content_type_for_file("scripts/sync-version.sh", Some(registry)),
    Some("script"),
  )
  assert_eq(
    content_type_for_file(".gitmodules", Some(registry)),
    Some("config"),
  )
}

///|
test "token_search_terms includes vocabulary subtokens for string literals" {
  let registry = test_registry()
  let spec = registry.get_spec("json").unwrap()
  let tokens = tokenize_source(
    "{\"feature_name\":\"release-build\"}",
    "package.json",
    Some(registry),
  ).unwrap()
  let string_lits : Array[@kgf_types.Tok] = []
  for tok in tokens {
    if tok.get_kind() == "StringLit" {
      string_lits.push(tok)
    }
  }
  assert_eq(string_lits.length(), 2)
  let key_terms = token_search_terms(string_lits[0], spec~)
  let value_terms = token_search_terms(string_lits[1], spec~)
  assert_true(key_terms.contains("\"feature_name\""))
  assert_true(key_terms.contains("feature_name"))
  assert_true(value_terms.contains("\"release-build\""))
  assert_true(value_terms.contains("release"))
  assert_true(value_terms.contains("build"))
}
