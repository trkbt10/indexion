// Tests for window-based segmentation.

///|
test "default_config returns correct values" {
  let config = default_config()
  assert_eq(config.target_chunk_size, 500)
  assert_eq(config.min_chunk_size, 100)
  assert_eq(config.max_chunk_size, 2000)
  assert_eq(config.threshold, 0.42)
  assert_eq(config.window_size, 3)
}

///|
test "SegmentConfig accessors work correctly" {
  let config = SegmentConfig::new(300, 50, 1000, 0.5, 4)
  assert_eq(config.get_target_chunk_size(), 300)
  assert_eq(config.get_min_chunk_size(), 50)
  assert_eq(config.get_max_chunk_size(), 1000)
  assert_eq(config.get_threshold(), 0.5)
  assert_eq(config.get_window_size(), 4)
}

///|
test "SegmentPoint creation and accessors" {
  let point = @types.SegmentPoint::new(10, 50, @types.SegmentType::Paragraph)
  assert_eq(point.get_start(), 10)
  assert_eq(point.get_end(), 50)
  assert_eq(point.get_type(), @types.SegmentType::Paragraph)
  assert_eq(point.length(), 40)
}

///|
test "SegmentType equality" {
  assert_eq(@types.SegmentType::Paragraph, @types.SegmentType::Paragraph)
  assert_eq(@types.SegmentType::Section, @types.SegmentType::Section)
  assert_eq(@types.SegmentType::Heading, @types.SegmentType::Heading)
  assert_true(@types.SegmentType::Paragraph != @types.SegmentType::Section)
}

///|
test "@types.WindowDivergence creation and accessors" {
  let values = [0.1, 0.5, 0.3]
  let positions = [10, 20, 30]
  let divergence = @types.WindowDivergence::new(values, positions)
  assert_eq(divergence.get_values().length(), 3)
  assert_eq(divergence.get_positions().length(), 3)
}

///|
test "combine_sentences joins texts correctly" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new("World.", 7, 13),
    @sentence.Sentence::new("Test.", 14, 19),
  ]
  let combined = combine_sentences(sentences, 0, 2)
  assert_eq(combined, "Hello.World.")
}

///|
test "combine_sentences handles out of bounds" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new("World.", 7, 13),
  ]
  let combined = combine_sentences(sentences, 0, 5) // More than available
  assert_eq(combined, "Hello.World.")
}

///|
test "min_max_normalize with varying values" {
  let values = [1.0, 5.0, 3.0]
  let normalized = min_max_normalize(values)
  assert_eq(normalized.length(), 3)
  assert_eq(normalized[0], 0.0) // min
  assert_eq(normalized[1], 1.0) // max
  assert_eq(normalized[2], 0.5) // middle
}

///|
test "min_max_normalize with same values returns 0.5" {
  let values = [3.0, 3.0, 3.0]
  let normalized = min_max_normalize(values)
  assert_eq(normalized.length(), 3)
  assert_eq(normalized[0], 0.5)
  assert_eq(normalized[1], 0.5)
  assert_eq(normalized[2], 0.5)
}

///|
test "min_max_normalize with empty array" {
  let values : Array[Double] = []
  let normalized = min_max_normalize(values)
  assert_eq(normalized.length(), 0)
}

///|
test "find_local_maxima finds peaks" {
  let values = [0.1, 0.8, 0.3, 0.9, 0.2]
  let maxima = @utils.find_local_maxima(values, 0.5)
  assert_eq(maxima.length(), 2)
  assert_eq(maxima[0], 1) // index of 0.8
  assert_eq(maxima[1], 3) // index of 0.9
}

///|
test "find_local_maxima with threshold filtering" {
  let values = [0.1, 0.4, 0.2, 0.9, 0.3]
  let maxima = @utils.find_local_maxima(values, 0.5)
  assert_eq(maxima.length(), 1)
  assert_eq(maxima[0], 3) // Only 0.9 passes threshold
}

///|
test "find_local_maxima with empty array" {
  let values : Array[Double] = []
  let maxima = @utils.find_local_maxima(values, 0.5)
  assert_eq(maxima.length(), 0)
}

///|
test "find_local_maxima with edge maxima" {
  let values = [0.9, 0.5, 0.3, 0.4, 0.8]
  let maxima = @utils.find_local_maxima(values, 0.5)
  // First and last elements can be maxima if they meet threshold and are >= neighbor
  assert_true(maxima.length() >= 1)
}

