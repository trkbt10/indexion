// Tests for sentence splitting functionality.

///|
test "split_sentences with empty string" {
  let sentences = split_sentences("")
  assert_eq(sentences.length(), 0)
}

///|
test "split_sentences with single English sentence" {
  let sentences = split_sentences("Hello world.")
  assert_eq(sentences.length(), 1)
  assert_eq(sentences[0].text, "Hello world.")
  assert_eq(sentences[0].start, 0)
  assert_eq(sentences[0].end, 12)
}

///|
test "split_sentences with multiple English sentences" {
  let sentences = split_sentences("First sentence. Second sentence. Third one!")
  assert_eq(sentences.length(), 3)
  assert_eq(sentences[0].text, "First sentence.")
  assert_eq(sentences[1].text, "Second sentence.")
  assert_eq(sentences[2].text, "Third one!")
}

///|
test "split_sentences with question and exclamation" {
  let sentences = split_sentences("What is this? It is amazing!")
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "What is this?")
  assert_eq(sentences[1].text, "It is amazing!")
}

///|
test "split_sentences with Japanese sentences" {
  let sentences = split_sentences("これは文です。次の文です。")
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "これは文です。")
  assert_eq(sentences[1].text, "次の文です。")
}

///|
test "split_sentences with Japanese punctuation marks" {
  let sentences = split_sentences(
    "質問ですか？はい、そうです！すごい．",
  )
  assert_eq(sentences.length(), 3)
  assert_eq(sentences[0].text, "質問ですか？")
  assert_eq(sentences[1].text, "はい、そうです！")
  assert_eq(sentences[2].text, "すごい．")
}

///|
test "split_sentences with mixed English and Japanese" {
  let sentences = split_sentences("Hello. これはテストです。World!")
  assert_eq(sentences.length(), 3)
  assert_eq(sentences[0].text, "Hello.")
  assert_eq(sentences[1].text, "これはテストです。")
  assert_eq(sentences[2].text, "World!")
}

///|
test "split_sentences with newlines" {
  let sentences = split_sentences("First line\nSecond line\nThird line")
  assert_eq(sentences.length(), 3)
  assert_eq(sentences[0].text, "First line")
  assert_eq(sentences[1].text, "Second line")
  assert_eq(sentences[2].text, "Third line")
}

///|
test "split_sentences with consecutive punctuation" {
  let sentences = split_sentences("Wow!!! Really??? Yes...")
  assert_eq(sentences.length(), 3)
  assert_eq(sentences[0].text, "Wow!")
  assert_eq(sentences[1].text, "Really?")
  assert_eq(sentences[2].text, "Yes.")
}

///|
test "split_sentences with whitespace only" {
  let sentences = split_sentences("   \n\t  ")
  assert_eq(sentences.length(), 0)
}

///|
test "split_sentences with sentence without ending punctuation" {
  let sentences = split_sentences("This has no ending")
  assert_eq(sentences.length(), 1)
  assert_eq(sentences[0].text, "This has no ending")
}

///|
test "split_sentences with leading and trailing whitespace" {
  let sentences = split_sentences("  Hello world.  ")
  assert_eq(sentences.length(), 1)
  assert_eq(sentences[0].text, "Hello world.")
}

///|
test "split_sentences_text returns text only" {
  let texts = split_sentences_text("First. Second. Third.")
  assert_eq(texts.length(), 3)
  assert_eq(texts[0], "First.")
  assert_eq(texts[1], "Second.")
  assert_eq(texts[2], "Third.")
}

///|
test "count_sentences counts correctly" {
  assert_eq(count_sentences(""), 0)
  assert_eq(count_sentences("One."), 1)
  assert_eq(count_sentences("One. Two. Three."), 3)
  assert_eq(count_sentences("日本語。英語。混合。"), 3)
}

///|
test "Sentence::new and accessors" {
  let s = Sentence::new("Test sentence.", 10, 24)
  assert_eq(s.get_text(), "Test sentence.")
  assert_eq(s.get_start(), 10)
  assert_eq(s.get_end(), 24)
  assert_eq(s.length(), 14)
}

///|
test "split_sentences with multiple newlines" {
  let sentences = split_sentences("First.\n\n\nSecond.")
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "First.")
  assert_eq(sentences[1].text, "Second.")
}

///|
test "split_sentences preserves internal whitespace" {
  let sentences = split_sentences("Hello   world.  Next  one.")
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "Hello   world.")
  assert_eq(sentences[1].text, "Next  one.")
}

// ============================================================
// Quote Protection Tests
// ============================================================

