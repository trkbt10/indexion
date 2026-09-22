///|
/// A spec whose `Decl` rule binds labels to captures of varying width:
///
/// - `id:Ident`        — one token, safe;
/// - `name:Name`       — a rule whose every alternative is a single token,
///                       still safe;
/// - `doc:DocBlock?`   — a rule with a `*` repetition, multi-token;
/// - `path:Qualified`  — a rule with a 2+ element sequence, multi-token.
fn multi_token_spec(
  semantics : Map[String, Array[@kgf_types.SemOnBlock]]?,
  attrs : Map[String, Array[@kgf_types.AttrAction]],
) -> @kgf_types.KGFSpec {
  @kgf_types.KGFSpec::new(
    "multitok",
    tokens=[
      @kgf_types.TokenDef::new("KW_def", "def"),
      @kgf_types.TokenDef::new("Ident", "[a-z]+"),
      @kgf_types.TokenDef::new("TypeIdent", "[A-Z][a-z]*"),
      @kgf_types.TokenDef::new("DOT", "\\."),
      @kgf_types.TokenDef::new("DocComment", "///[^\\n]*"),
      @kgf_types.TokenDef::new("WS", "\\s+", skip=true),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Decl*"),
      "Decl": @kgf_types.RuleDef::new(
        "Decl", "doc:DocBlock? KW_def id:Ident name:Name path:Qualified",
      ),
      // Every alternative is exactly one token reference: single-token.
      "Name": @kgf_types.RuleDef::new("Name", "Ident / TypeIdent"),
      // `*` repetition: unbounded.
      "DocBlock": @kgf_types.RuleDef::new(
        "DocBlock", "DocComment ( DocComment )*",
      ),
      // Sequence of 2+ elements: at least two tokens.
      "Qualified": @kgf_types.RuleDef::new("Qualified", "Ident DOT Ident"),
    },
    attrs~,
    semantics~,
  )
}

///|
/// Warnings whose text mentions the truncation, i.e. produced by this check
/// and not by one of the other validations in the same section.
fn truncation_warnings(spec : @kgf_types.KGFSpec) -> Array[String] {
  let out : Array[String] = []
  for d in check(spec) {
    if d.get_severity() == "warning" &&
      d.get_message().contains("can match more than one token") {
      out.push(d.get_message())
    }
  }
  out
}

///|
fn decl_block(attrs : @kgf_types.SemExpr) -> @kgf_types.SemOnBlock {
  @kgf_types.SemOnBlock::new("Decl", [
    @kgf_types.SemStmt::edge(
      "declares",
      @kgf_types.SemExpr::variable("file"),
      @kgf_types.SemExpr::variable("id"),
      attrs=Some(attrs),
    ),
  ])
}

///|
test "check: $label on a repetition rule warns and names the fix" {
  // `doc:DocBlock?` can match many DocComment tokens; `$doc` keeps the last.
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("doc"),
      @kgf_types.SemExpr::variable("doc"),
    ]),
  )
  let messages = truncation_warnings(
    multi_token_spec(Some({ "Decl": [block] }), Map([])),
  )
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("Decl"))
  assert_true(messages[0].contains("'doc'"))
  assert_true(messages[0].contains("DocBlock"))
  assert_true(messages[0].contains("$doc_text"))
}

///|
test "check: $label on a multi-element sequence rule warns" {
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("path"),
      @kgf_types.SemExpr::variable("path"),
    ]),
  )
  let messages = truncation_warnings(
    multi_token_spec(Some({ "Decl": [block] }), Map([])),
  )
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("'path'"))
  assert_true(messages[0].contains("Qualified"))
}

///|
test "check: single-token captures never warn" {
  // `$id` is bound straight to a token, and `$name` to a rule whose every
  // alternative is one token reference — both read back exactly.
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("id"),
      @kgf_types.SemExpr::variable("id"),
      @kgf_types.SemExpr::str("name"),
      @kgf_types.SemExpr::variable("name"),
    ]),
  )
  assert_eq(
    truncation_warnings(multi_token_spec(Some({ "Decl": [block] }), Map([]))).length(),
    0,
  )
}

///|
test "check: reading the _text form of a multi-token capture never warns" {
  // `$doc_text` is the accumulated text — the documented fix — so using it
  // must not be flagged.
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("doc"),
      @kgf_types.SemExpr::variable("doc_text"),
      @kgf_types.SemExpr::str("path"),
      @kgf_types.SemExpr::variable("path_text"),
    ]),
  )
  assert_eq(
    truncation_warnings(multi_token_spec(Some({ "Decl": [block] }), Map([]))).length(),
    0,
  )
}