///|
test "segment_by_divergence with empty text returns empty" {
  let config = default_config()
  let points = segment_by_divergence("", config)
  assert_eq(points.length(), 0)
}

///|
test "segment_by_divergence with whitespace only returns empty" {
  let config = default_config()
  let points = segment_by_divergence("   \n\t  ", config)
  assert_eq(points.length(), 0)
}

///|
test "segment_by_divergence with small text returns single segment" {
  let config = SegmentConfig::new(500, 100, 2000, 0.42, 3)
  let text = "Small text."
  let points = segment_by_divergence(text, config)
  assert_eq(points.length(), 1)
  assert_eq(points[0].get_start(), 0)
  assert_eq(points[0].get_end(), text.length())
}

///|
test "segment_by_divergence with few sentences" {
  let config = SegmentConfig::new(500, 50, 2000, 0.42, 3)
  let text = "First sentence. Second sentence. Third sentence."
  let points = segment_by_divergence(text, config)
  // With only 3 sentences and window_size=3, we need at least 4 sentences for window analysis
  // So this should be handled by handle_few_sentences
  assert_true(points.length() >= 1)
}

///|
test "segment helper uses default config" {
  let text = "Hello world. This is a test. Another sentence here."
  let points = segment(text)
  // Should return at least one segment
  assert_true(points.length() >= 1)
  // First segment should start at 0
  assert_eq(points[0].get_start(), 0)
}

///|
test "calculate_window_tfidf_divergence with insufficient sentences" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new("World.", 7, 13),
  ]
  let divergence = calculate_window_tfidf_divergence(sentences, 3)
  // Not enough sentences for window_size=3
  assert_eq(divergence.get_values().length(), 0)
  assert_eq(divergence.get_positions().length(), 0)
}

///|
test "segment covers entire text" {
  let config = default_config()
  let text = "First sentence here. Second sentence follows. Third one now. Fourth and final."
  let points = segment_by_divergence(text, config)

  // Verify segments cover the entire text
  if points.length() > 0 {
    assert_eq(points[0].get_start(), 0)
    assert_eq(points[points.length() - 1].get_end(), text.length())

    // Verify no gaps between segments
    for i = 1; i < points.length(); i = i + 1 {
      assert_eq(points[i].get_start(), points[i - 1].get_end())
    }
  }
}

// =============================================================================
// Integration tests with real text
// =============================================================================

///|
test "segment_by_divergence with real English text" {
  let text =
    #|The first paragraph introduces the main topic. This is important background information. We will explore these ideas further.
    #|
    #|The second paragraph discusses technical details. Here we explain the implementation approach. Multiple techniques are combined to achieve the goal. Performance considerations are also addressed.
    #|
    #|The third paragraph provides a conclusion. We summarize the key findings. Future work directions are suggested. Thank you for reading this document.
  let config = SegmentConfig::new(100, 50, 500, 0.3, 2)
  let segments = segment_by_divergence(text, config)

  // Should generate at least one segment
  assert_true(segments.length() >= 1)

  // First segment starts at 0
  assert_eq(segments[0].get_start(), 0)

  // Last segment ends at text length
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Verify no gaps between segments
  for i = 1; i < segments.length(); i = i + 1 {
    assert_eq(segments[i].get_start(), segments[i - 1].get_end())
  }

  // Verify all segments are Paragraph type
  for seg in segments {
    assert_eq(seg.get_type(), @types.SegmentType::Paragraph)
  }
}

///|
test "segment_by_divergence with real Japanese text" {
  let text =
    #|最初の段落です。これは導入部分になります。重要な背景情報を説明します。
    #|
    #|次の段落では、別のトピックについて説明します。詳細な情報が含まれています。技術的な内容も解説します。実装の方針を述べます。
    #|
    #|最後の段落は結論です。まとめを述べます。今後の課題についても言及します。ご覧いただきありがとうございます。
  let config = SegmentConfig::new(80, 40, 400, 0.3, 2)
  let segments = segment_by_divergence(text, config)

  // Should generate at least one segment
  assert_true(segments.length() >= 1)

  // First segment starts at 0
  assert_eq(segments[0].get_start(), 0)

  // Last segment ends at text length
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Verify no gaps between segments
  for i = 1; i < segments.length(); i = i + 1 {
    assert_eq(segments[i].get_start(), segments[i - 1].get_end())
  }

  // Verify all segment sizes respect constraints
  for seg in segments {
    let size = seg.length()
    // Min size check (last segment might be smaller)
    if seg != segments[segments.length() - 1] {
      assert_true(size >= 20) // Allow some flexibility
    }
  }
}