///|
test "split_sentences with Japanese quotes - basic" {
  // Punctuation inside Japanese quotes should not split
  let sentences = split_sentences(
    "「まあ、お前だけお食べ。」と母は言った。",
  )
  assert_eq(sentences.length(), 1)
  assert_eq(
    sentences[0].text,
    "「まあ、お前だけお食べ。」と母は言った。",
  )
}

///|
test "split_sentences with nested Japanese quotes" {
  // Nested quotes: 「彼は『本当か？』と聞いた。」
  let sentences = split_sentences(
    "「彼は『本当か？』と聞いた。」",
  )
  assert_eq(sentences.length(), 1)
  assert_eq(sentences[0].text, "「彼は『本当か？』と聞いた。」")
}

///|
test "split_sentences with quotes - multiple sentences" {
  let sentences = split_sentences(
    "「こんにちは。」と彼は言った。「さようなら。」と彼女は答えた。",
  )
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "「こんにちは。」と彼は言った。")
  assert_eq(
    sentences[1].text,
    "「さようなら。」と彼女は答えた。",
  )
}

///|
test "split_sentences with English quotes" {
  // Note: English ASCII quotes are not protected because they are ambiguous
  // (same character for open and close). This matches the reference implementation.
  let sentences = split_sentences("He said \"Hello. How are you?\" to her.")
  // English quotes are NOT protected - sentence splits at "Hello."
  assert_true(sentences.length() >= 2)
}

///|
test "split_sentences with quote protection disabled" {
  let options = {
    quote_protection: false,
    quote_safe_max_length: 240,
    include_closing_brackets: false,
  }
  let sentences = split_sentences_with_options(
    "「まあ、お前だけお食べ。」と母は言った。", options,
  )
  // Without protection, the punctuation inside quotes will split
  assert_true(sentences.length() >= 2)
}

///|
test "split_sentences with long quote exceeding max length" {
  // Create a quote longer than 20 characters (using small max for testing)
  let options = {
    quote_protection: true,
    quote_safe_max_length: 20,
    include_closing_brackets: false,
  }
  let long_text = "「これはとても長い文章で、二十文字を超えています。分割されるべきです。」"
  let sentences = split_sentences_with_options(long_text, options)
  // With a short max length, the quote should be split
  assert_true(sentences.length() >= 2)
}

///|
test "split_sentences with include_closing_brackets" {
  let options = {
    quote_protection: false,
    quote_safe_max_length: 240,
    include_closing_brackets: true,
  }
  let sentences = split_sentences_with_options(
    "これはテスト」次の文。", options,
  )
  // The closing bracket should act as a sentence terminator
  assert_eq(sentences.length(), 2)
}

///|
test "SplitOptions::default creates expected defaults" {
  let options = SplitOptions::default()
  assert_eq(options.quote_protection, true)
  assert_eq(options.quote_safe_max_length, 240)
  assert_eq(options.include_closing_brackets, false)
}

///|
test "split_sentences_text_with_options works" {
  let options = SplitOptions::default()
  let texts = split_sentences_text_with_options("First. Second.", options)
  assert_eq(texts.length(), 2)
  assert_eq(texts[0], "First.")
  assert_eq(texts[1], "Second.")
}

///|
test "count_sentences_with_options works" {
  let options = SplitOptions::default()
  assert_eq(count_sentences_with_options("One. Two. Three.", options), 3)
}

///|
test "split_sentences with mixed quote types" {
  // Japanese and English quotes mixed
  // English quotes are not protected, so "OK." causes a split
  // Japanese quotes are protected
  let sentences = split_sentences(
    "She said \"OK.\" 「そうですね。」と答えた。",
  )
  // English quote causes split at "OK.", and Japanese quote protects the rest
  assert_true(sentences.length() >= 1)
  // The Japanese quoted portion should be in a sentence
  let last = sentences[sentences.length() - 1]
  assert_true(last.text.contains("「そうですね。」と答えた。"))
}

///|
test "split_sentences with question in quote" {
  let sentences = split_sentences(
    "「何をしているの？」と彼女は尋ねた。次の文。",
  )
  assert_eq(sentences.length(), 2)
  assert_eq(
    sentences[0].text,
    "「何をしているの？」と彼女は尋ねた。",
  )
  assert_eq(sentences[1].text, "次の文。")
}

///|
test "split_sentences with exclamation in quote" {
  let sentences = split_sentences(
    "「やめて！」と叫んだ。彼は驚いた。",
  )
  assert_eq(sentences.length(), 2)
  assert_eq(sentences[0].text, "「やめて！」と叫んだ。")
  assert_eq(sentences[1].text, "彼は驚いた。")
}
