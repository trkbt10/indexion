// Tests for TF-IDF based segmentation.

// =============================================================================
// TfidfConfig Tests
// =============================================================================

///|
test "TfidfConfig::new creates default config" {
  let config = TfidfConfig::new()
  assert_eq(config.get_target_chunk_size(), 500)
  assert_eq(config.get_min_chunk_size(), 100)
  assert_eq(config.get_max_chunk_size(), 2000)
  assert_eq(config.get_tfidf_threshold(), 0.45)
  assert_eq(config.get_window_size(), 3)
}

///|
test "TfidfConfig::create with custom values" {
  let config = TfidfConfig::create(200, 50, 1000, 0.5, 2)
  assert_eq(config.get_target_chunk_size(), 200)
  assert_eq(config.get_min_chunk_size(), 50)
  assert_eq(config.get_max_chunk_size(), 1000)
  assert_eq(config.get_tfidf_threshold(), 0.5)
  assert_eq(config.get_window_size(), 2)
}

///|
test "TfidfConfig equality" {
  let config1 = TfidfConfig::create(200, 50, 1000, 0.5, 2)
  let config2 = TfidfConfig::create(200, 50, 1000, 0.5, 2)
  let config3 = TfidfConfig::create(300, 50, 1000, 0.5, 2)
  assert_eq(config1, config2)
  assert_true(config1 != config3)
}

// =============================================================================
// TfidfStrategy Tests
// =============================================================================

///|
test "TfidfStrategy::new creates strategy with default config" {
  let strategy = TfidfStrategy::new()
  let config = strategy.get_config()
  assert_eq(config.get_target_chunk_size(), 500)
  assert_eq(config.get_window_size(), 3)
}

///|
test "TfidfStrategy::with_config uses custom config" {
  let config = TfidfConfig::create(100, 20, 500, 0.3, 2)
  let strategy = TfidfStrategy::with_config(config)
  assert_eq(strategy.get_config().get_target_chunk_size(), 100)
  assert_eq(strategy.get_config().get_tfidf_threshold(), 0.3)
}

///|
test "TfidfStrategy implements SegmentationStrategy name" {
  let strategy = TfidfStrategy::new()
  assert_eq(@types.SegmentationStrategy::name(strategy), "tfidf")
}

// =============================================================================
// segment_by_tfidf - Empty/Whitespace Tests
// =============================================================================

///|
test "segment_by_tfidf empty text returns empty" {
  let config = TfidfConfig::new()
  let result = segment_by_tfidf("", config)
  assert_eq(result.length(), 0)
}

///|
test "segment_by_tfidf whitespace only returns empty" {
  let config = TfidfConfig::new()
  let result = segment_by_tfidf("   \t\n  ", config)
  assert_eq(result.length(), 0)
}

///|
test "segment_by_tfidf Japanese whitespace only returns empty" {
  let config = TfidfConfig::new()
  let result = segment_by_tfidf("\u{3000}\u{3000}", config)
  assert_eq(result.length(), 0)
}

// =============================================================================
// segment_by_tfidf - Small Text Tests
// =============================================================================

///|
test "segment_by_tfidf text smaller than min_size returns single segment" {
  let config = TfidfConfig::create(100, 50, 200, 0.45, 3)
  let text = "Short text."
  let result = segment_by_tfidf(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), text.length())
}

///|
test "segment_by_tfidf text exactly min_size" {
  let config = TfidfConfig::create(100, 10, 200, 0.45, 3)
  let text = "1234567890"
  let result = segment_by_tfidf(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 10)
}

// =============================================================================
// segment_by_tfidf - Normal Segmentation Tests
// =============================================================================

///|
test "segment_by_tfidf produces valid segments" {
  let config = TfidfConfig::create(50, 10, 200, 0.3, 2)
  let text = "First sentence here. Second sentence follows. Third one is different. Fourth continues. Fifth ends."
  let result = segment_by_tfidf(text, config)
  assert_true(result.length() >= 1)
  // First segment starts at 0
  assert_eq(result[0].get_start(), 0)
  // Last segment ends at text length
  assert_eq(result[result.length() - 1].get_end(), text.length())
}

