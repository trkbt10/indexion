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
test "pattern_matcher: non-capturing group (?:...)" {
  // Non-capturing groups should work like regular groups
  let result = match_pattern("(?:ab)+", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
  // With alternation inside non-capturing group
  let result2 = match_pattern("(?:a|b)+", "abba", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "abba")
  // Simple number pattern
  let result3 = match_pattern("[1-9][0-9]*", "123", 0)
  assert_eq(result3.matched, true)
  assert_eq(result3.text, "123")
  // Number pattern with non-capturing group alternation
  let result4 = match_pattern("(?:0|[1-9][0-9]*)", "123", 0)
  assert_eq(result4.matched, true)
  assert_eq(result4.text, "123")
  // Full TypeScript NumberLit pattern
  let result5 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "123.456", 0)
  assert_eq(result5.matched, true)
  assert_eq(result5.text, "123.456")
  // Without decimal part
  let result6 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "42", 0)
  assert_eq(result6.matched, true)
  assert_eq(result6.text, "42")
  // Zero
  let result7 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "0.5", 0)
  assert_eq(result7.matched, true)
  assert_eq(result7.text, "0.5")
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
test "pattern_matcher: word boundary \\b at start" {
  // Pattern "import\b" should match "import" at word boundary
  let result = match_pattern("import\\b", "import foo", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "import")
}

///|
test "pattern_matcher: word boundary \\b prevents partial match" {
  // Pattern "import\b" should NOT match "importing" (no word boundary after "import")
  let result = match_pattern("import\\b", "importing", 0)
  assert_eq(result.matched, false)
}

///|
test "pattern_matcher: word boundary \\b at end of string" {
  // Pattern "test\b" should match "test" at end of string
  let result = match_pattern("test\\b", "test", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "test")
}

///|
test "pattern_matcher: word boundary \\b with punctuation" {
  // Pattern "foo\b" should match "foo" when followed by punctuation
  let result = match_pattern("foo\\b", "foo()", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "foo")
}

///|
test "pattern_matcher: non-word boundary \\B" {
  // Pattern "port\B" should match "port" when NOT at word boundary
  let result = match_pattern("port\\B", "importing", 2)
  assert_eq(result.matched, true)
  assert_eq(result.text, "port")
}

