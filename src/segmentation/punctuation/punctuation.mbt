// Punctuation-based segmentation implementation.
// Simple strategy that splits text at sentence boundaries and accumulates
// chunks up to a target size.

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
/// Segment text using punctuation-based chunking.
/// Accumulates sentences into chunks of approximately target_chunk_size,
/// splitting at sentence boundaries when possible.
pub fn segment_by_punctuation(
  text : String,
  config : PunctuationConfig,
) -> Array[@types.SegmentPoint] {
  let target_size = config.target_chunk_size
  let min_size = config.min_chunk_size
  let max_size = config.max_chunk_size

  // Handle empty or whitespace-only text
  if text.length() == 0 || is_whitespace_only(text) {
    return []
  }

  let text_length = text.length()

  // Very short text - single segment
  if text_length <= min_size {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  // Get sentence boundaries
  let sentences = @sentence.split_sentences(text)
  if sentences.length() == 0 {
    return [
      @types.SegmentPoint::new(0, text_length, @types.SegmentType::Paragraph),
    ]
  }

  // Build array of sentence end positions
  let boundaries : Array[Int] = []
  for s in sentences {
    boundaries.push(s.get_end())
  }
  // Always include end of text as a boundary
  if boundaries.length() == 0 ||
    boundaries[boundaries.length() - 1] != text_length {
    boundaries.push(text_length)
  }

  let points : Array[@types.SegmentPoint] = []
  let mut chunk_start = 0
  let mut last_boundary_idx = 0

  for i = 0; i < boundaries.length(); i = i + 1 {
    let boundary = boundaries[i]
    let current_chunk_size = boundary - chunk_start

    // Check if we've exceeded max size - force split
    if current_chunk_size > max_size {
      // Use last valid boundary if available and chunk would be >= min_size
      if last_boundary_idx > 0 {
        let last_boundary = boundaries[last_boundary_idx - 1]
        if last_boundary > chunk_start {
          let split_point = last_boundary
          if split_point - chunk_start >= min_size {
            points.push(
              @types.SegmentPoint::new(
                chunk_start,
                split_point,
                @types.SegmentType::Paragraph,
              ),
            )
            chunk_start = split_point
          }
        }
      }

      // If still over max, force split at max
      while boundary - chunk_start > max_size {
        let force_split_end = chunk_start + max_size
        points.push(
          @types.SegmentPoint::new(
            chunk_start,
            force_split_end,
            @types.SegmentType::Paragraph,
          ),
        )
        chunk_start = force_split_end
      }
      last_boundary_idx = i
      continue
    }

    // Check if we've reached target size
    if current_chunk_size >= target_size {
      points.push(
        @types.SegmentPoint::new(
          chunk_start,
          boundary,
          @types.SegmentType::Paragraph,
        ),
      )
      chunk_start = boundary
      last_boundary_idx = i
      continue
    }

    // Track last valid boundary for potential future splits
    last_boundary_idx = i
  }

  // Handle remaining text
  if chunk_start < text_length {
    let remaining = text_length - chunk_start

    // If remaining is very small and we have previous points, merge with last
    if remaining < min_size && points.length() > 0 {
      let last_point = points[points.length() - 1]
      points[points.length() - 1] = @types.SegmentPoint::new(
        last_point.get_start(),
        text_length,
        last_point.get_type(),
      )
    } else {
      // Check if there's actual content
      let remaining_text = extract_substring(text, chunk_start, text_length)
      if not(is_whitespace_only(remaining_text)) {
        points.push(
          @types.SegmentPoint::new(
            chunk_start,
            text_length,
            @types.SegmentType::Paragraph,
          ),
        )
      }
    }
  }

  points
}

///|
/// Extract substring from text given character offsets.
fn extract_substring(text : String, start : Int, end : Int) -> String {
  let chars = text.to_array()
  let buf = StringBuilder::new()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Segment text using punctuation strategy with default configuration.
pub fn segment(text : String) -> Array[@types.SegmentPoint] {
  segment_by_punctuation(text, PunctuationConfig::new())
}

///|
/// Implement SegmentationStrategy trait for PunctuationStrategy.
pub impl @types.SegmentationStrategy for PunctuationStrategy with name(self) {
  ignore(self)
  "punctuation"
}

///|
pub impl @types.SegmentationStrategy for PunctuationStrategy with segment(
  self,
  text,
) {
  segment_by_punctuation(text, self.config)
}