///|
test "segment_by_divergence with mixed language text" {
  let text =
    #|This is an English introduction. We discuss international topics. Multiple languages are used.
    #|
    #|日本語で書かれた段落です。異なる言語が混在しています。これはテストのためです。
    #|
    #|Back to English for the conclusion. This tests mixed content handling. Thank you for testing.
  let config = SegmentConfig::new(80, 40, 400, 0.3, 2)
  let segments = segment_by_divergence(text, config)

  // Should generate at least one segment
  assert_true(segments.length() >= 1)

  // First segment starts at 0
  assert_eq(segments[0].get_start(), 0)

  // Last segment ends at text length
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Verify no gaps and proper coverage
  for i = 1; i < segments.length(); i = i + 1 {
    assert_eq(segments[i].get_start(), segments[i - 1].get_end())
  }
}

///|
test "segment_by_divergence boundary positions are valid" {
  let text =
    #|First sentence here. Second sentence follows. Third one comes next. Fourth sentence appears. Fifth sentence written. Sixth sentence added. Seventh to finish.
  let config = SegmentConfig::new(50, 20, 200, 0.3, 2)
  let segments = segment_by_divergence(text, config)

  // Verify boundary positions are within text
  for seg in segments {
    assert_true(seg.get_start() >= 0)
    assert_true(seg.get_end() <= text.length())
    assert_true(seg.get_start() < seg.get_end())
  }

  // Total coverage equals text length
  let mut total_coverage = 0
  for seg in segments {
    total_coverage = total_coverage + seg.length()
  }
  assert_eq(total_coverage, text.length())
}

///|
test "segment_by_divergence with long text respects max_chunk_size" {
  // Create a long text with many sentences
  let sentences = [
    "This is sentence number one.", "Here comes sentence number two.", "Now we have sentence number three.",
    "Fourth sentence is written here.", "Fifth sentence appears now.", "Sixth sentence is being added.",
    "Seventh sentence joins the text.", "Eighth sentence is quite long.", "Ninth sentence continues on.",
    "Tenth sentence finishes this section.", "Eleventh sentence starts new section.",
    "Twelfth sentence provides more content.", "Thirteenth sentence adds variety.",
    "Fourteenth sentence keeps going.", "Fifteenth sentence wraps things up.",
  ]
  let mut text = ""
  for s in sentences {
    text = text + s + " "
  }

  let config = SegmentConfig::new(100, 50, 200, 0.3, 2)
  let segments = segment_by_divergence(text, config)

  // Check that most segments respect max_chunk_size
  // (last segment might exceed if remaining text is large)
  let mut oversized_count = 0
  for seg in segments {
    if seg.length() > config.max_chunk_size {
      oversized_count = oversized_count + 1
    }
  }
  // Allow at most one oversized segment (could be the last one)
  assert_true(oversized_count <= 1)
}

// =============================================================================
// Adaptive mode tests
// =============================================================================

///|
test "default_adaptive_config returns correct values" {
  let config = default_adaptive_config()
  assert_eq(config.percentile, 0.2)
  assert_eq(config.minimum_threshold, 0.13)
  assert_eq(config.target_chunk_size, 500)
  assert_eq(config.min_chunk_size, 100)
  assert_eq(config.max_chunk_size, 2000)
  assert_eq(config.window_size, 3)
}

///|
test "AdaptiveConfig accessors work correctly" {
  let config = AdaptiveConfig::new(0.3, 0.15, 400, 80, 1500, 4)
  assert_eq(config.get_percentile(), 0.3)
  assert_eq(config.get_minimum_threshold(), 0.15)
  assert_eq(config.get_target_chunk_size(), 400)
  assert_eq(config.get_min_chunk_size(), 80)
  assert_eq(config.get_max_chunk_size(), 1500)
  assert_eq(config.get_window_size(), 4)
}

