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
test "pattern_matcher: find_pattern_captures returns groups" {
  let matches = find_pattern_captures("(foo)=(\\d+)", "foo=10\nfoo=20")
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].text, "foo=10")
  assert_eq(matches[0].captures, ["foo", "10"])
  assert_eq(matches[1].captures, ["foo", "20"])
}

///|
test "pattern_matcher: find_pattern_captures supports case insensitive" {
  let matches = find_pattern_captures(
    "(reserved)",
    "RESERVED reserved",
    case_insensitive=true,
  )
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].captures[0], "RESERVED")
  assert_eq(matches[1].captures[0], "reserved")
}

///|
test "pattern_matcher: capture literals from normative lines" {
  let content = "## Timeout\nThe value MUST be `36`.\nFor example, `99` is shown.\nThe response SHALL return `200`.\n"
  let numeric = find_pattern_captures(
    "^(?![^\\n]*(?:for example|e\\.g\\.|suppose|consider ))[^\\n]*(?:\\bmust\\b|\\bshall\\b|\\bshould\\b|\\brequired\\b|=|\\|)[^\\n]*\\b([0-9]{1,})\\b",
    content,
    case_insensitive=true,
  )
  let quoted = find_pattern_captures(
    "^(?![^\\n]*(?:for example|e\\.g\\.|suppose|consider ))[^\\n]*(?:\\bmust\\b|\\bshall\\b|\\bshould\\b|\\brequired\\b|=|\\|)[^\\n]*`([^`\\n]+)`",
    content,
    case_insensitive=true,
  )
  assert_eq(numeric.map(fn(m) { m.captures[0] }), ["36", "200"])
  assert_eq(quoted.map(fn(m) { m.captures[0] }), ["36", "200"])
}

///|
test "pattern_matcher: capture section refs and pipe table pairs" {
  let content = "6. CHIMP Specification\nSee sections 6.1 and 6.2.\n| 7 | REQUEST_STOP |\n"
  let refs1 = find_pattern_captures(
    "^((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?[ \\t]",
    content,
    case_insensitive=true,
  )
  let refs2 = find_pattern_captures(
    "\\bsections?\\s+((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?\\b",
    content,
    case_insensitive=true,
  )
  let refs3 = find_pattern_captures(
    "\\b(?:and|or)\\s+((?:[A-Z]|\\d+(?:\\.\\d+)*))\\.?\\b",
    content,
    case_insensitive=true,
  )
  let pairs = find_pattern_captures(
    "\\|\\s*([0-9]+(?:\\.[0-9]+)*)\\s*\\|\\s*([A-Za-z][A-Za-z0-9 /'_-]*[A-Za-z0-9/_-])\\s*\\|",
    content,
  )
  assert_eq(refs1.map(fn(m) { m.captures[0] }), ["6"])
  assert_eq(refs2.map(fn(m) { m.captures[0] }), ["6.1"])
  assert_eq(refs3.map(fn(m) { m.captures[0] }), ["6.2"])
  assert_eq(pairs.length(), 1)
  assert_eq(pairs[0].captures, ["7", "REQUEST_STOP"])
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
