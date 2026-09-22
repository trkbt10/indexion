///|
fn simple_check_spec() -> @kgf_types.KGFSpec {
  @kgf_types.KGFSpec::new(
    "test",
    tokens=[
      @kgf_types.TokenDef::new("IDENT", "[a-z]+"),
      @kgf_types.TokenDef::new("NUMBER", "[0-9]+"),
      @kgf_types.TokenDef::new("WS", "\\s+", skip=true),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "IDENT NUMBER?"),
      "Pair": @kgf_types.RuleDef::new("Pair", "IDENT NUMBER"),
    },
  )
}

///|
test "check_source: valid source has no diagnostics" {
  let diagnostics = check_source("foo 42", "test.txt", simple_check_spec())
  assert_eq(diagnostics.length(), 0)
}

///|
test "check_source: reports lexer diagnostics with source position" {
  let diagnostics = check_source("foo @@", "test.txt", simple_check_spec())
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].get_file(), "test.txt")
  assert_eq(diagnostics[0].get_line(), 1)
  assert_eq(diagnostics[0].get_col(), 5)
  assert_eq(diagnostics[0].get_source(), "lexer")
  assert_true(diagnostics[0].get_message().contains("@@"))
}

///|
test "check_source: reports parser diagnostics with expected token" {
  let spec = @kgf_types.KGFSpec::new(
    "test",
    tokens=[
      @kgf_types.TokenDef::new("IDENT", "[a-z]+"),
      @kgf_types.TokenDef::new("NUMBER", "[0-9]+"),
      @kgf_types.TokenDef::new("WS", "\\s+", skip=true),
    ],
    rules={ "Doc": @kgf_types.RuleDef::new("Doc", "IDENT NUMBER") },
  )
  let diagnostics = check_source("foo bar", "test.txt", spec)
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].get_line(), 1)
  assert_eq(diagnostics[0].get_col(), 5)
  assert_eq(diagnostics[0].get_source(), "parser")
  assert_true(diagnostics[0].get_message().contains("NUMBER"))
  assert_true(diagnostics[0].get_message().contains("IDENT"))
}

///|
test "check_source: entirely unrecognized source only reports lexer" {
  let diagnostics = check_source("@@", "test.txt", simple_check_spec())
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].get_source(), "lexer")
}

///|
test "check_source: mermaid fixture is accepted" {
  let registry = @registry.KGFRegistry::load_from_dir(
    @kgf_fixtures.get_kgfs_dir(),
  )
  let spec = registry.get_spec("mermaid").unwrap()
  let path = @kgf_fixtures.get_fixtures_dir() + "/diagram/mermaid/gantt.mmd"
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  if content.length() > 0 {
    let diagnostics = check_source(content, path, spec)
    assert_eq(diagnostics.length(), 0)
  }
}

///|
test "check_source: broken mermaid fixture reports diagnostics" {
  let registry = @registry.KGFRegistry::load_from_dir(
    @kgf_fixtures.get_kgfs_dir(),
  )
  let spec = registry.get_spec("mermaid").unwrap()
  let path = @kgf_fixtures.get_fixtures_dir() + "/diagram/mermaid/broken.mmd"
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  if content.length() > 0 {
    let diagnostics = check_source(content, path, spec)
    assert_true(diagnostics.length() > 0)
    assert_true(diagnostics.iter().any(fn(d) { d.get_severity() == "error" }))
  }
}

///|
/// A spec whose grammar only accepts blanked-out lines: a line containing
/// "DROP" is rewritten to an empty line by `=== preprocess`, so raw content
/// that the grammar rejects becomes acceptable once prepared. This is exactly
/// the shape of the real preprocess specs (header/footer lines blanked out
/// before parsing).
fn preprocess_check_spec() -> @kgf_types.KGFSpec {
  @kgf_types.KGFSpec::new(
    "preproc",
    tokens=[
      @kgf_types.TokenDef::new("NL", "\\n"),
      @kgf_types.TokenDef::new("KEEP", "keep"),
      @kgf_types.TokenDef::new("WS", "[ \\t]+", skip=true),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Line*"),
      "Line": @kgf_types.RuleDef::new("Line", "KEEP NL / NL"),
    },
    preprocess=Some(["blankLineIfContains:DROP"]),
  )
}

///|
test "check_source: applies the spec's preprocess steps before lexing" {
  // Raw "DROP me" would fail both the lexer (unknown input) and the parser;
  // the preprocess step blanks the line, so the prepared text parses cleanly.
  let diagnostics = check_source(
    "keep\nDROP me\nkeep\n",
    "preproc.txt",
    preprocess_check_spec(),
  )
  assert_eq(diagnostics.length(), 0)
}

///|
test "check_source: preprocess parity matches the pipeline toolkit" {
  // The toolkit is the single source of truth for preprocessing; check_source
  // must see exactly the text the pipeline tokenizes.
  let spec = preprocess_check_spec()
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  let content = "keep\nDROP me\nkeep\n"
  assert_eq(toolkit.preprocess(content), "keep\n\nkeep\n")
  // Without preprocessing the same content is rejected, which is what the
  // raw-content implementation used to report.
  let raw_spec = @kgf_types.KGFSpec::new(
    "raw",
    tokens=spec.get_tokens(),
    rules=spec.get_rules(),
  )
  assert_true(check_source(content, "raw.txt", raw_spec).length() > 0)
}

///|
test "check_source: positions are resolved against the prepared text" {
  // The prepared text is what was tokenized, so line/col must index into it.
  // Here preprocess blanks line 2, and the offending token sits on line 3.
  let diagnostics = check_source(
    "keep\nDROP me\nbogus\n",
    "preproc.txt",
    preprocess_check_spec(),
  )
  assert_true(diagnostics.length() > 0)
  assert_eq(diagnostics[0].get_line(), 3)
  assert_eq(diagnostics[0].get_col(), 1)
}