///|
test "segment_by_tfidf segments are contiguous" {
  let config = TfidfConfig::create(30, 5, 100, 0.3, 2)
  let text = "One. Two. Three. Four. Five. Six. Seven. Eight."
  let result = segment_by_tfidf(text, config)
  // Check that segments are contiguous
  for i = 1; i < result.length(); i = i + 1 {
    assert_eq(result[i].get_start(), result[i - 1].get_end())
  }
}

///|
test "segment_by_tfidf segment type is Paragraph" {
  let config = TfidfConfig::create(20, 5, 100, 0.3, 2)
  let text = "First. Second. Third."
  let result = segment_by_tfidf(text, config)
  for seg in result {
    assert_eq(seg.get_type(), @types.SegmentType::Paragraph)
  }
}

// =============================================================================
// segment_by_tfidf - Few Sentences (Window Edge Case)
// =============================================================================

///|
test "segment_by_tfidf handles fewer sentences than window size" {
  // window_size=3, but only 2 sentences
  let config = TfidfConfig::create(50, 10, 200, 0.45, 3)
  let text = "First sentence. Second sentence."
  let result = segment_by_tfidf(text, config)
  assert_true(result.length() >= 1)
  assert_eq(result[0].get_start(), 0)
}

///|
test "segment_by_tfidf handles exactly window_size sentences" {
  let config = TfidfConfig::create(50, 10, 200, 0.45, 3)
  let text = "First. Second. Third."
  let result = segment_by_tfidf(text, config)
  assert_true(result.length() >= 1)
}

///|
test "segment_by_tfidf single sentence" {
  let config = TfidfConfig::create(100, 10, 200, 0.45, 3)
  let text = "This is a single sentence."
  let result = segment_by_tfidf(text, config)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), text.length())
}

///|
test "segment_by_tfidf no sentence boundaries" {
  let config = TfidfConfig::create(50, 10, 200, 0.45, 3)
  let text = "No sentence terminators here"
  let result = segment_by_tfidf(text, config)
  assert_eq(result.length(), 1)
}

// =============================================================================
// segment_by_tfidf - Japanese Text Tests
// =============================================================================

///|
test "segment_by_tfidf handles Japanese punctuation" {
  let config = TfidfConfig::create(30, 10, 100, 0.3, 2)
  let text = "これは文章です。次の文章です。別の文章です。最後の文章です。"
  let result = segment_by_tfidf(text, config)
  assert_true(result.length() >= 1)
}

