///|
/// Integration tests for KGF: parse_kgf -> build_peg -> Lexer::new -> tokenize -> run_parse
/// Tests the complete parsing pipeline from KGF specification to parsed results.

///|
/// Simple assignment language spec for integration testing.
/// Grammar: Program -> Statement*, Statement -> IDENT EQUALS NUMBER SEMI
fn simple_assignment_kgf() -> String {
  let text =
    #|language: test
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN NUMBER /[0-9]+/
    #|TOKEN EQUALS /=/
    #|TOKEN SEMI /;/
    #|
    #|=== grammar
    #|Program -> Statement*
    #|Statement -> IDENT EQUALS NUMBER SEMI
    #|
    #|=== attrs
    #|on Statement: def id=name kind=Variable
    #|
  text
}

///|
test "integration: simple assignment parsing" {
  // Parse the KGF spec
  let spec = @spec.parse_kgf(simple_assignment_kgf())
  assert_true(spec is Some(_))
  let spec = spec.unwrap()

  // Verify spec parsed correctly
  assert_eq(spec.get_language(), "test")
  assert_eq(spec.get_tokens().length(), 5) // SKIP + 4 tokens
  assert_eq(spec.get_rules().length(), 2) // Program and Statement

  // Build PEG from spec
  let peg = build_peg(spec)

  // Create lexer from token definitions
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Tokenize the source code
  let source = "x = 42;"
  let tokens = lexer.tokenize(source)

  // Verify tokenization
  assert_eq(tokens.length(), 4) // IDENT, EQUALS, NUMBER, SEMI
  assert_eq(tokens[0].kind, "IDENT")
  assert_eq(tokens[0].text, "x")
  assert_eq(tokens[1].kind, "EQUALS")
  assert_eq(tokens[2].kind, "NUMBER")
  assert_eq(tokens[2].text, "42")
  assert_eq(tokens[3].kind, "SEMI")

  // Run PEG parse
  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)
  assert_eq(result.pos, 4) // All tokens consumed
}

///|
test "integration: multiple statements" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "x = 1; y = 2; z = 3;"
  let tokens = lexer.tokenize(source)

  // 3 statements * 4 tokens each = 12 tokens
  assert_eq(tokens.length(), 12)

  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)
  assert_eq(result.pos, 12)
}

///|
test "integration: empty program" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = ""
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 0)

  // Empty program should still parse (Statement* matches zero times)
  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)
  assert_eq(result.pos, 0)
}

///|
test "integration: whitespace handling" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "  x   =   42  ;  "
  let tokens = lexer.tokenize(source)

  // Whitespace should be skipped, only meaningful tokens
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].text, "x")
  assert_eq(tokens[2].text, "42")

  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Expression language spec with operators and precedence.
fn expression_kgf() -> String {
  let text =
    #|language: expr
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN NUMBER /[0-9]+/
    #|TOKEN PLUS /\+/
    #|TOKEN MINUS /-/
    #|TOKEN STAR /\*/
    #|TOKEN SLASH /\//
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|
    #|=== grammar
    #|Expr -> Term ((PLUS | MINUS) Term)*
    #|Term -> Factor ((STAR | SLASH) Factor)*
    #|Factor -> NUMBER | LPAREN Expr RPAREN
    #|
  text
}