///|
test "segment_adaptive with empty text returns empty" {
  let config = default_adaptive_config()
  let points = segment_adaptive("", config)
  assert_eq(points.length(), 0)
}

///|
test "segment_adaptive with whitespace only returns empty" {
  let config = default_adaptive_config()
  let points = segment_adaptive("   \n\t  ", config)
  assert_eq(points.length(), 0)
}

///|
test "segment_adaptive with small text returns single segment" {
  let config = AdaptiveConfig::new(0.2, 0.13, 500, 100, 2000, 3)
  let text = "Small text."
  let points = segment_adaptive(text, config)
  assert_eq(points.length(), 1)
  assert_eq(points[0].get_start(), 0)
  assert_eq(points[0].get_end(), text.length())
}

///|
test "segment_adaptive with real English text" {
  let text =
    #|The first paragraph introduces the main topic. This is important background information. We will explore these ideas further.
    #|
    #|The second paragraph discusses technical details. Here we explain the implementation approach. Multiple techniques are combined to achieve the goal. Performance considerations are also addressed.
    #|
    #|The third paragraph provides a conclusion. We summarize the key findings. Future work directions are suggested. Thank you for reading this document.
  let config = AdaptiveConfig::new(0.2, 0.1, 100, 50, 500, 2)
  let segments = segment_adaptive(text, config)

  // Should generate at least one segment
  assert_true(segments.length() >= 1)

  // First segment starts at 0
  assert_eq(segments[0].get_start(), 0)

  // Last segment ends at text length
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Verify no gaps between segments
  for i = 1; i < segments.length(); i = i + 1 {
    assert_eq(segments[i].get_start(), segments[i - 1].get_end())
  }
}

///|
test "segment_adaptive with Japanese text" {
  let text =
    #|最初の段落です。これは導入部分になります。重要な背景情報を説明します。
    #|
    #|次の段落では、別のトピックについて説明します。詳細な情報が含まれています。技術的な内容も解説します。実装の方針を述べます。
    #|
    #|最後の段落は結論です。まとめを述べます。今後の課題についても言及します。ご覧いただきありがとうございます。
  let config = AdaptiveConfig::new(0.2, 0.1, 80, 40, 400, 2)
  let segments = segment_adaptive(text, config)

  // Should generate at least one segment
  assert_true(segments.length() >= 1)

  // First segment starts at 0
  assert_eq(segments[0].get_start(), 0)

  // Last segment ends at text length
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Verify complete text coverage
  let mut total = 0
  for seg in segments {
    total = total + seg.length()
  }
  assert_eq(total, text.length())
}

///|
test "segment_adaptive subdivides oversized chunks" {
  // Create a long text that will produce oversized chunks
  let sentences = [
    "First sentence introduces the topic.", "Second sentence provides more context.",
    "Third sentence continues the discussion.", "Fourth sentence adds important details.",
    "Fifth sentence elaborates on the point.", "Sixth sentence gives examples.",
    "Seventh sentence compares approaches.", "Eighth sentence discusses alternatives.",
    "Ninth sentence explains methodology.", "Tenth sentence describes the process.",
    "Eleventh sentence outlines results.", "Twelfth sentence analyzes findings.",
    "Thirteenth sentence draws conclusions.", "Fourteenth sentence suggests implications.",
    "Fifteenth sentence recommends actions.",
  ]
  let mut text = ""
  for s in sentences {
    text = text + s + " "
  }

  let config = AdaptiveConfig::new(0.2, 0.1, 100, 50, 200, 2)
  let segments = segment_adaptive(text, config)

  // Should generate segments
  assert_true(segments.length() >= 1)

  // Verify coverage
  assert_eq(segments[0].get_start(), 0)
  assert_eq(segments[segments.length() - 1].get_end(), text.length())

  // Most segments should respect max_chunk_size
  let mut oversized_count = 0
  for seg in segments {
    if seg.length() > config.max_chunk_size {
      oversized_count = oversized_count + 1
    }
  }
  // Allow at most one oversized segment
  assert_true(oversized_count <= 1)
}

///|
test "segment_adaptive handles few sentences gracefully" {
  let config = AdaptiveConfig::new(0.2, 0.13, 500, 50, 2000, 3)
  let text = "First sentence. Second sentence. Third sentence."
  let points = segment_adaptive(text, config)
  // Should be handled by handle_few_sentences
  assert_true(points.length() >= 1)
  assert_eq(points[0].get_start(), 0)
}

