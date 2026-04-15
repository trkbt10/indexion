///|
test "parser: group (ab)+" {
  let result = match_pattern("(ab)+", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
}

///|
test "parser: alternation a|b" {
  let result1 = match_pattern("a|b", "a", 0)
  assert_eq(result1.matched, true)
  assert_eq(result1.text, "a")
  let result2 = match_pattern("a|b", "b", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "b")
}

///|
test "parser: alternation inside group - no infinite recursion" {
  let result = match_pattern("([ab]|c)+", "abcabc", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "abcabc")
}

///|
test "parser: complex alternation in group" {
  let result = match_pattern("([^x]|xy)+", "abxyab", 0)
  assert_eq(result.matched, true)
}

///|
test "parser: nested groups with alternation" {
  let result = match_pattern("(a(b|c)d)+", "abdacd", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "abdacd")
}

///|
test "parser: non-capturing group (?:...)" {
  let result = match_pattern("(?:ab)+", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
  let result2 = match_pattern("(?:a|b)+", "abba", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "abba")
  let result3 = match_pattern("[1-9][0-9]*", "123", 0)
  assert_eq(result3.matched, true)
  assert_eq(result3.text, "123")
  let result4 = match_pattern("(?:0|[1-9][0-9]*)", "123", 0)
  assert_eq(result4.matched, true)
  assert_eq(result4.text, "123")
  let result5 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "123.456", 0)
  assert_eq(result5.matched, true)
  assert_eq(result5.text, "123.456")
  let result6 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "42", 0)
  assert_eq(result6.matched, true)
  assert_eq(result6.text, "42")
  let result7 = match_pattern("(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "0.5", 0)
  assert_eq(result7.matched, true)
  assert_eq(result7.text, "0.5")
}

///|
test "parser: exactly n quantifier {n}" {
  let result = match_pattern("\\d{3}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "123")
  let result2 = match_pattern("\\d{3}", "12", 0)
  assert_eq(result2.matched, false)
}

///|
test "parser: at least n quantifier {n,}" {
  let result = match_pattern("\\d{2,}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "12345")
  let result2 = match_pattern("\\d{2,}", "12abc", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "12")
  let result3 = match_pattern("\\d{2,}", "1abc", 0)
  assert_eq(result3.matched, false)
}

///|
test "parser: between n and m quantifier {n,m}" {
  let result = match_pattern("\\d{2,4}", "12345", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "1234")
  let result2 = match_pattern("\\d{2,4}", "12abc", 0)
  assert_eq(result2.matched, true)
  assert_eq(result2.text, "12")
  let result3 = match_pattern("\\d{2,4}", "1abc", 0)
  assert_eq(result3.matched, false)
}

///|
test "parser: hex color with {n}" {
  let result = match_pattern("#[0-9a-fA-F]{6}", "#ff00aa", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "#ff00aa")
  let result2 = match_pattern("#[0-9a-fA-F]{6}", "#fff", 0)
  assert_eq(result2.matched, false)
}

///|
test "parser: group with {n}" {
  let result = match_pattern("(ab){3}", "ababab", 0)
  assert_eq(result.matched, true)
  assert_eq(result.text, "ababab")
  let result2 = match_pattern("(ab){3}", "abab", 0)
  assert_eq(result2.matched, false)
}
