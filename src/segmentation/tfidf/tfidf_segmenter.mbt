// TF-IDF based segmentation implementation.
// Uses TF-IDF cosine distance between adjacent sentence windows to detect
// semantic boundaries without external API calls.

///|
/// Combine multiple sentences into a single text string.
fn combine_sentences(
  sentences : Array[@sentence.Sentence],
  start : Int,
  count : Int,
) -> String {
  let buf = StringBuilder::new()
  let end = if start + count > sentences.length() {
    sentences.length()
  } else {
    start + count
  }
  for i = start; i < end; i = i + 1 {
    buf.write_string(sentences[i].get_text())
  }
  buf.to_string()
}

///|
/// Get the end position of the last sentence in a window.
fn get_window_end(
  sentences : Array[@sentence.Sentence],
  start : Int,
  count : Int,
) -> Int {
  let end_index = if start + count > sentences.length() {
    sentences.length()
  } else {
    start + count
  }
  if end_index > 0 {
    sentences[end_index - 1].get_end()
  } else {
    0
  }
}

///|
/// Normalize an array of values using Min-Max normalization.
/// Returns values in range [0, 1].
fn min_max_normalize(values : Array[Double]) -> Array[Double] {
  if values.length() == 0 {
    return []
  }

  // Find min and max
  let mut min_val = values[0]
  let mut max_val = values[0]
  for i = 1; i < values.length(); i = i + 1 {
    if values[i] < min_val {
      min_val = values[i]
    }
    if values[i] > max_val {
      max_val = values[i]
    }
  }

  // Handle case where all values are the same
  if max_val == min_val {
    let result : Array[Double] = []
    for _ in values {
      result.push(0.5)
    }
    return result
  }

  // Normalize
  let range = max_val - min_val
  let result : Array[Double] = []
  for value in values {
    result.push((value - min_val) / range)
  }
  result
}

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
    windows.push(combine_sentences(sentences, i, window_size))
    window_ends.push(get_window_end(sentences, i, window_size))
  }

  // Calculate TF-IDF distances between adjacent windows
  let tfidf_values = @text_tfidf.calculate_adjacent_tfidf_distance(windows)

  // Normalize TF-IDF values
  let normalized_tfidf = min_max_normalize(tfidf_values)

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
