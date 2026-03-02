// Segmentation functions using window divergence.

///|
/// Default configuration values.
let default_target_chunk_size : Int = 500

///|
let default_min_chunk_size : Int = 100

///|
let default_max_chunk_size : Int = 2000

///|
let default_threshold : Double = 0.42

///|
let default_window_size : Int = 3

///|
/// Create a default SegmentConfig.
pub fn default_config() -> SegmentConfig {
  SegmentConfig::new(
    default_target_chunk_size, default_min_chunk_size, default_max_chunk_size, default_threshold,
    default_window_size,
  )
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
    let distance = if s.get_end() > target_pos {
      s.get_end() - target_pos
    } else {
      target_pos - s.get_end()
    }
    if distance < min_distance {
      min_distance = distance
      nearest_end = s.get_end()
    }
  }

  nearest_end
}

///|
/// Convert boundary positions to @types.SegmentPoints.
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
/// Check if a string is whitespace only.
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
/// Segment text using TF-IDF divergence between sentence windows.
/// Returns an array of @types.SegmentPoints representing text boundaries.
pub fn segment_by_divergence(
  text : String,
  config : SegmentConfig,
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
    config.threshold,
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
/// Segment text using default configuration.
pub fn segment(text : String) -> Array[@types.SegmentPoint] {
  segment_by_divergence(text, default_config())
}

///|
/// Default adaptive configuration values.
let default_adaptive_percentile : Double = 0.2

///|
let default_adaptive_minimum_threshold : Double = 0.13

///|
/// Create a default AdaptiveConfig.
pub fn default_adaptive_config() -> AdaptiveConfig {
  AdaptiveConfig::new(
    default_adaptive_percentile, default_adaptive_minimum_threshold, default_target_chunk_size,
    default_min_chunk_size, default_max_chunk_size, default_window_size,
  )
}

///|
/// Calculate adaptive threshold from divergence values.
/// Uses percentile of sorted values with a minimum floor.
fn calculate_adaptive_threshold(
  divergence_values : Array[Double],
  percentile : Double,
  minimum_threshold : Double,
) -> Double {
  if divergence_values.length() == 0 {
    return minimum_threshold
  }

  // Sort in descending order
  let sorted = divergence_values.copy()
  sorted.sort_by(fn(a, b) { b.compare(a) })

  // Calculate percentile index (top percentile%)
  let percentile_index = if sorted.length().to_double() * percentile - 1.0 > 0.0 {
    (sorted.length().to_double() * percentile - 1.0).to_int()
  } else {
    0
  }

  let percentile_threshold = sorted[percentile_index]

  // Return max of percentile threshold and minimum threshold
  if percentile_threshold > minimum_threshold {
    percentile_threshold
  } else {
    minimum_threshold
  }
}

///|
/// Subdivide oversized chunks recursively.
/// Applies finer-grained segmentation to chunks exceeding max_chunk_size.
fn subdivide_oversized_chunks(
  boundaries : Array[Int],
  text_length : Int,
  sentences : Array[@sentence.Sentence],
  min_size : Int,
  max_size : Int,
  window_size : Int,
  minimum_threshold : Double,
) -> Array[Int] {
  let result : Array[Int] = []
  let mut last_boundary = 0
  let all_positions = boundaries.copy()
  all_positions.push(text_length)

  for pos in all_positions {
    let chunk_size = pos - last_boundary

    if chunk_size > max_size {
      // Find sentences within this chunk
      let chunk_sentences : Array[@sentence.Sentence] = []
      for s in sentences {
        if s.get_start() >= last_boundary && s.get_end() <= pos {
          chunk_sentences.push(s)
        }
      }

      // Use smaller window size for subdivision
      let sub_window_size = if window_size / 2 > 1 {
        window_size / 2
      } else {
        1
      }

      if chunk_sentences.length() >= sub_window_size + 1 {
        let sub_divergence = calculate_window_tfidf_divergence(
          chunk_sentences, sub_window_size,
        )

        if sub_divergence.divergence_values.length() > 0 {
          // Use median as threshold for subdivision
          let sorted_div = sub_divergence.divergence_values.copy()
          sorted_div.sort_by(fn(a, b) { b.compare(a) })
          let median_index = sorted_div.length() / 2
          let median_threshold = sorted_div[median_index]
          let threshold = if median_threshold > minimum_threshold {
            median_threshold
          } else {
            minimum_threshold
          }

          let local_maxima = find_local_maxima(
            sub_divergence.divergence_values,
            threshold,
          )
          let candidate_positions : Array[Int] = []
          for idx in local_maxima {
            let candidate = sub_divergence.window_end_positions[idx]
            if candidate > last_boundary && candidate < pos {
              candidate_positions.push(candidate)
            }
          }
          candidate_positions.sort_by(fn(a, b) { a.compare(b) })

          let mut previous = last_boundary
          for candidate in candidate_positions {
            if candidate - previous >= min_size && pos - candidate >= min_size {
              result.push(candidate)
              previous = candidate
            }
          }
        }
      }

      // Force split remaining oversized portions
      let mut current_boundary = if result.length() > 0 {
        result[result.length() - 1]
      } else {
        last_boundary
      }
      while pos - current_boundary > max_size {
        let force_split_target = current_boundary + max_size
        let split_point = find_nearest_sentence_end(
          sentences, force_split_target,
        )

        if split_point > current_boundary && split_point < pos {
          result.push(split_point)
          current_boundary = split_point
          continue
        }

        break
      }
    }

    if pos < text_length {
      result.push(pos)
    }
    last_boundary = pos
  }

  result
}

///|
/// Segment text using adaptive threshold mode.
/// Dynamically determines threshold based on divergence value distribution.
pub fn segment_adaptive(
  text : String,
  config : AdaptiveConfig,
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

  if divergence.divergence_values.length() == 0 {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  // Calculate adaptive threshold
  let threshold = calculate_adaptive_threshold(
    divergence.divergence_values,
    config.percentile,
    config.minimum_threshold,
  )

  // Find local maxima above adaptive threshold
  let maxima_indices = find_local_maxima(
    divergence.divergence_values,
    threshold,
  )

  // Convert maxima indices to positions
  let candidate_positions : Array[Int] = []
  for idx in maxima_indices {
    let pos = divergence.window_end_positions[idx]
    if pos > 0 {
      candidate_positions.push(pos)
    }
  }
  candidate_positions.sort_by(fn(a, b) { a.compare(b) })

  // Apply minimum size constraint
  let boundaries : Array[Int] = []
  let mut last_boundary = 0
  for pos in candidate_positions {
    if pos - last_boundary >= config.min_chunk_size {
      boundaries.push(pos)
      last_boundary = pos
    }
  }

  // Subdivide oversized chunks
  let final_boundaries = subdivide_oversized_chunks(
    boundaries,
    text_length,
    sentences,
    config.min_chunk_size,
    config.max_chunk_size,
    config.window_size,
    config.minimum_threshold,
  )

  // Convert to segment points
  let points = boundaries_to_segment_points(final_boundaries, text_length)

  if points.length() > 0 {
    return points
  }

  [@types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph)]
}
