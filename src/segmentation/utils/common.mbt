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
  sentences : Array[@types.Sentence],
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
  sentences : Array[@types.Sentence],
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
  sentences : Array[@types.Sentence],
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
/// Combine multiple sentences into a single text string.
/// Takes sentences from start index with count sentences.
pub fn combine_sentences(
  sentences : Array[@types.Sentence],
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
pub fn get_window_end(
  sentences : Array[@types.Sentence],
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
/// Smooth an array of values using a symmetric moving average.
/// The window extends `radius` elements on each side (total width = 2*radius + 1).
/// Edges use partial windows (naturally shrink).
fn smooth_moving_average(values : Array[Double], radius : Int) -> Array[Double] {
  let n = values.length()
  if n == 0 || radius <= 0 {
    return values.copy()
  }
  let result : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    let lo = if i - radius > 0 { i - radius } else { 0 }
    let hi = if i + radius < n - 1 { i + radius } else { n - 1 }
    let mut sum = 0.0
    for j = lo; j <= hi; j = j + 1 {
      sum += values[j]
    }
    result.push(sum / (hi - lo + 1).to_double())
  }
  result
}

///|
/// Calculate peak prominence for each index.
/// Prominence measures how much a peak stands out from its surrounding valleys.
/// For each point, scan left and right until a higher value is found;
/// the minimum encountered on each side is the "key col" (valley).
/// Prominence = value - max(left_col, right_col).
/// For boundary peaks (no higher peak on one side), only the other side counts.
fn calculate_prominence(values : Array[Double]) -> Array[Double] {
  let n = values.length()
  let prominence = Array::make(n, 0.0)
  if n == 0 {
    return prominence
  }
  for i = 0; i < n; i = i + 1 {
    // Scan left for the key col
    let mut left_min = values[i]
    let mut has_left = false
    for j = i - 1; j >= 0; j = j - 1 {
      if values[j] < left_min {
        left_min = values[j]
      }
      if values[j] > values[i] {
        has_left = true
        break
      }
    }
    // If no higher peak found on left, this point dominates the left boundary.
    // In that case left_min is the global minimum to the left, which is valid.
    if i > 0 {
      has_left = true
    }
    // Scan right for the key col
    let mut right_min = values[i]
    let mut has_right = false
    for j = i + 1; j < n; j = j + 1 {
      if values[j] < right_min {
        right_min = values[j]
      }
      if values[j] > values[i] {
        has_right = true
        break
      }
    }
    if i < n - 1 {
      has_right = true
    }
    // Prominence: distance from peak to the higher of the two key cols
    let col = if has_left && has_right {
      if left_min > right_min { left_min } else { right_min }
    } else if has_left {
      left_min
    } else if has_right {
      right_min
    } else {
      values[i] // single element: prominence is 0
    }
    prominence[i] = values[i] - col
  }
  prominence
}

///|
/// Find local maxima indices where values exceed the threshold.
/// Uses moving average smoothing (radius=1) to reduce noise, then filters
/// by peak prominence to reject insignificant local bumps.
/// A peak must satisfy:
///   1. Smoothed value >= threshold
///   2. Is a local maximum in the smoothed signal
///   3. Peak prominence >= 20% of the signal range (adaptive)
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

  // Step 1: Smooth with moving average (radius=1 → 3-point window)
  let smoothed = smooth_moving_average(values, 1)

  // Step 2: Find candidate local maxima in smoothed signal
  let candidates : Array[Int] = []
  if smoothed[0] >= threshold && smoothed[0] >= smoothed[1] {
    candidates.push(0)
  }
  for i = 1; i < smoothed.length() - 1; i = i + 1 {
    if smoothed[i] >= threshold &&
      smoothed[i] >= smoothed[i - 1] &&
      smoothed[i] >= smoothed[i + 1] {
      candidates.push(i)
    }
  }
  let last_idx = smoothed.length() - 1
  if smoothed[last_idx] >= threshold &&
    smoothed[last_idx] >= smoothed[last_idx - 1] {
    candidates.push(last_idx)
  }

  // Step 3: Filter by peak prominence
  let prominence = calculate_prominence(smoothed)
  // Adaptive prominence threshold: 20% of signal range
  let mut min_val = smoothed[0]
  let mut max_val = smoothed[0]
  for v in smoothed {
    if v < min_val {
      min_val = v
    }
    if v > max_val {
      max_val = v
    }
  }
  let signal_range = max_val - min_val
  let min_prominence = signal_range * 0.2

  for idx in candidates {
    if prominence[idx] >= min_prominence {
      maxima.push(idx)
    }
  }

  maxima
}
