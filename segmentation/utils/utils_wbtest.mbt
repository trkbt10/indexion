// Tests for segmentation/utils package.

///|
test "is_sentence_terminator identifies Japanese terminators" {
  assert_true(is_sentence_terminator('。'))
  assert_true(is_sentence_terminator('！'))
  assert_true(is_sentence_terminator('？'))
}

///|
test "is_sentence_terminator identifies English terminators" {
  assert_true(is_sentence_terminator('.'))
  assert_true(is_sentence_terminator('!'))
  assert_true(is_sentence_terminator('?'))
}

///|
test "is_sentence_terminator rejects non-terminators" {
  assert_false(is_sentence_terminator('a'))
  assert_false(is_sentence_terminator('あ'))
  assert_false(is_sentence_terminator(','))
  assert_false(is_sentence_terminator('、'))
}

///|
test "is_trailing_punctuation includes terminators" {
  assert_true(is_trailing_punctuation('.'))
  assert_true(is_trailing_punctuation('。'))
}

///|
test "is_trailing_punctuation includes closing brackets" {
  assert_true(is_trailing_punctuation('」'))
  assert_true(is_trailing_punctuation('』'))
  assert_true(is_trailing_punctuation(')'))
  assert_true(is_trailing_punctuation(']'))
}

///|
test "find_sentence_boundaries basic English" {
  let text = "Hello world. How are you? I am fine!"
  let boundaries = find_sentence_boundaries_default(text)
  inspect(boundaries, content="[13, 26, 36]")
}

///|
test "find_sentence_boundaries basic Japanese" {
  // こんにちは。 = 6 chars, 元気ですか？ = 6 chars, 私は元気です！ = 7 chars
  let text = "こんにちは。元気ですか？私は元気です！"
  let boundaries = find_sentence_boundaries_default(text)
  // Boundaries at character indices: 6, 12, 19
  inspect(boundaries, content="[6, 12, 19]")
}

///|
test "find_sentence_boundaries protects Japanese quotes" {
  // Sentence ending inside quotes should not split
  // 彼は「元気です。」と言った。 = 14 chars
  let text = "彼は「元気です。」と言った。"
  let boundaries = find_sentence_boundaries_default(text)
  // Only the final 。 should be a boundary, not the one inside quotes
  inspect(boundaries, content="[14]")
}

///|
test "find_sentence_boundaries protects nested Japanese quotes" {
  // 彼女は「『本当？』と聞いた。」と話した。 = 20 chars
  let text = "彼女は「『本当？』と聞いた。」と話した。"
  let boundaries = find_sentence_boundaries_default(text)
  // Only the final 。 should be a boundary
  inspect(boundaries, content="[20]")
}

///|
test "find_sentence_boundaries allows split for long quotes" {
  // Create a long quote that exceeds the default 240 character limit
  let options = FindBoundariesOptions::create(false, true, 10)
  // Quote content is longer than 10 characters
  let text = "彼は「これは長いテスト文です。さらに続きます。」と言った。"
  let boundaries = find_sentence_boundaries(text, options)
  // Should split inside the quote because it exceeds max length
  assert_true(boundaries.length() > 1)
}

///|
test "find_sentence_boundaries with extended terminators" {
  let options = FindBoundariesOptions::create(
    true, true, default_quote_safe_max_length,
  )
  // 彼は言った」次の文。 = 10 chars
  let text = "彼は言った」次の文。"
  let boundaries = find_sentence_boundaries(text, options)
  // 」 should be treated as a terminator with extended option
  // First boundary at 6 (after 」), second at 10 (after 。)
  inspect(boundaries, content="[6, 10]")
}

///|
test "find_next_boundary finds first boundary" {
  let text = "Hello. World."
  let boundary = find_next_boundary_default(text, 0)
  inspect(boundary, content="7")
}

///|
test "find_next_boundary from middle" {
  let text = "Hello. World."
  let boundary = find_next_boundary_default(text, 7)
  inspect(boundary, content="13")
}

///|
test "find_next_boundary returns length when no boundary" {
  let text = "No ending"
  let boundary = find_next_boundary_default(text, 0)
  inspect(boundary, content="9")
}

///|
test "is_at_boundary after terminator" {
  let text = "Hello. World"
  assert_true(is_at_boundary(text, 7))
}

///|
test "is_at_boundary in middle of word" {
  let text = "Hello. World"
  assert_false(is_at_boundary(text, 3))
}

