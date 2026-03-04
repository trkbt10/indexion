// Common utility functions for segmentation strategies.
// Extracted from window/segmenter.mbt and tfidf/tfidf_segmenter.mbt to reduce duplication.

///|
/// Check if a string contains only whitespace.
pub fn is_whitespace_only(s : String) -> Bool {
  let chars = s.to_array()
  for c in chars {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\u{3000}' {
      return false
    }
  }
  true
}

///|
/// Find the nearest sentence boundary to a target position.
pub fn find_nearest_sentence_end(
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
pub fn apply_size_constraints(
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
pub fn boundaries_to_segment_points(
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
pub fn handle_few_sentences(
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
/// Find local maxima indices where values exceed the threshold.
pub fn find_local_maxima(
  values : Array[Double],
  threshold : Double,
) -> Array[Int] {
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
