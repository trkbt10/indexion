///|
/// Builds a minimal spec whose `Decl` rule binds `id` (directly) and `doc`
/// (only inside the referenced `Docstring` sub-rule, so it does NOT leak to
/// `Decl`). `EXTRA` is a non-SKIP token no rule consumes.
fn label_ref_spec(
  semantics : Map[String, Array[@kgf_types.SemOnBlock]]?,
  attrs : Map[String, Array[@kgf_types.AttrAction]],
) -> @kgf_types.KGFSpec {
  @kgf_types.KGFSpec::new(
    "labelref",
    tokens=[
      @kgf_types.TokenDef::new("KW_def", "def"),
      @kgf_types.TokenDef::new("Ident", "[a-z]+"),
      @kgf_types.TokenDef::new("STR", "\"[^\"]*\""),
      @kgf_types.TokenDef::new("EXTRA", "@"),
      @kgf_types.TokenDef::new("WS", "\\s+", skip=true),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Decl*"),
      "Decl": @kgf_types.RuleDef::new("Decl", "KW_def id:Ident Docstring?"),
      "Docstring": @kgf_types.RuleDef::new("Docstring", "doc:STR"),
    },
    attrs~,
    semantics~,
  )
}

///|
fn warnings_in(
  diagnostics : Array[Diagnostic],
  section : String,
) -> Array[String] {
  let out : Array[String] = []
  for d in diagnostics {
    if d.get_section() == section && d.get_severity() == "warning" {
      out.push(d.get_message())
    }
  }
  out
}

///|
fn any_message_contains(messages : Array[String], needle : String) -> Bool {
  messages.iter().any(fn(m) { m.contains(needle) })
}

///|
test "check: unbound label reference in semantics is a warning" {
  // `$doc` is bound by Docstring, not by Decl — named labels never leak out
  // of a referenced rule, so `$doc` evaluates to null at runtime.
  let block = @kgf_types.SemOnBlock::new("Decl", [
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
  let spec = label_ref_spec(Some({ "Decl": [block] }), Map([]))
  let messages = warnings_in(check(spec), "semantics")
  assert_true(any_message_contains(messages, "'$doc'"))
  assert_true(any_message_contains(messages, "Decl"))
  // `$id` is bound and `$file` is a builtin var — neither may be reported.
  assert_false(any_message_contains(messages, "'$id'"))
  assert_false(any_message_contains(messages, "'$file'"))
}

///|
test "check: derived label forms and let locals are bound" {
  // `$id_text` / `$id_pos` / `$id_len` / `$id_children` derive from `id`,
  // `_text` / `_last` are reserved meta, and `sym` is a `let` local.
  let block = @kgf_types.SemOnBlock::new(
    "Decl",
    [
      @kgf_types.SemStmt::let_("sym", @kgf_types.SemExpr::variable("id_text")),
      @kgf_types.SemStmt::edge(
        "declares",
        @kgf_types.SemExpr::variable("file"),
        @kgf_types.SemExpr::variable("sym"),
        attrs=Some(
          @kgf_types.SemExpr::func("obj", [
            @kgf_types.SemExpr::str("pos"),
            @kgf_types.SemExpr::variable("id_pos"),
            @kgf_types.SemExpr::str("len"),
            @kgf_types.SemExpr::variable("id_len"),
            @kgf_types.SemExpr::str("kids"),
            @kgf_types.SemExpr::variable("id_children"),
            @kgf_types.SemExpr::str("all"),
            @kgf_types.SemExpr::variable("_text"),
            @kgf_types.SemExpr::str("last"),
            @kgf_types.SemExpr::variable("_last"),
          ]),
        ),
      ),
    ],
    when_cond=Some(@kgf_types.SemExpr::variable("id")),
  )
  let spec = label_ref_spec(Some({ "Decl": [block] }), Map([]))
  assert_eq(warnings_in(check(spec), "semantics").length(), 0)
}

///|
test "check: a let local is not visible before its declaration" {
  let block = @kgf_types.SemOnBlock::new("Decl", [
    @kgf_types.SemStmt::edge(
      "declares",
      @kgf_types.SemExpr::variable("file"),
      @kgf_types.SemExpr::variable("sym"),
    ),
    @kgf_types.SemStmt::let_("sym", @kgf_types.SemExpr::variable("id")),
  ])
  let spec = label_ref_spec(Some({ "Decl": [block] }), Map([]))
  assert_true(
    any_message_contains(warnings_in(check(spec), "semantics"), "'$sym'"),
  )
}

///|
test "check: labels nested in groups and repetitions count as bound" {
  let rules : Map[String, @kgf_types.RuleDef] = {
    "Doc": @kgf_types.RuleDef::new("Doc", "Decl*"),
    "Decl": @kgf_types.RuleDef::new(
      "Decl", "KW_def decorators:( Ident / prop:STR )* id:Ident",
    ),
  }
  let block = @kgf_types.SemOnBlock::new("Decl", [
    @kgf_types.SemStmt::edge(
      "declares",
      @kgf_types.SemExpr::variable("file"),
      @kgf_types.SemExpr::variable("id"),
      attrs=Some(
        @kgf_types.SemExpr::func("obj", [
          @kgf_types.SemExpr::str("decorators"),
          @kgf_types.SemExpr::variable("decorators_text"),
          @kgf_types.SemExpr::str("prop"),
          @kgf_types.SemExpr::variable("prop"),
        ]),
      ),
    ),
  ])
  let spec = @kgf_types.KGFSpec::new(
    "nested",
    tokens=[
      @kgf_types.TokenDef::new("KW_def", "def"),
      @kgf_types.TokenDef::new("Ident", "[a-z]+"),
      @kgf_types.TokenDef::new("STR", "\"[^\"]*\""),
    ],
    rules~,
    semantics=Some({ "Decl": [block] }),
  )
  assert_eq(warnings_in(check(spec), "semantics").length(), 0)
}

///|
test "check: unbound label is reported once per rule" {
  let block = @kgf_types.SemOnBlock::new("Decl", [
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
  ])
  let spec = label_ref_spec(Some({ "Decl": [block] }), Map([]))
  let messages = warnings_in(check(spec), "semantics")
  assert_eq(messages.length(), 1)
}

///|
test "check: unbound label reference in attrs is a warning" {
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("def", params={
        "id": "id",
        "kind": "Function",
        "ns": "value",
        "doc": "doc",
      }),
    ],
  }
  let messages = warnings_in(check(label_ref_spec(None, attrs)), "attrs")
  assert_eq(messages.length(), 1)
  assert_true(any_message_contains(messages, "doc=doc"))
  // `kind=Function` and `ns=value` are literals, not label names.
  assert_false(any_message_contains(messages, "kind="))
  assert_false(any_message_contains(messages, "ns="))
}