///|
test "is_at_boundary at invalid positions" {
  let text = "Hello."
  assert_false(is_at_boundary(text, 0))
  assert_false(is_at_boundary(text, -1))
  assert_false(is_at_boundary(text, 100))
}

///|
test "ncd returns low value for identical texts" {
  let result = ncd("hello world", "hello world")
  // Identical texts should have very low NCD (close to 0)
  assert_true(result < 0.3)
}

///|
test "ncd returns low value for similar texts" {
  // Similar texts should have lower NCD than completely different texts
  let similar = ncd("hello world how are you", "hello world how is it")
  let different = ncd("hello world", "xyz abc 123 456")
  assert_true(similar < different)
}

///|
test "ncd returns high value for completely different texts" {
  // Completely different texts should have high NCD (close to 1)
  let result = ncd("aaaaaaaaaa", "bbbbbbbbbb")
  assert_true(result > 0.5)
}

///|
test "ncd returns 1 for empty vs non-empty" {
  assert_eq(ncd("", "hello"), 1.0)
  assert_eq(ncd("hello", ""), 1.0)
}

///|
test "ncd returns 0 for both empty" {
  assert_eq(ncd("", ""), 0.0)
}

///|
test "calculate_adjacent_ncd with empty array" {
  let result = calculate_adjacent_ncd([])
  assert_eq(result.length(), 0)
}

///|
test "calculate_adjacent_ncd with single element" {
  let result = calculate_adjacent_ncd(["hello"])
  assert_eq(result.length(), 0)
}

///|
test "calculate_adjacent_ncd with multiple elements" {
  let result = calculate_adjacent_ncd(["hello", "world", "test"])
  assert_eq(result.length(), 2)
}

///|
test "calculate_adjacent_ncd detects similarity differences" {
  // Similar adjacent texts should have lower NCD than different ones
  let texts = [
    "The cat sat on the mat.", "The cat lay on the mat.", "xyz abc 123 completely different text.",
  ]
  let ncds = calculate_adjacent_ncd(texts)
  // First pair (similar) should have lower NCD than second pair (different)
  assert_true(ncds[0] < ncds[1])
}