///|
test "check: a multi-token label is reported once per rule" {
  let block = @kgf_types.SemOnBlock::new(
    "Decl",
    [
      @kgf_types.SemStmt::edge(
        "declares",
        @kgf_types.SemExpr::variable("doc"),
        @kgf_types.SemExpr::variable("doc"),
        attrs=Some(
          @kgf_types.SemExpr::func("obj", [
            @kgf_types.SemExpr::str("doc"),
            @kgf_types.SemExpr::variable("doc"),
          ]),
        ),
      ),
    ],
    when_cond=Some(@kgf_types.SemExpr::variable("doc")),
  )
  assert_eq(
    truncation_warnings(multi_token_spec(Some({ "Decl": [block] }), Map([]))).length(),
    1,
  )
}

///|
test "check: a let local shadowing the label suppresses later reads" {
  // Once `let doc = ...` runs, `$doc` resolves to the local, not the label,
  // so the truncation no longer applies to reads that follow it.
  let block = @kgf_types.SemOnBlock::new("Decl", [
    @kgf_types.SemStmt::let_("doc", @kgf_types.SemExpr::variable("doc_text")),
    @kgf_types.SemStmt::edge(
      "declares",
      @kgf_types.SemExpr::variable("file"),
      @kgf_types.SemExpr::variable("id"),
      attrs=Some(
        @kgf_types.SemExpr::func("obj", [
          @kgf_types.SemExpr::str("doc"),
          @kgf_types.SemExpr::variable("doc"),
        ]),
      ),
    ),
  ])
  assert_eq(
    truncation_warnings(multi_token_spec(Some({ "Decl": [block] }), Map([]))).length(),
    0,
  )
}

///|
test "check: attrs params that read the raw label value warn" {
  // `ref name=path` and `import module=doc` both read `labels.get(<label>)`,
  // the last-token value, so a multi-token capture truncates them.
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("ref", params={ "name": "path" }),
      @kgf_types.AttrAction::new("import", params={ "module": "doc" }),
    ],
  }
  let messages = truncation_warnings(multi_token_spec(None, attrs))
  assert_eq(messages.length(), 2)
  assert_true(messages.iter().any(fn(m) { m.contains("ref name=path") }))
  assert_true(messages.iter().any(fn(m) { m.contains("import module=doc") }))
}

///|
test "check: attrs def doc= reads _text and never warns" {
  // `eval_attr_def` looks `doc` up as `<label>_text`, so binding it to a
  // multi-token capture is exactly right and must stay silent — while `id`
  // on the same action, which reads the raw value, still warns.
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("def", params={
        "id": "path",
        "doc": "doc",
        "kind": "Function",
      }),
    ],
  }
  let messages = truncation_warnings(multi_token_spec(None, attrs))
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("def id=path"))
}

///|
test "check: attrs literal params are not treated as labels" {
  // `kind` and `ns` are literals, never label names, so they cannot truncate
  // even when they happen to spell one.
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("def", params={
        "id": "id",
        "kind": "doc",
        "ns": "path",
      }),
    ],
  }
  assert_eq(truncation_warnings(multi_token_spec(None, attrs)).length(), 0)
}

///|
test "check: a recursive rule counts as multi-token" {
  // `List -> Ident ( DOT List )?` reaches itself, so it is unbounded. The
  // cycle must terminate rather than recurse forever.
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("items"),
      @kgf_types.SemExpr::variable("items"),
    ]),
  )
  let spec = @kgf_types.KGFSpec::new(
    "recursive",
    tokens=[
      @kgf_types.TokenDef::new("Ident", "[a-z]+"),
      @kgf_types.TokenDef::new("DOT", "\\."),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Decl*"),
      "Decl": @kgf_types.RuleDef::new("Decl", "id:Ident items:List"),
      "List": @kgf_types.RuleDef::new("List", "Ident ( DOT List )?"),
    },
    semantics=Some({ "Decl": [block] }),
  )
  let messages = truncation_warnings(spec)
  assert_eq(messages.length(), 1)
  assert_true(messages[0].contains("List"))
}

///|
test "check: a label bound to a lookahead-only rule never warns" {
  // Predicates consume no tokens, so such a capture has no `_last` to
  // truncate and reporting it would be noise.
  let block = decl_block(
    @kgf_types.SemExpr::func("obj", [
      @kgf_types.SemExpr::str("ahead"),
      @kgf_types.SemExpr::variable("ahead"),
    ]),
  )
  let spec = @kgf_types.KGFSpec::new(
    "lookahead",
    tokens=[
      @kgf_types.TokenDef::new("Ident", "[a-z]+"),
      @kgf_types.TokenDef::new("DOT", "\\."),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Decl*"),
      "Decl": @kgf_types.RuleDef::new("Decl", "ahead:Ahead id:Ident"),
      "Ahead": @kgf_types.RuleDef::new("Ahead", "&Ident !DOT"),
    },
    semantics=Some({ "Decl": [block] }),
  )
  assert_eq(truncation_warnings(spec).length(), 0)
}