///|
test "check: attrs naming a bound label produces no warning" {
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [@kgf_types.AttrAction::new("def", params={ "id": "id" })],
  }
  assert_eq(
    warnings_in(check(label_ref_spec(None, attrs)), "attrs").length(),
    0,
  )
}

///|
test "check: token kind no rule consumes is a warning" {
  let messages = warnings_in(check(label_ref_spec(None, Map([]))), "grammar")
  assert_eq(messages.length(), 1)
  assert_true(any_message_contains(messages, "EXTRA"))
  // Consumed kinds and the skipped WS must not be reported.
  assert_false(any_message_contains(messages, "Ident"))
  assert_false(any_message_contains(messages, "WS"))
}

///|
test "check: lex-only spec reports no unreachable token kinds" {
  let spec = @kgf_types.KGFSpec::new("lexonly", tokens=[
    @kgf_types.TokenDef::new("Ident", "[a-z]+"),
    @kgf_types.TokenDef::new("EXTRA", "@"),
  ])
  assert_eq(warnings_in(check(spec), "grammar").length(), 0)
}

///|
test "check: python and rust specs raise no label or token warnings" {
  // These two specs were rewritten against the real engine semantics and are
  // the reference for "correct": a warning here means the check is wrong.
  //
  // Both must stay completely silent — an earlier revision of rust read
  // `$doc` on `doc:DocBlock?` and lost every line of a doc comment but the
  // last, so this is a regression guard for the multi-token check as much as
  // for the specs.
  let registry = @registry.KGFRegistry::load_from_dir(
    @kgf_fixtures.get_kgfs_dir(),
  )
  match registry.get_spec("rust") {
    Some(spec) => {
      let diagnostics = check(spec)
      assert_eq(warnings_in(diagnostics, "semantics").length(), 0)
      assert_eq(warnings_in(diagnostics, "attrs").length(), 0)
      assert_eq(warnings_in(diagnostics, "grammar").length(), 0)
    }
    None => ()
  }
  match registry.get_spec("python") {
    Some(spec) => {
      let diagnostics = check(spec)
      // `MethodDef` binds `prop:PropertyDecoratorLine` inside a `*`; the
      // spec reads it as `$prop_text`, so the multi-token check stays silent.
      assert_eq(warnings_in(diagnostics, "semantics").length(), 0)
      assert_eq(warnings_in(diagnostics, "attrs").length(), 0)
      assert_eq(warnings_in(diagnostics, "grammar").length(), 0)
    }
    None => ()
  }
}