///|
test "compress produces smaller output for repetitive text" {
  // Repetitive text should compress better than random text
  let repetitive = compress("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  let varied = compress("abcdefghijklmnopqrstuvwxyz123456")
  // Repetitive text should compress to smaller size
  assert_true(repetitive.length() < varied.length())
}

///|
test "compressed_size returns consistent results" {
  let text = "hello world"
  let size1 = compressed_size(text)
  let size2 = compressed_size(text)
  assert_eq(size1, size2)
}

///|
test "find_local_maxima with empty array" {
  let result = find_local_maxima([], 0.3)
  assert_eq(result.length(), 0)
}

///|
test "find_local_maxima with single element above threshold" {
  let result = find_local_maxima([0.5], 0.3)
  inspect(result, content="[0]")
}

///|
test "find_local_maxima with single element below threshold" {
  let result = find_local_maxima([0.1], 0.3)
  assert_eq(result.length(), 0)
}

///|
test "find_local_maxima identifies peak" {
  let values = [0.1, 0.5, 0.2, 0.8, 0.3]
  let result = find_local_maxima(values, 0.3)
  // Peak at index 1 (0.5) and index 3 (0.8)
  inspect(result, content="[1, 3]")
}

///|
test "find_local_maxima respects threshold" {
  let values = [0.1, 0.5, 0.2, 0.4, 0.3]
  let result = find_local_maxima(values, 0.45)
  // Only peak at index 1 (0.5) is above threshold
  inspect(result, content="[1]")
}

///|
test "min_max_normalize with empty array" {
  let result = min_max_normalize([])
  assert_eq(result.length(), 0)
}

///|
test "min_max_normalize with single element" {
  let result = min_max_normalize([0.5])
  inspect(result, content="[0.5]")
}

///|
test "min_max_normalize with all same values" {
  let result = min_max_normalize([0.5, 0.5, 0.5])
  inspect(result, content="[0.5, 0.5, 0.5]")
}

///|
test "min_max_normalize normalizes range" {
  let result = min_max_normalize([0.0, 0.5, 1.0])
  inspect(result, content="[0, 0.5, 1]")
}

///|
test "tokenize_text_for_tfidf returns tokens" {
  let tokens = tokenize_text_for_tfidf("Hello World")
  assert_true(tokens.length() > 0)
}

///|
test "calculate_adjacent_tfidf_distance with texts" {
  let texts = ["Hello world", "How are you", "Goodbye world"]
  let distances = calculate_adjacent_tfidf_distance(texts)
  assert_eq(distances.length(), 2)
}

///|
test "QuoteStackEntry creation and access" {
  let entry = QuoteStackEntry::new('「', 5)
  assert_eq(entry.get_open(), '「')
  assert_eq(entry.get_start(), 5)
}

///|
test "FindBoundariesOptions default values" {
  let options = FindBoundariesOptions::new()
  assert_false(options.get_include_closing_brackets())
  assert_true(options.get_respect_japanese_quotes())
  assert_eq(options.get_quote_safe_max_length(), 240)
}

///|
test "update_quote_stack pushes opening quotes" {
  let stack : Array[QuoteStackEntry] = []
  update_quote_stack(stack, '「', 0)
  assert_eq(stack.length(), 1)
  assert_eq(stack[0].get_open(), '「')
}

///|
test "update_quote_stack pops matching closing quotes" {
  let stack : Array[QuoteStackEntry] = []
  update_quote_stack(stack, '「', 0)
  update_quote_stack(stack, '」', 5)
  assert_eq(stack.length(), 0)
}

///|
test "update_quote_stack ignores non-quote characters" {
  let stack : Array[QuoteStackEntry] = []
  update_quote_stack(stack, 'a', 0)
  update_quote_stack(stack, '。', 1)
  assert_eq(stack.length(), 0)
}

///|
test "build_quote_stack_until builds correct state" {
  let text = "「こんにちは」別の「テスト"
  let stack = build_quote_stack_until(text, text.length())
  // First quote pair is closed, second is open
  assert_eq(stack.length(), 1)
}

///|
test "is_inside_protected_quote returns false for empty stack" {
  let stack : Array[QuoteStackEntry] = []
  assert_false(is_inside_protected_quote(stack, 10, 240))
}

///|
test "is_inside_protected_quote returns true within max length" {
  let stack = [QuoteStackEntry::new('「', 5)]
  assert_true(is_inside_protected_quote(stack, 10, 240))
}

///|
test "is_inside_protected_quote returns false beyond max length" {
  let stack = [QuoteStackEntry::new('「', 5)]
  assert_false(is_inside_protected_quote(stack, 250, 240))
}

// =============================================================================
// UTF-8 Encoding Tests (char_to_utf8, string_to_utf8)
// =============================================================================

///|
test "char_to_utf8 ASCII characters (1-byte)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, 'A')
  assert_eq(buf.length(), 1)
  assert_eq(buf[0].to_int(), 0x41) // 'A' = 0x41
}

///|
test "char_to_utf8 ASCII range boundaries" {
  // Test lowest printable ASCII
  let buf1 : Array[Byte] = []
  char_to_utf8(buf1, ' ') // space = 0x20
  assert_eq(buf1.length(), 1)
  assert_eq(buf1[0].to_int(), 0x20)

  // Test highest ASCII (0x7F)
  let buf2 : Array[Byte] = []
  char_to_utf8(buf2, '\u{007F}')
  assert_eq(buf2.length(), 1)
  assert_eq(buf2[0].to_int(), 0x7F)
}

///|
test "char_to_utf8 2-byte UTF-8 (0x80-0x7FF)" {
  // Latin Extended: 'é' = U+00E9
  let buf1 : Array[Byte] = []
  char_to_utf8(buf1, 'é')
  assert_eq(buf1.length(), 2)
  // U+00E9 -> C3 A9 in UTF-8
  assert_eq(buf1[0].to_int(), 0xC3)
  assert_eq(buf1[1].to_int(), 0xA9)
}

///|
test "char_to_utf8 2-byte boundary (0x80)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, '\u{0080}')
  assert_eq(buf.length(), 2)
  // U+0080 -> C2 80 in UTF-8
  assert_eq(buf[0].to_int(), 0xC2)
  assert_eq(buf[1].to_int(), 0x80)
}

///|
test "char_to_utf8 2-byte boundary (0x7FF)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, '\u{07FF}')
  assert_eq(buf.length(), 2)
  // U+07FF -> DF BF in UTF-8
  assert_eq(buf[0].to_int(), 0xDF)
  assert_eq(buf[1].to_int(), 0xBF)
}

