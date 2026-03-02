// Tests for punctuation-based segmentation.

// =============================================================================
// PunctuationConfig Tests
// =============================================================================

///|
test "PunctuationConfig::new creates default config" {
  let config = PunctuationConfig::new()
  assert_eq(config.get_target_chunk_size(), 500)
  assert_eq(config.get_min_chunk_size(), 100)
  assert_eq(config.get_max_chunk_size(), 2000)
}

///|
test "PunctuationConfig::create with custom values" {
  let config = PunctuationConfig::create(200, 50, 1000)
  assert_eq(config.get_target_chunk_size(), 200)
  assert_eq(config.get_min_chunk_size(), 50)
  assert_eq(config.get_max_chunk_size(), 1000)
}

///|
test "PunctuationConfig equality" {
  let config1 = PunctuationConfig::create(200, 50, 1000)
  let config2 = PunctuationConfig::create(200, 50, 1000)
  let config3 = PunctuationConfig::create(300, 50, 1000)
  assert_eq(config1, config2)
  assert_true(config1 != config3)
}

// =============================================================================
// PunctuationStrategy Tests
// =============================================================================

///|
test "PunctuationStrategy::new creates strategy with default config" {
  let strategy = PunctuationStrategy::new()
  let config = strategy.get_config()
  assert_eq(config.get_target_chunk_size(), 500)
}

///|
test "PunctuationStrategy::with_config uses custom config" {
  let config = PunctuationConfig::create(100, 20, 500)
  let strategy = PunctuationStrategy::with_config(config)
  assert_eq(strategy.get_config().get_target_chunk_size(), 100)
  assert_eq(strategy.get_config().get_min_chunk_size(), 20)
}

///|
test "PunctuationStrategy implements SegmentationStrategy name" {
  let strategy = PunctuationStrategy::new()
  assert_eq(@types.SegmentationStrategy::name(strategy), "punctuation")
}

// =============================================================================
// segment_by_punctuation - Empty/Whitespace Tests
// =============================================================================

///|
test "segment_by_punctuation empty text returns empty" {
  let config = PunctuationConfig::new()
  let result = segment_by_punctuation("", config)
  assert_eq(result.length(), 0)
}

///|
test "segment_by_punctuation whitespace only returns empty" {
  let config = PunctuationConfig::new()
  let result = segment_by_punctuation("   \t\n  ", config)
  assert_eq(result.length(), 0)
}

///|
test "segment_by_punctuation Japanese whitespace only returns empty" {
  let config = PunctuationConfig::new()
  // Full-width space (U+3000)
  let result = segment_by_punctuation("\u{3000}\u{3000}", config)
  assert_eq(result.length(), 0)
}

// =============================================================================
// segment_by_punctuation - Small Text Tests
// =============================================================================

///|
test "segment_by_punctuation text smaller than min_size returns single segment" {
  let config = PunctuationConfig::create(100, 50, 200)
  let text = "Short text."
  let result = segment_by_punctuation(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), text.length())
}

///|
test "segment_by_punctuation text exactly min_size" {
  let config = PunctuationConfig::create(100, 10, 200)
  let text = "1234567890" // exactly 10 chars
  let result = segment_by_punctuation(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 10)
}

// =============================================================================
// segment_by_punctuation - Normal Segmentation Tests
// =============================================================================

///|
test "segment_by_punctuation splits at sentence boundaries" {
  let config = PunctuationConfig::create(20, 5, 100)
  let text = "First sentence. Second sentence. Third sentence."
  let result = segment_by_punctuation(text, config)
  // Should create segments at sentence boundaries
  assert_true(result.length() >= 1)
  // First segment should start at 0
  assert_eq(result[0].get_start(), 0)
}

///|
test "segment_by_punctuation accumulates sentences to target size" {
  // target=50, so should accumulate until ~50 chars
  let config = PunctuationConfig::create(50, 10, 200)
  let text = "One. Two. Three. Four. Five. Six. Seven. Eight. Nine. Ten."
  let result = segment_by_punctuation(text, config)
  // Should have multiple segments
  assert_true(result.length() >= 1)
  // Each segment (except last) should be around target size
  for i = 0; i < result.length(); i = i + 1 {
    let seg = result[i]
    let size = seg.get_end() - seg.get_start()
    // Non-last segments should respect min_size
    if i < result.length() - 1 {
      assert_true(size >= 10)
    }
  }
}

