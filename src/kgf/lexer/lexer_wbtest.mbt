///|
test "lexer: basic tokenization" {
  let lex = lexer()
    .token("NUMBER", "\\d+")
    .token("IDENT", "[a-zA-Z_][a-zA-Z0-9_]*")
    .skip("WS", "\\s+")
    .build()
  let tokens = lex.tokenize("foo 123 bar")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0].kind, "IDENT")
  assert_eq(tokens[0].text, "foo")
  assert_eq(tokens[1].kind, "NUMBER")
  assert_eq(tokens[1].text, "123")
  assert_eq(tokens[2].kind, "IDENT")
  assert_eq(tokens[2].text, "bar")
}

///|
test "lexer: string literal with quotes" {
  let lex = lexer().token("STRING", "\"[^\"]*\"").skip("WS", "\\s+").build()
  let tokens = lex.tokenize("\"hello world\"")
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].kind, "STRING")
  assert_eq(tokens[0].text, "\"hello world\"")
  assert_eq(tokens[0].get_value(), "hello world")
}

///|
test "lexer: operators and punctuation" {
  let lex = lexer()
    .token("PLUS", "\\+")
    .token("MINUS", "-")
    .token("STAR", "\\*")
    .token("NUMBER", "\\d+")
    .skip("WS", "\\s+")
    .build()
  let tokens = lex.tokenize("1 + 2 - 3 * 4")
  assert_eq(tokens.length(), 7)
  assert_eq(tokens[0].kind, "NUMBER")
  assert_eq(tokens[1].kind, "PLUS")
  assert_eq(tokens[2].kind, "NUMBER")
  assert_eq(tokens[3].kind, "MINUS")
  assert_eq(tokens[4].kind, "NUMBER")
  assert_eq(tokens[5].kind, "STAR")
  assert_eq(tokens[6].kind, "NUMBER")
}

///|
test "lexer: position tracking" {
  let lex = lexer().token("WORD", "\\w+").skip("WS", "\\s+").build()
  let tokens = lex.tokenize("hello world")
  assert_eq(tokens.length(), 2)
  assert_eq(tokens[0].pos, 0)
  assert_eq(tokens[1].pos, 6)
}

///|
test "lexer: empty input" {
  let lex = lexer().token("WORD", "\\w+").build()
  let tokens = lex.tokenize("")
  assert_eq(tokens.length(), 0)
}

///|
test "lexer: priority order" {
  // Keywords should be matched before identifiers
  let lex = lexer()
    .token("IF", "if")
    .token("ELSE", "else")
    .token("IDENT", "[a-zA-Z_][a-zA-Z0-9_]*")
    .skip("WS", "\\s+")
    .build()
  let tokens = lex.tokenize("if foo else bar")
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].kind, "IF")
  assert_eq(tokens[1].kind, "IDENT")
  assert_eq(tokens[2].kind, "ELSE")
  assert_eq(tokens[3].kind, "IDENT")
}

///|
test "lexer: typescript-style string literal pattern" {
  // TypeScript string pattern: "([^"\\]|\\.)*" or '([^'\\]|\\.)*'
  // We test a simpler but equivalent pattern structure
  let lex = lexer()
    .token("STRING", "\"[^\"]*\"")
    .token("IDENT", "[a-zA-Z]+")
    .skip("WS", "\\s+")
    .build()
  let tokens = lex.tokenize("foo \"hello world\" bar")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0].kind, "IDENT")
  assert_eq(tokens[1].kind, "STRING")
  assert_eq(tokens[1].text, "\"hello world\"")
  assert_eq(tokens[2].kind, "IDENT")
}

///|
test "lexer: keyword with word boundary takes priority" {
  // Create lexer with keyword using \b and identifier
  let lex = lexer()
    .skip("WS", "\\s+")
    .token("KW_import", "import\\b")
    .token("Ident", "[a-zA-Z_][a-zA-Z0-9_]*")
    .build()

  // "import" should be recognized as keyword
  let tokens1 = lex.tokenize("import foo")
  assert_eq(tokens1[0].kind, "KW_import")
  assert_eq(tokens1[0].text, "import")
  assert_eq(tokens1[1].kind, "Ident")
  assert_eq(tokens1[1].text, "foo")

  // "importing" should be recognized as identifier, not keyword + partial
  let tokens2 = lex.tokenize("importing")
  assert_eq(tokens2[0].kind, "Ident")
  assert_eq(tokens2[0].text, "importing")
}

