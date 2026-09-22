// Tests for the lexical-scoping (`scope push` / `scope pop`) diagnostics
// produced by `check`. Specs are built inline rather than read from kgfs/.

///|
/// Builds a spec whose single grammar rule carries the given semantics block.
fn spec_with_semantics(body : String) -> @kgf_types.KGFSpec {
  let text = "on Decl {\n" + body + "\n}\n"
  let semantics = @kgf_parser.parse_semantics(text)
  @kgf_types.KGFSpec::new(
    "test",
    tokens=[@kgf_types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "Decl": @kgf_types.RuleDef::new("Decl", "IDENT") },
    semantics~,
  )
}

///|
/// Returns the messages of all diagnostics that mention scope frames.
fn scope_diagnostics(spec : @kgf_types.KGFSpec) -> Array[String] {
  let messages : Array[String] = []
  for d in check(spec) {
    if d.get_message().contains("scope push") ||
      d.get_message().contains("scope pop") {
      messages.push(d.get_message())
    }
  }
  messages
}

///|
test "check: scope push/pop statements are accepted without diagnostics" {
  let spec = spec_with_semantics("  scope push\n  scope pop")
  assert_eq(scope_diagnostics(spec).length(), 0)
  // And nothing else about the spec is flagged as an error.
  for d in check(spec) {
    assert_eq(d.get_severity(), "warning")
  }
}

///|
test "check: scope push without any scope pop is reported" {
  let spec = spec_with_semantics("  scope push")
  let messages = scope_diagnostics(spec)
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("never 'scope pop'"))
}

///|
test "check: scope pop without any scope push is reported" {
  let spec = spec_with_semantics("  scope pop")
  let messages = scope_diagnostics(spec)
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("never 'scope push'"))
}

///|
test "check: balance is spec-wide, not per block" {
  // The intended pattern splits push and pop across two rules, so a block
  // holding only one half must not be flagged.
  let text =
    #|on Header {
    #|  scope push
    #|}
    #|on Decl {
    #|  scope pop
    #|}
    #|
  let spec = @kgf_types.KGFSpec::new(
    "test",
    tokens=[@kgf_types.TokenDef::new("IDENT", "[a-z]+")],
    rules={
      "Decl": @kgf_types.RuleDef::new("Decl", "Header IDENT"),
      "Header": @kgf_types.RuleDef::new("Header", "IDENT"),
    },
    semantics=@kgf_parser.parse_semantics(text),
  )
  assert_eq(scope_diagnostics(spec).length(), 0)
}

///|
test "check: scope statements nested in a for body are counted" {
  let body = @kgf_types.SemStmt::for_(
    "x",
    @kgf_types.SemExpr::variable("items"),
    [@kgf_types.SemStmt::scope_push()],
  )
  let block = @kgf_types.SemOnBlock::new("Decl", [body])
  let spec = @kgf_types.KGFSpec::new(
    "test",
    tokens=[@kgf_types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "Decl": @kgf_types.RuleDef::new("Decl", "IDENT") },
    semantics=Some({ "Decl": [block] }),
  )
  let messages = scope_diagnostics(spec)
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("never 'scope pop'"))
}

///|
test "check: a spec with no scope statements reports nothing" {
  let spec = spec_with_semantics("  edge declares from $file to $id")
  assert_eq(scope_diagnostics(spec).length(), 0)
}