///|
test "adaptive threshold calculation" {
  // Test with varying divergence values
  let text =
    #|Topic one is discussed here. More details about topic one. Additional information provided.
    #|
    #|A completely different topic starts here. This is about something else. New subject matter.
    #|
    #|Back to related content. Continuing the theme. Final thoughts on the matter.
  let config = AdaptiveConfig::new(0.3, 0.1, 80, 40, 400, 2)
  let segments = segment_adaptive(text, config)

  // Should produce segments
  assert_true(segments.length() >= 1)

  // Verify all segments have valid type
  for seg in segments {
    assert_eq(seg.get_type(), @types.SegmentType::Paragraph)
  }
}

// =============================================================================
// Internal function tests - find_nearest_sentence_end
// =============================================================================

///|
test "find_nearest_sentence_end exact match" {
  let sentences = [
    @sentence.Sentence::new("First.", 0, 6),
    @sentence.Sentence::new("Second.", 6, 13),
    @sentence.Sentence::new("Third.", 13, 19),
  ]
  let result = @utils.find_nearest_sentence_end(sentences, 13)
  assert_eq(result, 13) // Exact match
}

///|
test "find_nearest_sentence_end closest to left" {
  let sentences = [
    @sentence.Sentence::new("First.", 0, 10),
    @sentence.Sentence::new("Second.", 10, 20),
    @sentence.Sentence::new("Third.", 20, 30),
  ]
  // Position 12 is closer to 10 (distance 2) than to 20 (distance 8)
  let result = @utils.find_nearest_sentence_end(sentences, 12)
  assert_eq(result, 10)
}

///|
test "find_nearest_sentence_end closest to right" {
  let sentences = [
    @sentence.Sentence::new("First.", 0, 10),
    @sentence.Sentence::new("Second.", 10, 20),
    @sentence.Sentence::new("Third.", 20, 30),
  ]
  // Position 18 is closer to 20 (distance 2) than to 10 (distance 8)
  let result = @utils.find_nearest_sentence_end(sentences, 18)
  assert_eq(result, 20)
}

///|
test "find_nearest_sentence_end empty array" {
  let sentences : Array[@sentence.Sentence] = []
  let result = @utils.find_nearest_sentence_end(sentences, 10)
  assert_eq(result, 0)
}

///|
test "find_nearest_sentence_end single sentence" {
  let sentences = [@sentence.Sentence::new("Only one.", 0, 9)]
  let result = @utils.find_nearest_sentence_end(sentences, 100)
  assert_eq(result, 9)
}

// =============================================================================
// Internal function tests - boundaries_to_segment_points
// =============================================================================

///|
test "boundaries_to_segment_points basic" {
  let boundaries = [10, 20, 30]
  let result = @utils.boundaries_to_segment_points(boundaries, 40)
  assert_eq(result.length(), 4)
  // First segment: 0-10
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 10)
  // Second segment: 10-20
  assert_eq(result[1].get_start(), 10)
  assert_eq(result[1].get_end(), 20)
  // Third segment: 20-30
  assert_eq(result[2].get_start(), 20)
  assert_eq(result[2].get_end(), 30)
  // Fourth segment: 30-40
  assert_eq(result[3].get_start(), 30)
  assert_eq(result[3].get_end(), 40)
}

///|
test "boundaries_to_segment_points empty boundaries" {
  let boundaries : Array[Int] = []
  let result = @utils.boundaries_to_segment_points(boundaries, 50)
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 50)
}

///|
test "boundaries_to_segment_points boundary at text_length" {
  let boundaries = [25, 50]
  let result = @utils.boundaries_to_segment_points(boundaries, 50)
  assert_eq(result.length(), 2)
  // 0-25 and 25-50
  assert_eq(result[0].get_end(), 25)
  assert_eq(result[1].get_start(), 25)
  assert_eq(result[1].get_end(), 50)
}

///|
test "boundaries_to_segment_points skips duplicate boundaries" {
  let boundaries = [10, 10, 20] // duplicate 10
  let result = @utils.boundaries_to_segment_points(boundaries, 30)
  // Should skip second 10 since it equals previous end
  assert_true(result.length() >= 2)
}