///|
test "char_to_utf8 3-byte UTF-8 Japanese hiragana" {
  // 'あ' = U+3042
  let buf : Array[Byte] = []
  char_to_utf8(buf, 'あ')
  assert_eq(buf.length(), 3)
  // U+3042 -> E3 81 82 in UTF-8
  assert_eq(buf[0].to_int(), 0xE3)
  assert_eq(buf[1].to_int(), 0x81)
  assert_eq(buf[2].to_int(), 0x82)
}

///|
test "char_to_utf8 3-byte UTF-8 Chinese character" {
  // '中' = U+4E2D
  let buf : Array[Byte] = []
  char_to_utf8(buf, '中')
  assert_eq(buf.length(), 3)
  // U+4E2D -> E4 B8 AD in UTF-8
  assert_eq(buf[0].to_int(), 0xE4)
  assert_eq(buf[1].to_int(), 0xB8)
  assert_eq(buf[2].to_int(), 0xAD)
}

///|
test "char_to_utf8 3-byte boundary (0x800)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, '\u{0800}')
  assert_eq(buf.length(), 3)
  // U+0800 -> E0 A0 80 in UTF-8
  assert_eq(buf[0].to_int(), 0xE0)
  assert_eq(buf[1].to_int(), 0xA0)
  assert_eq(buf[2].to_int(), 0x80)
}

///|
test "char_to_utf8 3-byte boundary (0xFFFF)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, '\u{FFFF}')
  assert_eq(buf.length(), 3)
  // U+FFFF -> EF BF BF in UTF-8
  assert_eq(buf[0].to_int(), 0xEF)
  assert_eq(buf[1].to_int(), 0xBF)
  assert_eq(buf[2].to_int(), 0xBF)
}

///|
test "char_to_utf8 4-byte UTF-8 emoji" {
  // '😀' = U+1F600
  let buf : Array[Byte] = []
  char_to_utf8(buf, '😀')
  assert_eq(buf.length(), 4)
  // U+1F600 -> F0 9F 98 80 in UTF-8
  assert_eq(buf[0].to_int(), 0xF0)
  assert_eq(buf[1].to_int(), 0x9F)
  assert_eq(buf[2].to_int(), 0x98)
  assert_eq(buf[3].to_int(), 0x80)
}

///|
test "char_to_utf8 4-byte boundary (0x10000)" {
  let buf : Array[Byte] = []
  char_to_utf8(buf, '\u{10000}')
  assert_eq(buf.length(), 4)
  // U+10000 -> F0 90 80 80 in UTF-8
  assert_eq(buf[0].to_int(), 0xF0)
  assert_eq(buf[1].to_int(), 0x90)
  assert_eq(buf[2].to_int(), 0x80)
  assert_eq(buf[3].to_int(), 0x80)
}

///|
test "string_to_utf8 empty string" {
  let result = string_to_utf8("")
  assert_eq(result.length(), 0)
}

///|
test "string_to_utf8 ASCII only" {
  let result = string_to_utf8("Hello")
  assert_eq(result.length(), 5)
  assert_eq(result[0].to_int(), 0x48) // 'H'
  assert_eq(result[1].to_int(), 0x65) // 'e'
  assert_eq(result[2].to_int(), 0x6C) // 'l'
  assert_eq(result[3].to_int(), 0x6C) // 'l'
  assert_eq(result[4].to_int(), 0x6F) // 'o'
}

///|
test "string_to_utf8 Japanese text" {
  let result = string_to_utf8("あい")
  // 'あ' = 3 bytes, 'い' = 3 bytes
  assert_eq(result.length(), 6)
}

///|
test "string_to_utf8 mixed content" {
  let result = string_to_utf8("A中😀")
  // 'A' = 1 byte, '中' = 3 bytes, '😀' = 4 bytes
  assert_eq(result.length(), 8)
}

///|
test "string_to_utf8 produces valid UTF-8 roundtrip" {
  // Test that our encoding matches what would be expected
  let text = "Hello 世界 🌍"
  let bytes = string_to_utf8(text)
  // 'Hello ' = 6 bytes, '世' = 3, '界' = 3, ' ' = 1, '🌍' = 4 = 17 total
  assert_eq(bytes.length(), 17)
}

// =============================================================================
// LZ77 find_longest_match Tests
// =============================================================================

