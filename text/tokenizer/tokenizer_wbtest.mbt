// Tests for the tokenizer module.

///|
test "normalize_text converts to lowercase" {
  let result = normalize_text("Hello World")
  assert_eq(result, "hello world")
}

///|
test "normalize_text normalizes whitespace" {
  let result = normalize_text("  hello   world  ")
  assert_eq(result, "hello world")
}

///|
test "normalize_text handles tabs and newlines" {
  let result = normalize_text("hello\t\nworld")
  assert_eq(result, "hello world")
}

///|
test "normalize_text preserves CJK characters" {
  let result = normalize_text("Hello 世界")
  assert_eq(result, "hello 世界")
}

///|
test "extract_word_tokens extracts english words" {
  let tokens = extract_word_tokens("hello world test")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], "hello")
  assert_eq(tokens[1], "world")
  assert_eq(tokens[2], "test")
}

///|
test "extract_word_tokens filters short tokens" {
  let tokens = extract_word_tokens("a to be or not")
  // "a" is too short, others are 2+ chars
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0], "to")
  assert_eq(tokens[1], "be")
  assert_eq(tokens[2], "or")
  assert_eq(tokens[3], "not")
}

///|
test "extract_word_tokens handles mixed text" {
  let tokens = extract_word_tokens("hello世界world")
  // CJK chars break words but are not included in word tokens
  assert_eq(tokens.length(), 2)
  assert_eq(tokens[0], "hello")
  assert_eq(tokens[1], "world")
}

///|
test "extract_word_tokens includes hyphen and underscore" {
  let tokens = extract_word_tokens("hello-world test_case")
  assert_eq(tokens.length(), 2)
  assert_eq(tokens[0], "hello-world")
  assert_eq(tokens[1], "test_case")
}

///|
test "extract_character_bigrams generates bigrams" {
  let bigrams = extract_character_bigrams("abc")
  assert_eq(bigrams.length(), 2)
  assert_eq(bigrams[0], "ab")
  assert_eq(bigrams[1], "bc")
}

///|
test "extract_character_bigrams removes whitespace" {
  let bigrams = extract_character_bigrams("a b c")
  assert_eq(bigrams.length(), 2)
  assert_eq(bigrams[0], "ab")
  assert_eq(bigrams[1], "bc")
}

///|
test "extract_character_bigrams handles single char" {
  let bigrams = extract_character_bigrams("a")
  assert_eq(bigrams.length(), 1)
  assert_eq(bigrams[0], "a")
}

///|
test "extract_character_bigrams handles empty string" {
  let bigrams = extract_character_bigrams("")
  assert_eq(bigrams.length(), 0)
}

///|
test "extract_character_bigrams handles japanese text" {
  let bigrams = extract_character_bigrams("日本語")
  assert_eq(bigrams.length(), 2)
  assert_eq(bigrams[0], "日本")
  assert_eq(bigrams[1], "本語")
}

///|
test "tokenize_for_tfidf combines words and bigrams" {
  let tokens = tokenize_for_tfidf("hello world")
  // Words: hello, world
  // Bigrams: he, el, ll, lo, ow, wo, or, rl, ld (9 bigrams from "helloworld")
  assert_true(tokens.length() > 2)
  // First tokens should be words
  assert_eq(tokens[0], "hello")
  assert_eq(tokens[1], "world")
}

///|
test "tokenize_for_tfidf handles empty string" {
  let tokens = tokenize_for_tfidf("")
  assert_eq(tokens.length(), 0)
}

///|
test "tokenize_for_tfidf handles whitespace only" {
  let tokens = tokenize_for_tfidf("   ")
  assert_eq(tokens.length(), 0)
}

///|
test "tokenize_for_tfidf handles japanese text" {
  let tokens = tokenize_for_tfidf("日本語テスト")
  // No word tokens for pure CJK
  // Bigrams: 日本, 本語, 語テ, テス, スト
  assert_eq(tokens.length(), 5)
  assert_eq(tokens[0], "日本")
  assert_eq(tokens[1], "本語")
}

///|
test "tokenize_for_tfidf handles mixed japanese and english" {
  let tokens = tokenize_for_tfidf("hello 世界")
  // Word: hello
  // Bigrams from "hello世界": he, el, ll, lo, o世, 世界
  assert_true(tokens.length() > 1)
  assert_eq(tokens[0], "hello")
}

///|
test "is_cjk_char detects hiragana" {
  assert_true(is_cjk_char('あ'))
  assert_true(is_cjk_char('ん'))
}

///|
test "is_cjk_char detects katakana" {
  assert_true(is_cjk_char('ア'))
  assert_true(is_cjk_char('ン'))
}

///|
test "is_cjk_char detects kanji" {
  assert_true(is_cjk_char('日'))
  assert_true(is_cjk_char('本'))
}

///|
test "is_cjk_char rejects ascii" {
  assert_eq(is_cjk_char('a'), false)
  assert_eq(is_cjk_char('Z'), false)
  assert_eq(is_cjk_char('0'), false)
}