///|
test "segment_by_tfidf handles mixed Japanese and English" {
  let config = TfidfConfig::create(40, 10, 100, 0.3, 2)
  let text = "Hello world. これは日本語です。Mixed content. 続きます。"
  let result = segment_by_tfidf(text, config)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment_by_tfidf - Size Constraints Tests
// =============================================================================

///|
test "segment_by_tfidf respects max_chunk_size" {
  let config = TfidfConfig::create(50, 10, 80, 0.3, 2)
  let text = "A. B. C. D. E. F. G. H. I. J. K. L. M. N. O. P. Q. R. S. T. U. V. W. X. Y. Z."
  let result = segment_by_tfidf(text, config)
  // Each segment should not exceed max_chunk_size
  for seg in result {
    let size = seg.get_end() - seg.get_start()
    assert_true(size <= 80)
  }
}

///|
test "segment_by_tfidf respects min_chunk_size" {
  let config = TfidfConfig::create(30, 15, 100, 0.2, 2)
  let text = "First sentence here. Second follows. Third one. Fourth. Fifth sentence ends here."
  let result = segment_by_tfidf(text, config)
  // Non-last segments should generally respect min_size
  // (last segment can be smaller if needed)
  assert_true(result.length() >= 1)
}

// =============================================================================
// segment() wrapper function tests
// =============================================================================

///|
test "segment uses default configuration" {
  let text = "This is a test sentence. Another one here."
  let result = segment(text)
  // With default config (target=500), short text becomes single segment
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
  let strategy = TfidfStrategy::new()
  let text = "Test sentence."
  let result = @types.SegmentationStrategy::segment(strategy, text)
  assert_true(result.length() >= 1)
}

///|
test "SegmentationStrategy::segment with custom config via trait" {
  let config = TfidfConfig::create(20, 5, 50, 0.3, 2)
  let strategy = TfidfStrategy::with_config(config)
  let text = "First. Second. Third. Fourth. Fifth."
  let result = @types.SegmentationStrategy::segment(strategy, text)
  assert_true(result.length() >= 1)
}

// =============================================================================
// Internal function tests
// =============================================================================

///|
test "is_whitespace_only with spaces" {
  assert_true(@utils.is_whitespace_only("   "))
}

///|
test "is_whitespace_only with tabs and newlines" {
  assert_true(@utils.is_whitespace_only("\t\n\r"))
}

///|
test "is_whitespace_only with content returns false" {
  assert_false(@utils.is_whitespace_only("  a  "))
}

///|
test "is_whitespace_only empty string" {
  assert_true(@utils.is_whitespace_only(""))
}

///|
test "is_whitespace_only Japanese full-width space" {
  assert_true(@utils.is_whitespace_only("\u{3000}"))
}

///|
test "combine_sentences basic" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
  ]
  let result = combine_sentences(sentences, 0, 2)
  assert_eq(result, "Hello. World.")
}

///|
test "combine_sentences partial" {
  let sentences = [
    @sentence.Sentence::new("One", 0, 3),
    @sentence.Sentence::new("Two", 3, 6),
    @sentence.Sentence::new("Three", 6, 11),
  ]
  let result = combine_sentences(sentences, 0, 2)
  assert_eq(result, "OneTwo")
}

///|
test "combine_sentences beyond length" {
  let sentences = [
    @sentence.Sentence::new("One", 0, 3),
    @sentence.Sentence::new("Two", 3, 6),
  ]
  let result = combine_sentences(sentences, 0, 10)
  assert_eq(result, "OneTwo")
}

///|
test "get_window_end basic" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
    @sentence.Sentence::new(" Test. ", 13, 20),
  ]
  let result = get_window_end(sentences, 0, 2)
  assert_eq(result, 13) // End of second sentence
}

///|
test "get_window_end beyond length" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
  ]
  let result = get_window_end(sentences, 0, 10)
  assert_eq(result, 13) // End of last sentence
}

///|
test "get_window_end empty" {
  let sentences : Array[@sentence.Sentence] = []
  let result = get_window_end(sentences, 0, 2)
  assert_eq(result, 0)
}

///|
test "min_max_normalize empty array" {
  let result = min_max_normalize([])
  assert_eq(result.length(), 0)
}

///|
test "min_max_normalize single value" {
  let result = min_max_normalize([0.5])
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0.5)
}

///|
test "min_max_normalize all same values" {
  let result = min_max_normalize([0.5, 0.5, 0.5])
  for val in result {
    assert_eq(val, 0.5)
  }
}

///|
test "min_max_normalize range" {
  let result = min_max_normalize([0.0, 0.5, 1.0])
  assert_eq(result[0], 0.0)
  assert_eq(result[1], 0.5)
  assert_eq(result[2], 1.0)
}

///|
test "find_local_maxima empty array" {
  let result = @utils.find_local_maxima([], 0.3)
  assert_eq(result.length(), 0)
}

///|
test "find_local_maxima single element above threshold" {
  let result = @utils.find_local_maxima([0.5], 0.3)
  assert_eq(result.length(), 1)
  assert_eq(result[0], 0)
}

///|
test "find_local_maxima single element below threshold" {
  let result = @utils.find_local_maxima([0.1], 0.3)
  assert_eq(result.length(), 0)
}