///|
test "integration: expression parsing" {
  let spec = @spec.parse_kgf(expression_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "1 + 2 * 3"
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 5) // NUMBER PLUS NUMBER STAR NUMBER

  let result = run_parse(peg, spec, "Expr", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: nested expressions with parentheses" {
  let spec = @spec.parse_kgf(expression_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "(1 + 2) * (3 - 4)"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Expr", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Language spec with labeled captures.
fn labeled_kgf() -> String {
  let text =
    #|language: labeled
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN NUMBER /[0-9]+/
    #|TOKEN COLON /:/
    #|
    #|=== grammar
    #|Decl -> name:IDENT COLON type:IDENT
    #|
  text
}

///|
test "integration: labeled captures" {
  let spec = @spec.parse_kgf(labeled_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "myVar : int"
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 3)

  let result = run_parse(peg, spec, "Decl", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)

  // Check labeled captures
  let labels = result.labels
  match labels.get("name") {
    Some(String(s)) => assert_eq(s, "myVar")
    _ => fail("Expected name label")
  }
  match labels.get("type") {
    Some(String(s)) => assert_eq(s, "int")
    _ => fail("Expected type label")
  }
}

///|
/// Language spec with optional elements.
fn optional_kgf() -> String {
  let text =
    #|language: optional
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN NUMBER /[0-9]+/
    #|TOKEN EQUALS /=/
    #|TOKEN SEMI /;/
    #|
    #|=== grammar
    #|Decl -> name:IDENT (EQUALS init:NUMBER)? SEMI
    #|
  text
}

///|
test "integration: optional elements - with value" {
  let spec = @spec.parse_kgf(optional_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "x = 42 ;"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Decl", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)

  // Both name and init should be captured
  match result.labels.get("name") {
    Some(String(s)) => assert_eq(s, "x")
    _ => fail("Expected name label")
  }
  match result.labels.get("init") {
    Some(String(s)) => assert_eq(s, "42")
    _ => fail("Expected init label")
  }
}

///|
test "integration: optional elements - without value" {
  let spec = @spec.parse_kgf(optional_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "x ;"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Decl", tokens)
  assert_true(result is Some(_))
  let result = result.unwrap()
  assert_true(result.ok)

  // name should be captured, init should not
  match result.labels.get("name") {
    Some(String(s)) => assert_eq(s, "x")
    _ => fail("Expected name label")
  }
}

///|
/// Language spec with choice alternatives.
fn choice_kgf() -> String {
  let text =
    #|language: choice
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN NUMBER /[0-9]+/
    #|TOKEN STRING /"[^"]*"/
    #|
    #|=== grammar
    #|Value -> NUMBER | STRING | IDENT
    #|
  text
}

///|
test "integration: choice - number" {
  let spec = @spec.parse_kgf(choice_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "42"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Value", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: choice - string" {
  let spec = @spec.parse_kgf(choice_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "\"hello\""
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Value", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: choice - identifier" {
  let spec = @spec.parse_kgf(choice_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "myVar"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Value", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Tests parse failures for invalid input.
test "integration: parse failure - incomplete statement" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Missing semicolon
  let source = "x = 42"
  let tokens = lexer.tokenize(source)

  // Statement rule expects SEMI at end
  let result = run_parse(peg, spec, "Statement", tokens)
  assert_true(result is None)
}

///|
test "integration: parse failure - wrong token order" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Number before identifier
  let source = "42 = x ;"
  let tokens = lexer.tokenize(source)

  // Statement expects IDENT first
  let result = run_parse(peg, spec, "Statement", tokens)
  assert_true(result is None)
}

///|
test "integration: parse failure - mismatched parentheses" {
  let spec = @spec.parse_kgf(expression_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Missing closing paren
  let source = "(1 + 2"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Expr", tokens)
  // Should fail because RPAREN is missing
  assert_true(result is None)
}

///|
/// Language spec with one-or-more repetition (plus).
fn plus_kgf() -> String {
  let text =
    #|language: plus
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN DOT /\./
    #|
    #|=== grammar
    #|QualifiedName -> IDENT (DOT IDENT)+
    #|
  text
}

///|
test "integration: plus repetition - success" {
  let spec = @spec.parse_kgf(plus_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "a.b.c"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "QualifiedName", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: plus repetition - failure (no dots)" {
  let spec = @spec.parse_kgf(plus_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Just a single identifier, but rule requires at least one DOT IDENT
  let source = "a"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "QualifiedName", tokens)
  // Should fail because plus requires at least one match
  assert_true(result is None)
}

///|
/// Case-insensitive token matching test.
fn case_insensitive_kgf() -> String {
  let text =
    #|language: case
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN KW_SELECT /select/i
    #|TOKEN KW_FROM /from/i
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Query -> KW_SELECT IDENT KW_FROM IDENT
    #|
  text
}

///|
test "integration: case insensitive tokens" {
  let spec = @spec.parse_kgf(case_insensitive_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Mixed case keywords
  let source = "SELECT name FROM users"
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].kind, "KW_SELECT")
  assert_eq(tokens[2].kind, "KW_FROM")

  let result = run_parse(peg, spec, "Query", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: case insensitive lowercase" {
  let spec = @spec.parse_kgf(case_insensitive_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "select name from users"
  let tokens = lexer.tokenize(source)

  assert_eq(tokens[0].kind, "KW_SELECT")
  assert_eq(tokens[2].kind, "KW_FROM")

  let result = run_parse(peg, spec, "Query", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Complex nested rule references.
fn nested_rules_kgf() -> String {
  let text =
    #|language: nested
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN COLON /:/
    #|TOKEN COMMA /,/
    #|
    #|=== grammar
    #|Object -> LBRACE (Pair (COMMA Pair)*)? RBRACE
    #|Pair -> key:IDENT COLON value:Value
    #|Value -> IDENT | Object
    #|
  text
}

///|
test "integration: nested objects" {
  let spec = @spec.parse_kgf(nested_rules_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "{ a : { b : c } }"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Object", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: multiple pairs" {
  let spec = @spec.parse_kgf(nested_rules_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "{ a : x , b : y , c : z }"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Object", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: empty object" {
  let spec = @spec.parse_kgf(nested_rules_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "{ }"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Object", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Test position tracking in tokens.
test "integration: token position tracking" {
  let spec = @spec.parse_kgf(simple_assignment_kgf()).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "x = 42 ;"
  let tokens = lexer.tokenize(source)

  // x starts at position 0
  assert_eq(tokens[0].pos, 0)
  // = starts at position 2 (after "x ")
  assert_eq(tokens[1].pos, 2)
  // 42 starts at position 4 (after "x = ")
  assert_eq(tokens[2].pos, 4)
  // ; starts at position 7 (after "x = 42 ")
  assert_eq(tokens[3].pos, 7)
}

///|
/// Test string token with value extraction.
fn string_value_kgf() -> String {
  let text =
    #|language: stringval
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN STRING /"[^"]*"/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Lit -> val:STRING | IDENT
    #|
  text
}

///|
test "integration: string value extraction" {
  let spec = @spec.parse_kgf(string_value_kgf()).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "\"hello world\""
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].kind, "STRING")
  assert_eq(tokens[0].text, "\"hello world\"")
  // get_value should strip quotes
  assert_eq(tokens[0].get_value(), "hello world")
}

///|
/// Test with resolver section parsing.
fn resolver_kgf() -> String {
  let text =
    #|language: resolver_test
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Program -> IDENT*
    #|
    #|=== resolver
    #|sources: src, lib
    #|exts: .ts, .js
    #|module_path_style: slash
    #|bare_prefix: @
    #|
  text
}

///|
test "integration: resolver section parsing" {
  let spec = @spec.parse_kgf(resolver_kgf()).unwrap()

  let resolver = spec.get_resolver()
  assert_eq(resolver.get_sources().length(), 2)
  assert_eq(resolver.get_sources()[0], "src")
  assert_eq(resolver.get_sources()[1], "lib")
  assert_eq(resolver.get_exts().length(), 2)
  assert_eq(resolver.get_module_path_style().as_string(), "slash")
  assert_eq(resolver.get_bare_prefix(), "@")
}

///|
/// Test with attrs section parsing.
fn attrs_kgf() -> String {
  let text =
    #|language: attrs_test
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN KW_DEF /def/
    #|TOKEN KW_REF /ref/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Program -> (FuncDef | VarRef)*
    #|FuncDef -> KW_DEF name:IDENT
    #|VarRef -> KW_REF name:IDENT
    #|
    #|=== attrs
    #|on FuncDef: def name kind=Function
    #|on VarRef: ref name
    #|
  text
}

///|
test "integration: attrs section parsing" {
  let spec = @spec.parse_kgf(attrs_kgf()).unwrap()

  let attrs = spec.get_attrs()
  assert_eq(attrs.length(), 2)

  let func_def_attrs = attrs.get("FuncDef").unwrap()
  assert_eq(func_def_attrs.length(), 1)
  assert_eq(func_def_attrs[0].get_kind(), "def")

  let var_ref_attrs = attrs.get("VarRef").unwrap()
  assert_eq(var_ref_attrs.length(), 1)
  assert_eq(var_ref_attrs[0].get_kind(), "ref")
}

///|
test "integration: attrs parsing with program" {
  let spec = @spec.parse_kgf(attrs_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  let source = "def myFunc ref myVar"
  let tokens = lexer.tokenize(source)

  assert_eq(tokens.length(), 4)

  let result = run_parse(peg, spec, "Program", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Comment handling in KGF spec.
fn comments_kgf() -> String {
  let text =
    #|language: comments_test
    #|
    #|=== lex
    #|# This is a comment in lex section
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|# Comment in grammar section
    #|Program -> IDENT*
    #|
  text
}

///|
test "integration: comments in kgf spec" {
  let spec = @spec.parse_kgf(comments_kgf()).unwrap()

  // Comments should be ignored
  assert_eq(spec.get_language(), "comments_test")
  assert_eq(spec.get_tokens().length(), 2) // SKIP and IDENT only
  assert_eq(spec.get_rules().length(), 1) // Program only
}

///|
/// Multiline rule continuation.
fn multiline_rule_kgf() -> String {
  let text =
    #|language: multiline
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN COMMA /,/
    #|
    #|=== grammar
    #|Call -> IDENT LPAREN
    #|        (IDENT (COMMA IDENT)*)?
    #|        RPAREN
    #|
  text
}

///|
test "integration: multiline rule definition" {
  let spec = @spec.parse_kgf(multiline_rule_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Function call with arguments
  let source = "func ( a , b , c )"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Call", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
test "integration: multiline rule empty args" {
  let spec = @spec.parse_kgf(multiline_rule_kgf()).unwrap()
  let peg = build_peg(spec)
  let lexer = @lexer.Lexer::new(spec.get_tokens())

  // Function call without arguments
  let source = "func ( )"
  let tokens = lexer.tokenize(source)

  let result = run_parse(peg, spec, "Call", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}
