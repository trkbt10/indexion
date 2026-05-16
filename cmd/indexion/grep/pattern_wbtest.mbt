///|
using @test {assert_eq}

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

///|
/// Resolve a representative spec from the loaded registry for tests that
/// need a non-empty KGFSpec input.
fn moonbit_spec() -> @kgf_types.KGFSpec? {
  let registry = @kgf_features.load_registry_or_empty(specs_dir="kgfs")
  registry.get_spec("moonbit")
}

///|
test "parse_pattern with MoonBit spec: PascalCase identifiers become Text matchers" {
  // Regression: pattern parts like "Handle" or "Some" used to be treated as
  // structural kind matchers via a lexical uppercase heuristic, producing
  // Kind("Handle") — but no KGF spec declares a kind named "Handle", so the
  // matcher could never fire and `indexion grep Handle` returned zero hits
  // even when "Handle" appeared in the source as a TypeIdent token.
  let spec = moonbit_spec()
  let aliases = build_alias_table(spec)
  let kinds = build_kind_set(spec)
  for part in ["Handle", "Some", "None", "Layout"] {
    let parsed = parse_pattern_with_aliases(part, aliases, kinds~)
    assert_eq(parsed.length(), 1)
    match parsed[0] {
      Text(value) => assert_eq(value, part.to_lower())
      _ => {
        println("expected Text matcher for pattern: " + part)
        assert_true(false)
      }
    }
  }
}

///|
test "parse_pattern with MoonBit spec: real token-kind names stay Kind matchers" {
  // The fix must not regress the legitimate use of structural kind matchers:
  // names that actually appear as TOKEN declarations in some KGF spec must
  // still produce Kind(...) so patterns like "KW_pub KW_fn TypeIdent" work.
  let spec = moonbit_spec()
  let aliases = build_alias_table(spec)
  let kinds = build_kind_set(spec)
  for name in ["TypeIdent", "Ident", "Number", "KW_fn"] {
    let parsed = parse_pattern_with_aliases(name, aliases, kinds~)
    assert_eq(parsed.length(), 1)
    match parsed[0] {
      Kind(value) => assert_eq(value, name)
      _ => {
        println("expected Kind matcher for token name: " + name)
        assert_true(false)
      }
    }
  }
}

///|
test "build_alias_table derives MoonBit punctuation aliases from KGF token patterns" {
  // Regression: alias creation used to hardcode `match name { "LPAREN" =>
  // aliases.set("(", name) ... }`, so any spec that named its open paren
  // something other than `LPAREN` got no alias even if its regex was just
  // `\(`. Driving the alias entirely from the regex pattern lets new
  // specs work without touching grep. Resolved per-spec so that
  // collisions across specs (e.g. Mermaid's RoundOpen vs MoonBit's LPAREN
  // both for `(`) don't shadow each other.
  let spec = moonbit_spec()
  let aliases = build_alias_table(spec)
  let punctuation_cases : Array[(String, String)] = [
    ("(", "LPAREN"),
    (")", "RPAREN"),
    ("{", "LBRACE"),
    ("}", "RBRACE"),
    ("[", "LBRACKET"),
    ("]", "RBRACKET"),
    ("::", "DCOLON"),
    (":", "COLON"),
    (",", "COMMA"),
    (".", "DOT"),
    ("=", "EQ"),
    ("=>", "FATARROW"),
    ("->", "ARROW"),
    (";", "SEMI"),
  ]
  for case in punctuation_cases {
    let (literal, expected_kind) = case
    match aliases.get(literal) {
      Some(kind) => assert_eq(kind, expected_kind)
      None => {
        println(
          "expected alias for punctuation literal: " +
          literal +
          " → " +
          expected_kind,
        )
        assert_true(false)
      }
    }
  }
  // Keyword aliases must still take precedence — `pub` resolves to KW_pub,
  // never to a stray punctuation kind that happens to share the literal.
  assert_eq(aliases.get("pub"), Some("KW_pub"))
  assert_eq(aliases.get("fn"), Some("KW_fn"))
}

///|
test "parse_pattern_for_path resolves aliases per file's language" {
  // Mixed-language correctness: the same pattern `pub` must resolve to
  // `KW_pub` for a MoonBit file (where the spec defines that keyword)
  // and fall back to a Text matcher when the file has no matching spec
  // (or the matching spec doesn't define `pub` as a keyword).
  let registry = Some(@kgf_features.load_registry_or_empty(specs_dir="kgfs"))
  let moonbit_matchers = parse_pattern_for_path("pub", "demo.mbt", registry)
  assert_eq(moonbit_matchers.length(), 1)
  match moonbit_matchers[0] {
    Kind(value) => assert_eq(value, "KW_pub")
    _ => {
      println("expected Kind(KW_pub) for pub in MoonBit file")
      assert_true(false)
    }
  }
  let unknown_matchers = parse_pattern_for_path(
    "pub", "no-such-extension.unknown", registry,
  )
  assert_eq(unknown_matchers.length(), 1)
  match unknown_matchers[0] {
    Text(value) => assert_eq(value, "pub")
    _ => {
      println("expected Text(pub) for pub in unknown-language file")
      assert_true(false)
    }
  }
}

///|
test "find_matches line tracking advances through multi-line tokens" {
  // Regression: build_token_lines used to count lines by checking `kind ==
  // "NL"`, which silently misses newlines embedded inside block comments,
  // multi-line strings, and Python's `NL_INDENT`. Counting actual `\n`
  // characters in each token's text instead is KGF-agnostic and reports
  // correct line numbers for matches that follow such tokens.
  let registry = @kgf_features.load_registry_or_empty(specs_dir="kgfs")
  let content =
    #|fn first() -> Int { 1 }
    #|/* block
    #|   comment spanning
    #|   several lines */
    #|fn after_block() -> Int { 2 }
    #|
  let path = "test_lines.mbt"
  let tokens = match
    @kgf_features.tokenize_source(content, path, Some(registry)) {
    Some(value) => value
    None => {
      println("MoonBit spec not loaded — skipping line tracking assertion")
      return
    }
  }
  let spec = match registry.detect_from_path(path) {
    Some(lang) => registry.get_spec(lang)
    None => None
  }
  let matchers = parse_pattern_for_path("after_block", path, Some(registry))
  let matches = find_matches(tokens, matchers, path, content, spec~)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].line, 5)
}