///|
test "pattern_matcher: non-word boundary \\B fails at boundary" {
  // Pattern "port\B" should NOT match "port" at word boundary
  let result = match_pattern("port\\B", "import foo", 2)
  assert_eq(result.matched, false)
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
test "pattern_matcher: exactly n quantifier {n}" {
  // Match exactly 3 digits
  let result = match_pattern("\\d{3}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "123")
  // Not enough digits
  let result2 = match_pattern("\\d{3}", "12", 0)
  assert_eq(result2.matched, false)
}

///|
test "pattern_matcher: at least n quantifier {n,}" {
  // Match at least 2 digits
  let result = match_pattern("\\d{2,}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "12345")
  // Exactly 2 is OK
  let result2 = match_pattern("\\d{2,}", "12abc", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "12")
  // Only 1 digit - fail
  let result3 = match_pattern("\\d{2,}", "1abc", 0)
  assert_eq(result3.matched, false)
}

///|
test "pattern_matcher: between n and m quantifier {n,m}" {
  // Match 2-4 digits
  let result = match_pattern("\\d{2,4}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "1234")
  // Only 2 digits
  let result2 = match_pattern("\\d{2,4}", "12abc", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "12")
  // Only 1 digit - fail
  let result3 = match_pattern("\\d{2,4}", "1abc", 0)
  assert_eq(result3.matched, false)
}

///|
test "pattern_matcher: start anchor ^" {
  // ^ at start of string
  let result = match_pattern("^hello", "hello world", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "hello")
  // ^ not at start - fails
  let result2 = match_pattern("^hello", "say hello", 4)
  assert_eq(result2.matched, false)
}

///|
test "pattern_matcher: end anchor $" {
  // $ at end of string
  let result = match_pattern("world$", "hello world", 6)
  assert_eq(result.matched, true)
  assert_eq(result.text, "world")
}

///|
test "pattern_matcher: multiline ^ after newline" {
  // ^ should match after newline
  let result = match_pattern("^line2", "line1\nline2", 6)
  assert_eq(result.matched, true)
  assert_eq(result.text, "line2")
}

///|
test "pattern_matcher: multiline $ before newline" {
  // $ should match before newline
  let result = match_pattern("line1$", "line1\nline2", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "line1")
}

///|
test "pattern_matcher: string start \\A" {
  // \A only at absolute start
  let result = match_pattern("\\Ahello", "hello world", 0)
  assert_eq(result.matched, true)
  // \A does NOT match after newline
  let result2 = match_pattern("\\Aline2", "line1\nline2", 6)
  assert_eq(result2.matched, false)
}

///|
test "pattern_matcher: string end \\z" {
  // \z only at absolute end
  let result = match_pattern("world\\z", "hello world", 6)
  assert_eq(result.matched, true)
}

///|
test "pattern_matcher: hex color with {n}" {
  // Common use case: hex color code
  let result = match_pattern("#[0-9a-fA-F]{6}", "#ff00aa", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "#ff00aa")
  // Short hex fails
  let result2 = match_pattern("#[0-9a-fA-F]{6}", "#fff", 0)
  assert_eq(result2.matched, false)
}

///|
test "pattern_matcher: group with {n}" {
  // Repeat group exactly n times
  let result = match_pattern("(ab){3}", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
  // Not enough
  let result2 = match_pattern("(ab){3}", "abab", 0)
  assert_eq(result2.matched, false)
}

///|
test "pattern_matcher: non-greedy quantifier with backtracking" {
  // Non-greedy .*? stops at first match of subsequent element
  let r1 = match_pattern(".*?\\*", "Hello *", 0)
  assert_eq(r1.matched, true)
  assert_eq(r1.text, "Hello *")
  // Non-greedy [\\s\\S]*? works across any character (including whitespace)
  let r2 = match_pattern("[\\s\\S]*?\\*", "Hello *", 0)
  assert_eq(r2.matched, true)
  assert_eq(r2.text, "Hello *")
  // Greedy backtracking: .* followed by a literal still matches
  let r3 = match_pattern(".*\\*", "Hello *", 0)
  assert_eq(r3.matched, true)
  assert_eq(r3.text, "Hello *")
}

///|
test "pattern_matcher: block comment patterns" {
  // JSDoc comment /** ... */
  let r1 = match_pattern("\\/\\*\\*[\\s\\S]*?\\*\\/", "/** Hello */\nexport", 0)
  assert_eq(r1.matched, true)
  assert_eq(r1.text, "/** Hello */")
  // Multi-line block comment
  let r2 = match_pattern(
    "\\/\\*[\\s\\S]*?\\*\\/", "/* line1\nline2 */\ncode", 0,
  )
  assert_eq(r2.matched, true)
  assert_eq(r2.text, "/* line1\nline2 */")
  // Greedy vs non-greedy: picks first closing */
  let r3 = match_pattern("\\/\\*[\\s\\S]*?\\*\\/", "/* a */ /* b */", 0)
  assert_eq(r3.matched, true)
  assert_eq(r3.text, "/* a */")
}

///|
test "pattern_matcher: positive lookahead (?=...)" {
  // url followed by ( - lookahead doesn't consume (
  let r1 = match_pattern("url(?=\\()", "url(foo)", 0)
  assert_eq(r1.matched, true)
  assert_eq(r1.text, "url")
  // Identifier followed by = (ATTR_NAME pattern)
  let r2 = match_pattern("[a-z]+(?=\\s*=)", "name = value", 0)
  assert_eq(r2.matched, true)
  assert_eq(r2.text, "name")
  // Lookahead fails when condition not met
  let r3 = match_pattern("url(?=\\()", "url foo", 0)
  assert_eq(r3.matched, false)
}

///|
test "pattern_matcher: negative lookahead (?!...)" {
  // Match $ not followed by {
  let r1 = match_pattern("\\$(?!\\{)", "$x", 0)
  assert_eq(r1.matched, true)
  assert_eq(r1.text, "$")
  // Negative lookahead fails when condition IS met
  let r2 = match_pattern("\\$(?!\\{)", "${x}", 0)
  assert_eq(r2.matched, false)
  // Negative lookahead in alternation (template literal pattern)
  let r3 = match_pattern("\\$(?!\\{)|\\$\\{[^}]*\\}", "$x ${name}", 0)
  assert_eq(r3.matched, true)
  assert_eq(r3.text, "$")
}

///|
test "pattern_matcher: lookahead in non-capturing group" {
  // Pattern: (?:(?![abc])[a-z])+ — match lowercase letters except a,b,c
  let r1 = match_pattern("(?:(?![abc])[a-z])+", "defgh", 0)
  assert_eq(r1.matched, true)
  assert_eq(r1.text, "defgh")
  // Stops at 'a'
  let r2 = match_pattern("(?:(?![abc])[a-z])+", "deafgh", 0)
  assert_eq(r2.matched, true)
  assert_eq(r2.text, "de")
}

///|
test "pattern_matcher: unicode escape \\uXXXX" {
  // Check: what code point is 東?
  let east = '東'
  inspect(east.to_int(), content="26481") // 0x6771
  // \u6771 should match 東
  let r0 = match_pattern("\\u6771", "東京都", 0)
  inspect(r0.matched, content="true")
  // Single char match in char class
  let r1a = match_pattern("[\\u6771]", "東", 0)
  inspect(r1a.matched, content="true")
  // Unicode range in char class
  let r1 = match_pattern("[\\u4e00-\\u9fff]+", "東京都", 0)
  inspect(r1.matched, content="true")
  inspect(r1.text, content="東京都")
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
