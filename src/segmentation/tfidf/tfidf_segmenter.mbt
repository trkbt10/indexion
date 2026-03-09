// TF-IDF based segmentation implementation.
// Uses TF-IDF cosine distance between adjacent sentence windows to detect
// semantic boundaries without external API calls.
// Uses shared utilities from segmentation/utils for common operations.

///|
/// Calculate TF-IDF divergence between adjacent sentence windows.
pub fn calculate_window_tfidf_divergence(
  sentences : Array[@sentence.Sentence],
  window_size : Int,
) -> @types.WindowDivergence {
  let divergence_values : Array[Double] = []
  let window_end_positions : Array[Int] = []

  // Need at least window_size + 1 sentences to compare two windows
  if sentences.length() < window_size + 1 {
    return @types.WindowDivergence::new(divergence_values, window_end_positions)
  }

  // Build windows
  let windows : Array[String] = []
  let window_ends : Array[Int] = []

  let num_windows = sentences.length() - window_size + 1
  for i = 0; i < num_windows; i = i + 1 {
    windows.push(@utils.combine_sentences(sentences, i, window_size))
    window_ends.push(@utils.get_window_end(sentences, i, window_size))
  }

  // Tokenize windows
  let tokenized : Array[Array[String]] = []
  for w in windows {
    tokenized.push(@tokenizer.tokenize_for_tfidf(w))
  }
  // Calculate TF-IDF distances between adjacent windows
  let tfidf_values = @text_tfidf.calculate_adjacent_tfidf_distance_from_tokenized(
    tokenized,
  )

  // Normalize TF-IDF values
  let normalized_tfidf = @utils.min_max_normalize(tfidf_values)

  // Build result
  let length = if normalized_tfidf.length() < window_ends.length() - 1 {
    normalized_tfidf.length()
  } else {
    window_ends.length() - 1
  }

  for i = 0; i < length; i = i + 1 {
    divergence_values.push(normalized_tfidf[i])
    window_end_positions.push(window_ends[i])
  }

  @types.WindowDivergence::new(divergence_values, window_end_positions)
}

///|
/// Segment text using TF-IDF based semantic detection.
pub fn segment_by_tfidf(
  text : String,
  config : TfidfConfig,
) -> Array[@types.SegmentPoint] {
  // Handle empty or whitespace-only text
  if text.length() == 0 || @utils.is_whitespace_only(text) {
    return []
  }

  let text_length = text.length()

  // If text is smaller than min_chunk_size, return as single segment
  if text_length <= config.min_chunk_size {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  // Split into sentences
  let sentences = @sentence.split_sentences(text)

  if sentences.length() == 0 {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  // If not enough sentences for window analysis
  if sentences.length() < config.window_size + 1 {
    return @utils.handle_few_sentences(
      text,
      sentences,
      config.target_chunk_size,
      config.min_chunk_size,
      config.max_chunk_size,
    )
  }

  // Calculate window divergence
  let divergence = calculate_window_tfidf_divergence(
    sentences,
    config.window_size,
  )

  // Find local maxima above threshold
  let maxima_indices = @utils.find_local_maxima(
    divergence.divergence_values,
    config.tfidf_threshold,
  )

  // Convert maxima indices to positions
  let candidate_positions : Array[Int] = []
  for idx in maxima_indices {
    let pos = divergence.window_end_positions[idx]
    if pos > 0 {
      candidate_positions.push(pos)
    }
  }

  // Apply size constraints
  let final_boundaries = @utils.apply_size_constraints(
    text_length,
    candidate_positions,
    sentences,
    config.min_chunk_size,
    config.max_chunk_size,
    config.target_chunk_size,
  )

  // Convert to segment points
  let points = @utils.boundaries_to_segment_points(
    final_boundaries, text_length,
  )

  if points.length() > 0 {
    return points
  }

  [@types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph)]
}

///|
/// Segment text using TF-IDF strategy with default configuration.
pub fn segment(text : String) -> Array[@types.SegmentPoint] {
  segment_by_tfidf(text, TfidfConfig::new())
}

///|
/// Implement SegmentationStrategy trait for TfidfStrategy.
pub impl @types.SegmentationStrategy for TfidfStrategy with name(self) {
  ignore(self)
  "tfidf"
}

///|
pub impl @types.SegmentationStrategy for TfidfStrategy with segment(self, text) {
  segment_by_tfidf(text, self.config)
}