///|
test "check: attrs params the evaluator never reads are not checked" {
  // `note` is not an action kind eval_attrs implements, and `ref ns=` / `def
  // kind=` carry literals — none of them may produce a label warning.
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("note", params={ "id": "fieldKey" }),
      @kgf_types.AttrAction::new("scope", params={ "push": "decl" }),
      @kgf_types.AttrAction::new("ref", params={ "name": "id", "ns": "value" }),
    ],
  }
  assert_eq(
    warnings_in(check(label_ref_spec(None, attrs)), "attrs").length(),
    0,
  )
}

///|
test "check: attrs import/call label params are checked" {
  let attrs : Map[String, Array[@kgf_types.AttrAction]] = {
    "Decl": [
      @kgf_types.AttrAction::new("import", params={ "module": "path" }),
      @kgf_types.AttrAction::new("call", params={ "callee": "id" }),
    ],
  }
  let messages = warnings_in(check(label_ref_spec(None, attrs)), "attrs")
  assert_eq(messages.length(), 1)
  assert_true(any_message_contains(messages, "module=path"))
}

///|
/// A token kind that starts with a lowercase letter is still a reference
/// when a rule names it.
test "check: lowercase-named token consumed by a rule is not unreachable" {
  let spec = @kgf_types.KGFSpec::new(
    "chunks",
    tokens=[
      @kgf_types.TokenDef::new("tEXt", "tEXt"),
      @kgf_types.TokenDef::new("IEND", "IEND"),
      @kgf_types.TokenDef::new("Other", "[a-z]+"),
    ],
    rules={
      "Doc": @kgf_types.RuleDef::new("Doc", "Item*"),
      "Item": @kgf_types.RuleDef::new("Item", "text:tEXt / IEND / Other"),
    },
    attrs={},
    semantics=None,
  )
  let grammar = warnings_in(check(spec), "grammar")
  assert_false(any_message_contains(grammar, "tEXt"))
  assert_false(any_message_contains(grammar, "IEND"))
}

///|
/// A `let` named after a built-in variable is dead: the evaluator answers
/// `$root` / `$file` / `$language` from the context before it looks at locals.
test "check: let shadowing a built-in variable is a warning" {
  let block = @kgf_types.SemOnBlock::new("Decl", [
    @kgf_types.SemStmt::let_(
      "root",
      @kgf_types.SemExpr::call("findAncestor", [@kgf_types.SemExpr::str("x")]),
    ),
    @kgf_types.SemStmt::let_("proj", @kgf_types.SemExpr::variable("id")),
  ])
  let spec = label_ref_spec(Some({ "Decl": [block] }), {})
  let messages = warnings_in(check(spec), "semantics")
  assert_true(any_message_contains(messages, "`let root` shadows"))
  assert_false(any_message_contains(messages, "`let proj`"))
}

// ── LAYOUT directive validation ──────────────────

///|
/// Builds a spec whose grammar brackets a body with the synthetic INDENT and
/// DEDENT kinds, with the LAYOUT declaration and lex tokens supplied by the
/// caller so each test can break exactly one rule.
fn layout_spec(
  layout : @kgf_types.LayoutSpec?,
  extra_tokens : Array[@kgf_types.TokenDef],
  rules : Map[String, @kgf_types.RuleDef],
) -> @kgf_types.KGFSpec {
  let tokens = [
    @kgf_types.TokenDef::new("NL", "\\r?\\n"),
    @kgf_types.TokenDef::new("Comment", "#[^\\n]*"),
    @kgf_types.TokenDef::new("LPAREN", "\\("),
    @kgf_types.TokenDef::new("RPAREN", "\\)"),
    @kgf_types.TokenDef::new("Ident", "[a-z]+"),
  ]
  for token in extra_tokens {
    tokens.push(token)
  }
  @kgf_types.KGFSpec::new("layout", tokens~, layout~, rules~)
}

///|
/// The grammar every valid-layout test uses: a body is exactly one
/// INDENT…DEDENT pair, which is what the directive exists to make possible.
fn layout_rules() -> Map[String, @kgf_types.RuleDef] {
  {
    "Doc": @kgf_types.RuleDef::new("Doc", "Item*"),
    "Item": @kgf_types.RuleDef::new(
      "Item", "NL / Comment / LPAREN / RPAREN / Decl / Ident",
    ),
    "Decl": @kgf_types.RuleDef::new("Decl", "Ident NL INDENT Item* DEDENT"),
  }
}

