///|
test "parse_expr: simple identifier" {
  let node = parse_expr("FOO")
  inspect(node, content="Sym(\"FOO\")")
}

///|
test "parse_expr: sequence" {
  let node = parse_expr("FOO BAR")
  inspect(node, content="Seq([Sym(\"FOO\"), Sym(\"BAR\")])")
}

///|
test "parse_expr: choice" {
  let node = parse_expr("FOO | BAR")
  inspect(node, content="Choice([Sym(\"FOO\"), Sym(\"BAR\")])")
}

///|
test "parse_expr: star" {
  let node = parse_expr("FOO*")
  inspect(node, content="Star(Sym(\"FOO\"))")
}

///|
test "parse_expr: plus" {
  let node = parse_expr("FOO+")
  inspect(node, content="Plus(Sym(\"FOO\"))")
}

///|
test "parse_expr: optional" {
  let node = parse_expr("FOO?")
  inspect(node, content="Optional(Sym(\"FOO\"))")
}

///|
test "parse_expr: label" {
  let node = parse_expr("name:FOO")
  inspect(node, content="Label(\"name\", Sym(\"FOO\"))")
}

///|
test "parse_expr: parentheses" {
  let node = parse_expr("(FOO BAR)")
  inspect(node, content="Seq([Sym(\"FOO\"), Sym(\"BAR\")])")
}

///|
test "parse_expr: brackets for optional" {
  let node = parse_expr("[FOO]")
  inspect(node, content="Optional(Sym(\"FOO\"))")
}

///|
test "parse_expr: complex expression" {
  let node = parse_expr("stmt:IDENT (LPAREN args:expr* RPAREN)?")
  match node {
    Seq(items) => {
      assert_eq(items.length(), 2)
      match items[0] {
        Label("stmt", Sym("IDENT")) => ()
        _ => fail("Expected Label(stmt, Sym(IDENT))")
      }
      match items[1] {
        Optional(_) => ()
        _ => fail("Expected Optional")
      }
    }
    _ => fail("Expected Seq")
  }
}

///|
test "parse_expr: empty expression" {
  let node = parse_expr("")
  inspect(node, content="Empty")
}

///|
test "parse_expr: choice with sequences" {
  let node = parse_expr("FOO BAR | BAZ QUX")
  match node {
    Choice(alts) => {
      assert_eq(alts.length(), 2)
      match alts[0] {
        Seq(_) => ()
        _ => fail("Expected Seq for first alt")
      }
      match alts[1] {
        Seq(_) => ()
        _ => fail("Expected Seq for second alt")
      }
    }
    _ => fail("Expected Choice")
  }
}

///|
test "parse_expr: with comments" {
  let input =
    #|FOO BAR # comment here
    #|BAZ
  let node = parse_expr(input)
  match node {
    Seq(items) => assert_eq(items.length(), 3)
    _ => fail("Expected Seq")
  }
}

///|
test "run_parse: simple token match" {
  // Create a simple spec with one token and one rule
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[@types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "start": @types.RuleDef::new("start", "IDENT") },
  )
  let peg = build_peg(spec)
  let tokens = [@types.Tok::new("IDENT", "foo", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 1)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: sequence match" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("NUMBER", "[0-9]+"),
    ],
    rules={ "start": @types.RuleDef::new("start", "IDENT NUMBER") },
  )
  let peg = build_peg(spec)
  let tokens = [
    @types.Tok::new("IDENT", "foo", 0),
    @types.Tok::new("NUMBER", "42", 3),
  ]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 2)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: choice match" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("NUMBER", "[0-9]+"),
    ],
    rules={ "start": @types.RuleDef::new("start", "IDENT | NUMBER") },
  )
  let peg = build_peg(spec)
  // Test with NUMBER
  let tokens = [@types.Tok::new("NUMBER", "42", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 1)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: star repetition" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[@types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "start": @types.RuleDef::new("start", "IDENT*") },
  )
  let peg = build_peg(spec)
  // Test with multiple tokens
  let tokens = [
    @types.Tok::new("IDENT", "foo", 0),
    @types.Tok::new("IDENT", "bar", 3),
    @types.Tok::new("IDENT", "baz", 6),
  ]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 3)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: label capture" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[@types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "start": @types.RuleDef::new("start", "name:IDENT") },
  )
  let peg = build_peg(spec)
  let tokens = [@types.Tok::new("IDENT", "hello", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      match r.labels.get("name") {
        Some(String(s)) => assert_eq(s, "hello")
        _ => fail("Expected name label to be 'hello'")
      }
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: rule reference" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[@types.TokenDef::new("IDENT", "[a-z]+")],
    rules={
      "start": @types.RuleDef::new("start", "ident"),
      "ident": @types.RuleDef::new("ident", "IDENT"),
    },
  )
  let peg = build_peg(spec)
  let tokens = [@types.Tok::new("IDENT", "foo", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 1)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: failure" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("NUMBER", "[0-9]+"),
    ],
    rules={ "start": @types.RuleDef::new("start", "IDENT NUMBER") },
  )
  let peg = build_peg(spec)
  // Only one token, but rule expects two
  let tokens = [@types.Tok::new("IDENT", "foo", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    None => () // Expected failure
    Some(_) => fail("Expected parse failure")
  }
}

// =============================================================================
// PEG Predicate Operators (Ford 2004)
// =============================================================================

///|
test "parse_expr: And predicate" {
  let node = parse_expr("&FOO")
  inspect(node, content="And(Sym(\"FOO\"))")
}