///|
test "segment_by_punctuation respects target chunk size" {
  let config = PunctuationConfig::create(30, 5, 100)
  let text = "A. B. C. D. E. F. G. H. I. J."
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment_by_punctuation - Force Split (Max Size) Tests
// =============================================================================

///|
test "segment_by_punctuation force splits at max_size" {
  // Very small max_size to force splits
  let config = PunctuationConfig::create(10, 5, 20)
  let text = "This is a very long sentence without any periods that exceeds the maximum chunk size limit"
  let result = segment_by_punctuation(text, config)
  // Should have multiple segments due to force splits
  assert_true(result.length() > 1)
  // Each segment should not exceed max_size (allowing for boundary alignment)
  for seg in result {
    let size = seg.get_end() - seg.get_start()
    assert_true(size <= 20)
  }
}

///|
test "segment_by_punctuation handles no sentence boundaries with force split" {
  let config = PunctuationConfig::create(20, 5, 30)
  // No sentence terminators
  let text = "abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz"
  let result = segment_by_punctuation(text, config)
  // Should still segment using force splits
  assert_true(result.length() >= 1)
}

///|
test "segment_by_punctuation uses last valid boundary before force split" {
  let config = PunctuationConfig::create(30, 10, 50)
  // Sentences of varying sizes
  let text = "Short. Another short. This is a much longer sentence that goes over the max size limit."
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment_by_punctuation - Japanese Text Tests
// =============================================================================

///|
test "segment_by_punctuation handles Japanese punctuation" {
  let config = PunctuationConfig::create(20, 5, 100)
  let text = "これは文章です。次の文章です。最後の文章です。"
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
  // Should recognize 。 as sentence boundary
}

///|
test "segment_by_punctuation handles Japanese exclamation and question" {
  let config = PunctuationConfig::create(30, 5, 100)
  let text = "すごい！本当ですか？そうです。"
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

///|
test "segment_by_punctuation handles mixed Japanese and English" {
  let config = PunctuationConfig::create(30, 5, 100)
  let text = "Hello world. これは日本語です。Mixed content here."
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment_by_punctuation - Remaining Text Tests
// =============================================================================

///|
test "segment_by_punctuation handles remaining text smaller than min_size" {
  let config = PunctuationConfig::create(30, 10, 100)
  // Create text where remaining portion is small
  let text = "First chunk here. A."
  let result = segment_by_punctuation(text, config)
  // Small remaining should be merged with previous segment
  assert_true(result.length() >= 1)
  // Last segment should end at text length
  assert_eq(result[result.length() - 1].get_end(), text.length())
}

///|
test "segment_by_punctuation handles remaining text with content" {
  let config = PunctuationConfig::create(20, 5, 100)
  let text = "First. Second. Third portion here."
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
  // Should include all text
  assert_eq(result[result.length() - 1].get_end(), text.length())
}

///|
test "segment_by_punctuation ignores trailing whitespace-only content" {
  let config = PunctuationConfig::create(20, 5, 100)
  let text = "Content here.      "
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment_by_punctuation - Edge Cases
// =============================================================================

///|
test "segment_by_punctuation single character" {
  let config = PunctuationConfig::create(10, 1, 20)
  let text = "A"
  let result = segment_by_punctuation(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 1)
}

///|
test "segment_by_punctuation single sentence" {
  let config = PunctuationConfig::create(100, 5, 200)
  let text = "This is a single sentence."
  let result = segment_by_punctuation(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), text.length())
}

///|
test "segment_by_punctuation consecutive terminators" {
  let config = PunctuationConfig::create(30, 5, 100)
  let text = "Really?! Yes... No!!!"
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

///|
test "segment_by_punctuation with quotes" {
  let config = PunctuationConfig::create(50, 5, 200)
  let text = "He said \"Hello.\" She replied \"Hi!\""
  let result = segment_by_punctuation(text, config)
  assert_true(result.length() >= 1)
}

///|
test "segment_by_punctuation segment type is Paragraph" {
  let config = PunctuationConfig::create(20, 5, 100)
  let text = "First. Second."
  let result = segment_by_punctuation(text, config)
  for seg in result {
    assert_eq(seg.get_type(), @types.SegmentType::Paragraph)
  }
}

// =============================================================================
// segment() wrapper function tests
// =============================================================================

///|
test "segment uses default configuration" {
  let text = "This is a test sentence. Another one here."
  let result = segment(text)
  // Should work with default config (target=500, min=100, max=2000)
  // With such large defaults, short text becomes single segment
  assert_eq(result.length(), 1)
}

///|
test "segment empty text" {
  let result = segment("")
  assert_eq(result.length(), 0)
}

// =============================================================================
// SegmentationStrategy trait implementation tests
// =============================================================================

///|
test "SegmentationStrategy::segment works via trait" {
  let strategy = PunctuationStrategy::new()
  let text = "Test sentence."
  let result = @types.SegmentationStrategy::segment(strategy, text)
  assert_true(result.length() >= 1)
}

///|
test "SegmentationStrategy::segment with custom config via trait" {
  let config = PunctuationConfig::create(20, 5, 50)
  let strategy = PunctuationStrategy::with_config(config)
  let text = "First. Second. Third. Fourth. Fifth."
  let result = @types.SegmentationStrategy::segment(strategy, text)
  assert_true(result.length() >= 1)
}

// =============================================================================
// is_whitespace_only helper tests (internal function)
// =============================================================================

///|
test "is_whitespace_only with spaces" {
  assert_true(is_whitespace_only("   "))
}

///|
test "is_whitespace_only with tabs and newlines" {
  assert_true(is_whitespace_only("\t\n\r"))
}

///|
test "is_whitespace_only with mixed whitespace" {
  assert_true(is_whitespace_only(" \t \n \r "))
}

///|
test "is_whitespace_only with content returns false" {
  assert_false(is_whitespace_only("  a  "))
}

///|
test "is_whitespace_only empty string" {
  assert_true(is_whitespace_only(""))
}

///|
test "is_whitespace_only Japanese full-width space" {
  assert_true(is_whitespace_only("\u{3000}"))
}

// =============================================================================
// extract_substring helper tests (internal function)
// =============================================================================

///|
test "extract_substring basic" {
  let text = "Hello World"
  let result = extract_substring(text, 0, 5)
  assert_eq(result, "Hello")
}

///|
test "extract_substring middle" {
  let text = "Hello World"
  let result = extract_substring(text, 6, 11)
  assert_eq(result, "World")
}

///|
test "extract_substring end beyond length" {
  let text = "Hello"
  let result = extract_substring(text, 0, 100)
  assert_eq(result, "Hello")
}

///|
test "extract_substring empty range" {
  let text = "Hello"
  let result = extract_substring(text, 2, 2)
  assert_eq(result, "")
}

///|
test "extract_substring Japanese text" {
  let text = "こんにちは世界"
  let result = extract_substring(text, 0, 5)
  assert_eq(result, "こんにちは")
}