///|
fn errors_in(
  diagnostics : Array[Diagnostic],
  section : String,
) -> Array[String] {
  let out : Array[String] = []
  for d in diagnostics {
    if d.get_section() == section && d.get_severity() == "error" {
      out.push(d.get_message())
    }
  }
  out
}

///|
/// A well-formed directive passes: the synthetic kinds are accepted as
/// grammar symbols even though no lex TOKEN defines them.
test "check: a well-formed LAYOUT directive produces no diagnostic" {
  let spec = layout_spec(
    Some(
      @kgf_types.LayoutSpec::new(
        ["NL"],
        "INDENT",
        "DEDENT",
        comment=Some("Comment"),
        open=["LPAREN"],
        close=["RPAREN"],
      ),
    ),
    [],
    layout_rules(),
  )
  assert_eq(errors_in(check(spec), "lex"), [])
  assert_eq(errors_in(check(spec), "grammar"), [])
  assert_eq(warnings_in(check(spec), "grammar"), [])
}

///|
/// Without the directive the same grammar is wrong: INDENT and DEDENT are
/// then symbols nothing defines. This is what makes the acceptance above a
/// consequence of the directive rather than of a blanket exemption.
test "check: INDENT is undefined without a LAYOUT directive" {
  let spec = layout_spec(None, [], layout_rules())
  let messages = errors_in(check(spec), "grammar")
  assert_true(any_message_contains(messages, "undefined symbol 'INDENT'"))
  assert_true(any_message_contains(messages, "undefined symbol 'DEDENT'"))
}

///|
test "check: LAYOUT naming an undefined token kind is an error" {
  let spec = layout_spec(
    Some(
      @kgf_types.LayoutSpec::new(
        ["NEWLINE"],
        "INDENT",
        "DEDENT",
        comment=Some("Remark"),
        open=["LBRACE"],
        close=["RBRACE"],
      ),
    ),
    [],
    layout_rules(),
  )
  let messages = errors_in(check(spec), "lex")
  assert_true(any_message_contains(messages, "'NEWLINE'"))
  assert_true(any_message_contains(messages, "'Remark'"))
  assert_true(any_message_contains(messages, "'LBRACE'"))
  assert_true(any_message_contains(messages, "'RBRACE'"))
}

///|
/// A synthetic kind that the lex section also defines as a TOKEN would be
/// emitted from source text as well as by the pass, and the grammar could no
/// longer tell the two apart.
test "check: a synthetic kind defined as a lex TOKEN is an error" {
  let spec = layout_spec(
    Some(@kgf_types.LayoutSpec::new(["NL"], "INDENT", "DEDENT")),
    [@kgf_types.TokenDef::new("INDENT", ">>")],
    layout_rules(),
  )
  let messages = errors_in(check(spec), "lex")
  assert_true(any_message_contains(messages, "also defines it as a TOKEN"))
  assert_true(any_message_contains(messages, "'INDENT'"))
}

///|
test "check: the same kind for indent and dedent is an error" {
  let spec = layout_spec(
    Some(@kgf_types.LayoutSpec::new(["NL"], "LAYOUT_MARK", "LAYOUT_MARK")),
    [],
    {
      "Doc": @kgf_types.RuleDef::new("Doc", "Item*"),
      "Item": @kgf_types.RuleDef::new(
        "Item", "NL / Comment / LPAREN / RPAREN / LAYOUT_MARK / Ident",
      ),
    },
  )
  let messages = errors_in(check(spec), "lex")
  assert_true(any_message_contains(messages, "indent and dedent"))
}

///|
/// The synthetic kinds go through the same unreachable-token check as the lex
/// tokens: the pass injects them into every stream, so a grammar that ignores
/// them stops at the first indented line.
test "check: a synthetic kind no grammar rule consumes is a warning" {
  let spec = layout_spec(
    Some(@kgf_types.LayoutSpec::new(["NL"], "INDENT", "DEDENT")),
    [],
    {
      "Doc": @kgf_types.RuleDef::new("Doc", "Item*"),
      "Item": @kgf_types.RuleDef::new(
        "Item", "NL / Comment / LPAREN / RPAREN / Ident",
      ),
    },
  )
  let messages = warnings_in(check(spec), "grammar")
  assert_true(
    any_message_contains(messages, "'INDENT' is synthesized by the LAYOUT"),
  )
  assert_true(
    any_message_contains(messages, "'DEDENT' is synthesized by the LAYOUT"),
  )
}
