// TF-IDF based segmentation implementation.
// Uses TF-IDF cosine distance between adjacent sentence windows to detect
// semantic boundaries without external API calls.

///|
/// Check if a string contains only whitespace.
fn is_whitespace_only(s : String) -> Bool {
  let chars = s.to_array()
  for c in chars {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\u{3000}' {
      return false
    }
  }
  true
}

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
/// Find local maxima indices where values exceed the threshold.
fn find_local_maxima(values : Array[Double], threshold : Double) -> Array[Int] {
  let maxima : Array[Int] = []

  if values.length() < 3 {
    for i = 0; i < values.length(); i = i + 1 {
      if values[i] >= threshold {
        maxima.push(i)
      }
    }
    return maxima
  }

  // Check first element
  if values[0] >= threshold && values[0] >= values[1] {
    maxima.push(0)
  }

  // Check middle elements
  for i = 1; i < values.length() - 1; i = i + 1 {
    if values[i] >= threshold &&
      values[i] >= values[i - 1] &&
      values[i] >= values[i + 1] {
      maxima.push(i)
    }
  }

  // Check last element
  let last_idx = values.length() - 1
  if values[last_idx] >= threshold && values[last_idx] >= values[last_idx - 1] {
    maxima.push(last_idx)
  }

  maxima
}

///|
/// Find the nearest sentence boundary to a target position.
fn find_nearest_sentence_end(
  sentences : Array[@sentence.Sentence],
  target_pos : Int,
) -> Int {
  let mut nearest_end = 0
  let mut min_distance = 2147483647 // Max Int

  for s in sentences {
    let end_pos = s.get_end()
    let distance = if end_pos > target_pos {
      end_pos - target_pos
    } else {
      target_pos - end_pos
    }
    if distance < min_distance {
      min_distance = distance
      nearest_end = end_pos
    }
  }

  nearest_end
}

///|
/// Apply size constraints to candidate boundary positions.
fn apply_size_constraints(
  text_length : Int,
  candidate_positions : Array[Int],
  sentences : Array[@sentence.Sentence],
  min_size : Int,
  max_size : Int,
  target_size : Int,
) -> Array[Int] {
  let final_boundaries : Array[Int] = []
  let mut last_boundary = 0

  // Sort candidates
  let sorted_candidates = candidate_positions.copy()
  sorted_candidates.sort_by(fn(a, b) { a.compare(b) })

  if sorted_candidates.length() > 0 {
    for pos in sorted_candidates {
      // Force split if current segment exceeds max_size
      while pos - last_boundary > max_size {
        let force_split_target = last_boundary + max_size
        let split_point = find_nearest_sentence_end(
          sentences, force_split_target,
        )

        if split_point > last_boundary && split_point < pos {
          final_boundaries.push(split_point)
          last_boundary = split_point
          continue
        }

        // Fall back to hard split
        let force_split = last_boundary + max_size
        if force_split < pos {
          final_boundaries.push(force_split)
          last_boundary = force_split
          continue
        }

        break
      }

      let chunk_size = pos - last_boundary

      // Skip if too small
      if chunk_size < min_size {
        continue
      }

      // Accept if meets target or is close to max
      if chunk_size >= target_size || chunk_size > max_size * 8 / 10 {
        final_boundaries.push(pos)
        last_boundary = pos
      }
    }
  }

  // Handle remaining content
  while text_length - last_boundary > max_size {
    let force_split_target = last_boundary + max_size
    let split_point = find_nearest_sentence_end(sentences, force_split_target)

    if split_point > last_boundary && split_point < text_length {
      final_boundaries.push(split_point)
      last_boundary = split_point
      continue
    }

    // Fall back to hard split
    let force_split = if last_boundary + max_size < text_length {
      last_boundary + max_size
    } else {
      text_length
    }
    if force_split > last_boundary && force_split < text_length {
      final_boundaries.push(force_split)
      last_boundary = force_split
      continue
    }

    break
  }

  final_boundaries
}

///|
/// Convert boundary positions to SegmentPoints.
fn boundaries_to_segment_points(
  boundaries : Array[Int],
  text_length : Int,
) -> Array[@types.SegmentPoint] {
  let points : Array[@types.SegmentPoint] = []
  let mut start = 0

  for boundary in boundaries {
    if boundary > start {
      points.push(
        @types.SegmentPoint::new(start, boundary, @types.SegmentType::Paragraph),
      )
      start = boundary
    }
  }

  // Add final segment
  if start < text_length {
    points.push(
      @types.SegmentPoint::new(
        start,
        text_length,
        @types.SegmentType::Paragraph,
      ),
    )
  }

  points
}

///|
/// Handle case when there are too few sentences for window analysis.
fn handle_few_sentences(
  text : String,
  sentences : Array[@sentence.Sentence],
  target_size : Int,
  min_size : Int,
  max_size : Int,
) -> Array[@types.SegmentPoint] {
  let text_length = text.length()

  if text_length <= max_size {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  let points : Array[@types.SegmentPoint] = []
  let mut start = 0

  for s in sentences {
    if s.get_end() - start >= target_size {
      points.push(
        @types.SegmentPoint::new(
          start,
          s.get_end(),
          @types.SegmentType::Paragraph,
        ),
      )
      start = s.get_end()
    }
  }

  // Handle remaining text
  if start < text_length {
    if points.length() > 0 && text_length - start < min_size {
      // Merge with last segment if too small
      let last = points[points.length() - 1]
      points[points.length() - 1] = @types.SegmentPoint::new(
        last.get_start(),
        text_length,
        last.get_type(),
      )
    } else {
      points.push(
        @types.SegmentPoint::new(
          start,
          text_length,
          @types.SegmentType::Paragraph,
        ),
      )
    }
  }

  if points.length() > 0 {
    return points
  }

  [@types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph)]
}

///|
/// Segment text using TF-IDF based semantic detection.
pub fn segment_by_tfidf(
  text : String,
  config : TfidfConfig,
) -> Array[@types.SegmentPoint] {
  // Handle empty or whitespace-only text
  if text.length() == 0 || is_whitespace_only(text) {
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
    return handle_few_sentences(
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
  let maxima_indices = find_local_maxima(
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
  let final_boundaries = apply_size_constraints(
    text_length,
    candidate_positions,
    sentences,
    config.min_chunk_size,
    config.max_chunk_size,
    config.target_chunk_size,
  )

  // Convert to segment points
  let points = boundaries_to_segment_points(final_boundaries, text_length)

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