///|
test "parse_expr: Not predicate" {
  let node = parse_expr("!FOO")
  inspect(node, content="Not(Sym(\"FOO\"))")
}

///|
test "parse_expr: slash choice (PEG standard)" {
  let node = parse_expr("FOO / BAR")
  inspect(node, content="Choice([Sym(\"FOO\"), Sym(\"BAR\")])")
}

///|
test "parse_expr: mixed choice operators" {
  // Both | and / should work as choice operators
  let node = parse_expr("FOO | BAR / BAZ")
  inspect(node, content="Choice([Sym(\"FOO\"), Sym(\"BAR\"), Sym(\"BAZ\")])")
}

///|
test "parse_expr: nested And predicate" {
  let node = parse_expr("&(FOO BAR)")
  inspect(node, content="And(Seq([Sym(\"FOO\"), Sym(\"BAR\")]))")
}

///|
test "parse_expr: nested Not predicate" {
  let node = parse_expr("!(FOO | BAR)")
  inspect(node, content="Not(Choice([Sym(\"FOO\"), Sym(\"BAR\")]))")
}

///|
test "parse_expr: double negation (!!e = &e)" {
  // !!e is semantically equivalent to &e but parsed as nested Not
  let node = parse_expr("!!FOO")
  inspect(node, content="Not(Not(Sym(\"FOO\")))")
}

///|
test "parse_expr: predicate in sequence" {
  // Common pattern: identifier that is not a keyword
  let node = parse_expr("!KEYWORD IDENT")
  inspect(node, content="Seq([Not(Sym(\"KEYWORD\")), Sym(\"IDENT\")])")
}

///|
test "parse_expr: And with postfix" {
  // &FOO* - And applies to FOO, then star
  let node = parse_expr("&FOO*")
  inspect(node, content="Star(And(Sym(\"FOO\")))")
}

///|
test "parse_expr: complex predicate pattern" {
  // EndOfFile pattern: !. (not any character)
  // In KGF, terminals are in lex, so we use a token name
  let node = parse_expr("!ANY")
  inspect(node, content="Not(Sym(\"ANY\"))")
}

///|
test "run_parse: And predicate success without consuming" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[@types.TokenDef::new("IDENT", "[a-z]+")],
    rules={ "start": @types.RuleDef::new("start", "&IDENT IDENT") },
  )
  let peg = build_peg(spec)
  let tokens = [@types.Tok::new("IDENT", "foo", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      // &IDENT succeeds without consuming, then IDENT consumes
      assert_eq(r.pos, 1)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: And predicate failure" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("NUMBER", "[0-9]+"),
    ],
    rules={ "start": @types.RuleDef::new("start", "&IDENT NUMBER") },
  )
  let peg = build_peg(spec)
  // Token is NUMBER, but &IDENT expects IDENT
  let tokens = [@types.Tok::new("NUMBER", "123", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    None => () // Expected: &IDENT fails because token is NUMBER
    Some(_) => fail("Expected parse failure")
  }
}

///|
test "run_parse: Not predicate success" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("KEYWORD", "if|else|while"),
    ],
    rules={ "start": @types.RuleDef::new("start", "!KEYWORD IDENT") },
  )
  let peg = build_peg(spec)
  // Token is IDENT (not KEYWORD), so !KEYWORD succeeds
  let tokens = [@types.Tok::new("IDENT", "foo", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    Some(r) => {
      assert_true(r.ok)
      assert_eq(r.pos, 1)
    }
    None => fail("Expected successful parse")
  }
}

///|
test "run_parse: Not predicate failure" {
  let spec = @types.KGFSpec::new(
    "test",
    tokens=[
      @types.TokenDef::new("IDENT", "[a-z]+"),
      @types.TokenDef::new("KEYWORD", "if|else|while"),
    ],
    rules={ "start": @types.RuleDef::new("start", "!KEYWORD IDENT") },
  )
  let peg = build_peg(spec)
  // Token is KEYWORD, so !KEYWORD fails
  let tokens = [@types.Tok::new("KEYWORD", "if", 0)]
  let result = run_parse(peg, spec, "start", tokens)
  match result {
    None => () // Expected: !KEYWORD fails because token is KEYWORD
    Some(_) => fail("Expected parse failure")
  }
}

// =============================================================================
// Deprecation Warnings
// =============================================================================

///|
test "parse_expr_with_warnings: bar operator deprecated" {
  let (node, warnings) = parse_expr_with_warnings("FOO | BAR")
  inspect(node, content="Choice([Sym(\"FOO\"), Sym(\"BAR\")])")
  assert_eq(warnings.length(), 1)
  assert_true(warnings[0].contains("deprecated"))
  assert_true(warnings[0].contains("|"))
}

///|
test "parse_expr_with_warnings: bracket optional deprecated" {
  let (node, warnings) = parse_expr_with_warnings("[FOO]")
  inspect(node, content="Optional(Sym(\"FOO\"))")
  assert_eq(warnings.length(), 1)
  assert_true(warnings[0].contains("deprecated"))
  assert_true(warnings[0].contains("[e]"))
}

///|
test "parse_expr_with_warnings: slash no warning" {
  let (node, warnings) = parse_expr_with_warnings("FOO / BAR")
  inspect(node, content="Choice([Sym(\"FOO\"), Sym(\"BAR\")])")
  assert_eq(warnings.length(), 0)
}

///|
test "parse_expr_with_warnings: question mark no warning" {
  let (node, warnings) = parse_expr_with_warnings("FOO?")
  inspect(node, content="Optional(Sym(\"FOO\"))")
  assert_eq(warnings.length(), 0)
}