///|
test "lexer: typescript-style tokens" {
  // Test token definitions similar to those in typescript.kgf
  let lex = lexer()
    .token("KW_import", "import")
    .token("KW_from", "from")
    .token("Ident", "[A-Za-z_\\$][A-Za-z0-9_\\$]*")
    .token("StringLit", "\"[^\"]*\"")
    .token("LBRACE", "\\{")
    .token("RBRACE", "\\}")
    .token("SEMI", ";")
    .token("COMMA", ",")
    .skip("WS", "\\s+")
    .build()
  let code = "import { foo, bar } from \"module\";"
  let tokens = lex.tokenize(code)
  assert_eq(tokens[0].kind, "KW_import")
  assert_eq(tokens[1].kind, "LBRACE")
  assert_eq(tokens[2].kind, "Ident")
  assert_eq(tokens[2].text, "foo")
  assert_eq(tokens[3].kind, "COMMA")
  assert_eq(tokens[4].kind, "Ident")
  assert_eq(tokens[4].text, "bar")
  assert_eq(tokens[5].kind, "RBRACE")
  assert_eq(tokens[6].kind, "KW_from")
  assert_eq(tokens[7].kind, "StringLit")
  assert_eq(tokens[8].kind, "SEMI")
}

///|
test "capture_group: line doc comment /// extracts content" {
  let lexer = Lexer::new([
    @types.TokenDef::new("DocComment", "\\/\\/\\/(.*)"),
    @types.TokenDef::new("NL", "\\r?\\n"),
  ])
  let tokens = lexer.tokenize("/// Hello world\n")
  assert_eq(tokens[0].get_kind(), "DocComment")
  assert_eq(tokens[0].get_text(), "/// Hello world")
  assert_eq(tokens[0].get_value(), " Hello world")
}

///|
test "capture_group: block doc comment /** */ extracts content" {
  // Verify non-capture version works first
  let lexer_nc = Lexer::new([
    @types.TokenDef::new("DocComment", "\\/\\*\\*[\\s\\S]*?\\*\\/"),
  ])
  let tokens_nc = lexer_nc.tokenize("/** Hello */")
  assert_true(tokens_nc.length() > 0) // BASELINE: does this match at all?
  // Now test with capture group
  let lexer = Lexer::new([
    @types.TokenDef::new("DocComment", "\\/\\*\\*([\\s\\S]*?)\\*\\/"),
  ])
  let tokens = lexer.tokenize("/** Hello */")
  assert_true(tokens.length() > 0)
  if tokens.length() > 0 {
    assert_eq(tokens[0].get_kind(), "DocComment")
    assert_eq(tokens[0].get_text(), "/** Hello */")
    assert_eq(tokens[0].get_value(), " Hello ")
  }
}

///|
test "capture_group: multi-line block doc captures inner content" {
  let lexer = Lexer::new([
    @types.TokenDef::new("DocComment", "\\/\\*\\*([\\s\\S]*?)\\*\\/"),
    @types.TokenDef::new("NL", "\\r?\\n"),
  ])
  let input = "/**\n * Line one\n * Line two\n */"
  let tokens = lexer.tokenize(input)
  assert_true(tokens.length() > 0)
  if tokens.length() > 0 {
    assert_eq(tokens[0].get_kind(), "DocComment")
    let value = tokens[0].get_value()
    assert_true(value.contains("Line one"))
    assert_true(value.contains("Line two"))
  }
}

///|
test "capture_group: non-capturing group (?:) does not affect value" {
  let lexer = Lexer::new([
    @types.TokenDef::new("Keyword", "(?:let|var|const)"),
    @types.TokenDef::new("Ident", "[a-zA-Z]+"),
  ])
  let tokens = lexer.tokenize("let")
  assert_eq(tokens[0].get_kind(), "Keyword")
  assert_eq(tokens[0].get_text(), "let")
  // No capture group → value falls back to text
  assert_eq(tokens[0].get_value(), "let")
}

///|
test "capture_group: skip_value takes precedence over capture" {
  let lexer = Lexer::new([
    @types.TokenDef::new("Marker", "\\/\\/\\/\\|[^\\r\\n]*", skip_value=true),
    @types.TokenDef::new("NL", "\\r?\\n"),
  ])
  let tokens = lexer.tokenize("///| start\n")
  assert_eq(tokens[0].get_kind(), "Marker")
  assert_eq(tokens[0].get_value(), "")
}

///|
test "capture_group: lua doc comment --- extracts content" {
  let lexer = Lexer::new([@types.TokenDef::new("DocComment", "---(.*)")])
  let tokens = lexer.tokenize("--- This is a Lua doc")
  assert_eq(tokens[0].get_kind(), "DocComment")
  assert_eq(tokens[0].get_value(), " This is a Lua doc")
}

///|
test "capture_group: capturing group with alternation (a|b)" {
  let lexer = Lexer::new([
    @types.TokenDef::new("Doc", "\\/\\/\\/(.*)|---(.*)"),
    @types.TokenDef::new("NL", "\\r?\\n"),
  ])
  let tokens = lexer.tokenize("/// hello\n")
  assert_eq(tokens[0].get_kind(), "Doc")
  assert_eq(tokens[0].get_value(), " hello")
}
