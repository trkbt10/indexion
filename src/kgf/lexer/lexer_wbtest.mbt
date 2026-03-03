///|
test "pattern_matcher: literal matching" {
  let result = match_pattern("hello", "hello world", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "hello")
  assert_eq(result.end_pos, 5)
}

///|
test "pattern_matcher: literal no match" {
  let result = match_pattern("hello", "world", 0)
  assert_eq(result.matched, false)
}

///|
test "pattern_matcher: digit class \\d+" {
  let result = match_pattern("\\d+", "123abc", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "123")
}

///|
test "pattern_matcher: word class \\w+" {
  let result = match_pattern("\\w+", "hello_world123 test", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "hello_world123")
}

///|
test "pattern_matcher: whitespace \\s+" {
  let result = match_pattern("\\s+", "   hello", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "   ")
}

///|
test "pattern_matcher: character class [a-z]+" {
  let result = match_pattern("[a-z]+", "hello123", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "hello")
}

///|
test "pattern_matcher: character class [0-9]+" {
  let result = match_pattern("[0-9]+", "12345abc", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "12345")
}

///|
test "pattern_matcher: negated character class [^a-z]+" {
  let result = match_pattern("[^a-z]+", "123ABC", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "123ABC")
}

///|
test "pattern_matcher: any char .+" {
  let result = match_pattern(".+", "hello\nworld", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "hello")
}

///|
test "pattern_matcher: optional quantifier \\d?" {
  let result = match_pattern("\\d?", "abc", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "")
}

///|
test "pattern_matcher: group (ab)+" {
  let result = match_pattern("(ab)+", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
}

///|
test "pattern_matcher: alternation a|b" {
  let result1 = match_pattern("a|b", "a", 0)
  assert_eq(result1.matched, true)
  assert_eq(result1.text, "a")
  let result2 = match_pattern("a|b", "b", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "b")
}

///|
test "pattern_matcher: complex pattern [a-zA-Z_][a-zA-Z0-9_]*" {
  let result = match_pattern("[a-zA-Z_][a-zA-Z0-9_]*", "myVar123_test", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "myVar123_test")
}

///|
test "pattern_matcher: case insensitive" {
  let result = match_pattern("hello", "HELLO", 0, case_insensitive=true)
  assert_eq(result.matched, true)
  assert_eq(result.text, "HELLO")
}

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
test "pattern_matcher: alternation inside group - no infinite recursion" {
  // Pattern like "([^"\\]|\\.)*" has | inside group, should not cause infinite recursion
  let result = match_pattern("([ab]|c)+", "abcabc", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "abcabc")
}

///|
test "pattern_matcher: complex alternation in group" {
  // Test pattern similar to TypeScript string literal: "([^"\\]|\\.)*"
  // Simplified version without escape sequences
  let result = match_pattern("([^x]|xy)+", "abxyab", 0)
  assert_eq(result.matched, true)
}

///|
test "pattern_matcher: nested groups with alternation" {
  // Pattern with nested structures
  let result = match_pattern("(a(b|c)d)+", "abdacd", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "abdacd")
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