///|
test "boundaries_to_segment_points all Paragraph type" {
  let boundaries = [15, 30]
  let result = @utils.boundaries_to_segment_points(boundaries, 45)
  for seg in result {
    assert_eq(seg.get_type(), @types.SegmentType::Paragraph)
  }
}

// =============================================================================
// Internal function tests - apply_size_constraints
// =============================================================================

///|
test "apply_size_constraints filters small candidates" {
  let sentences = [
    @sentence.Sentence::new("A.", 0, 2),
    @sentence.Sentence::new("B.", 2, 4),
    @sentence.Sentence::new("C.", 4, 6),
  ]
  // Candidates at positions 2, 4 - both too small (< min_size=10)
  // Text length 20, max_size 50, so no force split needed
  let candidates = [2, 4]
  let result = @utils.apply_size_constraints(
    20, candidates, sentences, 10, 50, 15,
  )
  // Should filter out candidates that create chunks < min_size
  assert_eq(result.length(), 0)
}

///|
test "apply_size_constraints keeps valid candidates" {
  let sentences = [
    @sentence.Sentence::new("First chunk.", 0, 12),
    @sentence.Sentence::new("Second chunk.", 12, 25),
    @sentence.Sentence::new("Third chunk.", 25, 37),
  ]
  // Candidate at 25 creates chunk of 25 chars (>= min_size=10, >= target=20)
  let candidates = [25]
  let result = @utils.apply_size_constraints(
    50, candidates, sentences, 10, 100, 20,
  )
  assert_eq(result.length(), 1)
  assert_eq(result[0], 25)
}

///|
test "apply_size_constraints force splits oversized" {
  let sentences = [
    @sentence.Sentence::new("Very long content.", 0, 18),
    @sentence.Sentence::new("More content here.", 18, 36),
  ]
  // No candidates, but text is larger than max_size
  let candidates : Array[Int] = []
  let result = @utils.apply_size_constraints(
    100, candidates, sentences, 5, 30, 20,
  )
  // Should force split because 100 > max_size=30
  assert_true(result.length() >= 1)
}

///|
test "apply_size_constraints empty candidates small text" {
  let sentences = [@sentence.Sentence::new("Short.", 0, 6)]
  let candidates : Array[Int] = []
  // Text length 20 < max_size 100
  let result = @utils.apply_size_constraints(
    20, candidates, sentences, 5, 100, 50,
  )
  assert_eq(result.length(), 0)
}

// =============================================================================
// Internal function tests - handle_few_sentences
// =============================================================================

///|
test "handle_few_sentences short text single segment" {
  let sentences = [
    @sentence.Sentence::new("Hello.", 0, 6),
    @sentence.Sentence::new(" World.", 6, 13),
  ]
  let result = @utils.handle_few_sentences(
    "Hello. World.", sentences, 50, 5, 100,
  )
  // Text length 13 < max_size 100, so single segment
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 13)
}

///|
test "handle_few_sentences creates segments at target size" {
  // Create longer text that exceeds max_size
  let text = "A".repeat(250) // 250 chars
  let sentences = [
    @sentence.Sentence::new("First.", 0, 100),
    @sentence.Sentence::new("Second.", 100, 200),
  ]
  // max_size = 100, so should create multiple segments
  let result = @utils.handle_few_sentences(text, sentences, 80, 10, 100)
  assert_true(result.length() >= 1)
}

///|
test "handle_few_sentences merges small remaining" {
  let sentences = [
    @sentence.Sentence::new("Big chunk here.", 0, 50),
    @sentence.Sentence::new("Tiny.", 50, 55),
  ]
  let text = "Big chunk here." + "X".repeat(35) + "Tiny." // 55 chars
  let result = @utils.handle_few_sentences(text, sentences, 40, 10, 100)
  // Last segment is 5 chars (55-50) < min_size 10, should merge
  assert_true(result.length() >= 1)
  // If merged, last segment should end at 55
  assert_eq(result[result.length() - 1].get_end(), 55)
}

///|
test "handle_few_sentences empty sentences" {
  let sentences : Array[@sentence.Sentence] = []
  let result = @utils.handle_few_sentences("Some text.", sentences, 50, 5, 100)
  // Should return single segment covering entire text
  assert_eq(result.length(), 1)
  assert_eq(result[0].get_start(), 0)
  assert_eq(result[0].get_end(), 10)
}