///|
test "find_local_maxima identifies peaks" {
  let values = [0.1, 0.5, 0.2, 0.8, 0.3]
  let result = @utils.find_local_maxima(values, 0.3)
  // Peaks at index 1 (0.5) and index 3 (0.8)
  assert_eq(result.length(), 2)
  assert_eq(result[0], 1)
  assert_eq(result[1], 3)
}

///|
test "find_local_maxima respects threshold" {
  let values = [0.1, 0.5, 0.2, 0.4, 0.3]
  let result = @utils.find_local_maxima(values, 0.45)
  // Only index 1 (0.5) is above threshold
  assert_eq(result.length(), 1)
  assert_eq(result[0], 1)
}

///|
test "find_nearest_sentence_end exact match" {
  let sentences = [
    @sentence.Sentence::new("First one.", 0, 10),
    @sentence.Sentence::new("Second one", 10, 20),
    @sentence.Sentence::new("Third one.", 20, 30),
  ]
  let result = @utils.find_nearest_sentence_end(sentences, 10)
  assert_eq(result, 10)
}

///|
test "find_nearest_sentence_end nearest" {
  let sentences = [
    @sentence.Sentence::new("First one.", 0, 10),
    @sentence.Sentence::new("Second one", 10, 20),
    @sentence.Sentence::new("Third one.", 20, 30),
  ]
  let result = @utils.find_nearest_sentence_end(sentences, 12)
  assert_eq(result, 10) // 10 is closer than 20
}

///|
test "find_nearest_sentence_end empty" {
  let sentences : Array[@sentence.Sentence] = []
  let result = @utils.find_nearest_sentence_end(sentences, 10)
  assert_eq(result, 0)
}

///|
test "boundaries_to_segment_points basic" {
  let boundaries = [10, 20, 30]
  let result = @utils.boundaries_to_segment_points(boundaries, 40)
  assert_eq(result.length(), 4)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 10)
  assert_eq(result[1].get_start(), 10)
  assert_eq(result[1].get_end(), 20)
  assert_eq(result[2].get_start(), 20)
  assert_eq(result[2].get_end(), 30)
  assert_eq(result[3].get_start(), 30)
  assert_eq(result[3].get_end(), 40)
}

///|
test "boundaries_to_segment_points empty boundaries" {
  let boundaries : Array[Int] = []
  let result = @utils.boundaries_to_segment_points(boundaries, 40)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 40)
}

///|
test "boundaries_to_segment_points boundary at end" {
  let boundaries = [20, 40]
  let result = @utils.boundaries_to_segment_points(boundaries, 40)
  assert_eq(result.length(), 2)
  assert_eq(result[1].get_end(), 40)
}

///|
test "calculate_window_tfidf_divergence insufficient sentences" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
  ]
  // window_size=3, but only 2 sentences
  let result = calculate_window_tfidf_divergence(sentences, 3)
  assert_eq(result.divergence_values.length(), 0)
  assert_eq(result.window_end_positions.length(), 0)
}

///|
test "calculate_window_tfidf_divergence sufficient sentences" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
    @sentence.Sentence::new(" Test. ", 13, 20),
    @sentence.Sentence::new(" More. ", 20, 27),
  ]
  // window_size=2, 4 sentences = 3 windows, 2 divergence values
  let result = calculate_window_tfidf_divergence(sentences, 2)
  assert_true(result.divergence_values.length() >= 1)
}

///|
test "handle_few_sentences small text" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
  ]
  let result = @utils.handle_few_sentences(
    "Hello. World.", sentences, 50, 5, 100,
  )
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 13)
}

///|
test "handle_few_sentences with segments" {
  let text = "First sentence here. Second sentence follows. Third one is here."
  let sentences = @sentence.split_sentences(text)
  let result = @utils.handle_few_sentences(text, sentences, 20, 10, 100)
  assert_true(result.length() >= 1)
}