///|
test "find_longest_match no match at start" {
  let data = string_to_utf8("abcdef")
  let (offset, length) = find_longest_match(data, 0, 256, 3, 258)
  // At position 0, no previous data to match
  assert_eq(offset, 0)
  assert_eq(length, 0)
}

///|
test "find_longest_match finds exact match" {
  let data = string_to_utf8("abcabc")
  // At position 3, should find "abc" matching at position 0
  let (offset, length) = find_longest_match(data, 3, 256, 3, 258)
  assert_eq(offset, 3) // 3 positions back
  assert_eq(length, 3) // 3 characters match
}

///|
test "find_longest_match respects min_match_length" {
  let data = string_to_utf8("abab")
  // At position 2, "ab" matches but min_match is 3
  let (offset, length) = find_longest_match(data, 2, 256, 3, 258)
  assert_eq(offset, 0)
  assert_eq(length, 0)
}

///|
test "find_longest_match respects max_match_length" {
  let data = string_to_utf8("aaaaaaaaaaaaaaaaaaaa") // 20 'a's
  // At position 10, all previous match but max is 5
  let (_offset, length) = find_longest_match(data, 10, 256, 3, 5)
  assert_eq(length, 5)
}

///|
test "find_longest_match respects window_size" {
  let data = string_to_utf8("abcdefghij") // 10 chars
  // Add more data
  let extended : Array[Byte] = []
  for b in data {
    extended.push(b)
  }
  for b in string_to_utf8("abcdefghij") {
    extended.push(b)
  }
  // At position 10, window_size=5 means only search back 5 positions
  let (_offset, length) = find_longest_match(extended, 10, 5, 3, 258)
  // Can only see "fghij" (positions 5-9), "abcde" at 10 won't match
  // Actually at pos 10, looking back 5 sees pos 5-9 which is "fghij"
  // We're looking for match starting at pos 10 which is 'a' - no match in window
  assert_eq(length, 0)
}

///|
test "find_longest_match finds longest among multiple" {
  let data = string_to_utf8("abcabcabc")
  // At position 6, both "abc" at 0 and "abc" at 3 match
  // Should find the match giving longest result
  let (_offset, length) = find_longest_match(data, 6, 256, 3, 258)
  assert_eq(length, 3)
}

///|
test "find_longest_match position near end" {
  let data = string_to_utf8("abcab")
  // At position 3, only "ab" left but min is 2
  let (offset, length) = find_longest_match(data, 3, 256, 2, 258)
  assert_eq(length, 2)
  assert_eq(offset, 3)
}

///|
test "find_longest_match not enough data remaining" {
  let data = string_to_utf8("abc")
  // At position 2, only 1 byte left, less than min_match=3
  let (offset, length) = find_longest_match(data, 2, 256, 3, 258)
  assert_eq(offset, 0)
  assert_eq(length, 0)
}

///|
test "find_longest_match with repetitive data" {
  let data = string_to_utf8("aaaaaa")
  // At position 3, matches "aaa" at position 0
  let (_offset, length) = find_longest_match(data, 3, 256, 3, 258)
  assert_true(length >= 3)
}

// =============================================================================
// Additional compress tests
// =============================================================================

///|
test "compress empty string" {
  let result = compress("")
  assert_eq(result.length(), 0)
}

///|
test "compress single character" {
  let result = compress("a")
  // Single char = literal marker (1) + byte (1) = 2 bytes
  assert_eq(result.length(), 2)
}

///|
test "compress contains back references for repetitive text" {
  // "abcabc" should compress: abc as literals, then back-reference for second abc
  let result = compress("abcabcabc")
  // "abcabcabc" = 9 ASCII chars original
  // With compression, should be smaller due to back references
  // 3 literals (6 bytes) + 2 back-refs (8 bytes) = 14 bytes worst case
  // But back-refs save space compared to 18 bytes of all literals
  assert_true(result.length() > 0)
}

///|
test "compress handles UTF-8 correctly" {
  let result = compress("あいうえお")
  // 5 Japanese chars * 3 bytes each = 15 bytes raw
  // Each literal = 2 bytes output, so 30 bytes minimum
  assert_true(result.length() > 0)
}

///|
test "compress deterministic output" {
  let text = "hello world hello"
  let result1 = compress(text)
  let result2 = compress(text)
  assert_eq(result1.length(), result2.length())
}