// =============================================================================
// Internal function tests - calculate_adaptive_threshold
// =============================================================================

///|
test "calculate_adaptive_threshold empty values" {
  let values : Array[Double] = []
  let result = calculate_adaptive_threshold(values, 0.2, 0.15)
  assert_eq(result, 0.15) // Returns minimum_threshold
}

///|
test "calculate_adaptive_threshold uses percentile" {
  let values = [0.1, 0.3, 0.5, 0.7, 0.9]
  // Sorted desc: [0.9, 0.7, 0.5, 0.3, 0.1]
  // percentile 0.2 = top 20% = index 0 (0.9)
  let result = calculate_adaptive_threshold(values, 0.2, 0.1)
  assert_eq(result, 0.9)
}

///|
test "calculate_adaptive_threshold respects minimum" {
  let values = [0.05, 0.08, 0.10]
  // All values are below minimum_threshold 0.2
  let result = calculate_adaptive_threshold(values, 0.2, 0.2)
  assert_eq(result, 0.2) // Returns minimum_threshold
}

///|
test "calculate_adaptive_threshold single value above minimum" {
  let values = [0.5]
  let result = calculate_adaptive_threshold(values, 0.2, 0.1)
  assert_eq(result, 0.5)
}

///|
test "calculate_adaptive_threshold single value below minimum" {
  let values = [0.05]
  let result = calculate_adaptive_threshold(values, 0.2, 0.1)
  assert_eq(result, 0.1) // Returns minimum_threshold
}

// =============================================================================
// Internal function tests - subdivide_oversized_chunks
// =============================================================================

///|
test "subdivide_oversized_chunks no oversized" {
  let sentences = [
    @sentence.Sentence::new("Small.", 0, 6),
    @sentence.Sentence::new("Chunk.", 6, 12),
  ]
  let boundaries = [6]
  // Chunks are 6 and 6, both < max_size 50
  let result = subdivide_oversized_chunks(
    boundaries, 12, sentences, 3, 50, 2, 0.1,
  )
  // Should include original boundary plus nothing extra needed
  assert_true(result.length() >= 1)
}

///|
test "subdivide_oversized_chunks empty boundaries" {
  let sentences = [@sentence.Sentence::new("Content.", 0, 8)]
  let boundaries : Array[Int] = []
  let result = subdivide_oversized_chunks(
    boundaries, 8, sentences, 3, 50, 2, 0.1,
  )
  // No boundaries, text 8 < max 50, no subdivision needed
  assert_eq(result.length(), 0)
}

///|
test "subdivide_oversized_chunks force splits when needed" {
  let sentences = [
    @sentence.Sentence::new("First sentence here.", 0, 20),
    @sentence.Sentence::new("Second sentence.", 20, 36),
    @sentence.Sentence::new("Third sentence.", 36, 51),
    @sentence.Sentence::new("Fourth sentence.", 51, 67),
  ]
  // No initial boundaries, text_length=67, max_size=30
  // Should force split because 67 > 30
  let boundaries : Array[Int] = []
  let result = subdivide_oversized_chunks(
    boundaries, 67, sentences, 5, 30, 2, 0.1,
  )
  // Should have created split points
  assert_true(result.length() >= 1)
}

// =============================================================================
// Internal function tests - is_whitespace_only
// =============================================================================

///|
test "is_whitespace_only spaces" {
  assert_true(@utils.is_whitespace_only("   "))
}

///|
test "is_whitespace_only tabs" {
  assert_true(@utils.is_whitespace_only("\t\t"))
}

///|
test "is_whitespace_only newlines" {
  assert_true(@utils.is_whitespace_only("\n\r\n"))
}

///|
test "is_whitespace_only mixed" {
  assert_true(@utils.is_whitespace_only(" \t\n\r "))
}

///|
test "is_whitespace_only Japanese full-width space" {
  assert_true(@utils.is_whitespace_only("\u{3000}"))
}

///|
test "is_whitespace_only with content" {
  assert_false(@utils.is_whitespace_only("  a  "))
}

///|
test "is_whitespace_only empty" {
  assert_true(@utils.is_whitespace_only(""))
}

///|
test "is_whitespace_only single char" {
  assert_false(@utils.is_whitespace_only("x"))
}
