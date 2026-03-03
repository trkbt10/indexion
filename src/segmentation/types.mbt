// Common type definitions for segmentation strategies.

///|
/// Classification of segment content.
pub(all) enum SegmentType {
  /// A paragraph-level segment.
  Paragraph
  /// A section-level segment (larger logical unit).
  Section
  /// A heading segment.
  Heading
} derive(Eq, Show)

///|
/// A lightweight segment point without text content.
/// Used for efficient processing when the client already has the original text.
pub struct SegmentPoint {
  /// Start position (character offset) in the original text.
  start : Int
  /// End position (character offset) in the original text (exclusive).
  end : Int
  /// The type of segment.
  segment_type : SegmentType
} derive(Eq, Show)

///|
/// Create a new SegmentPoint.
pub fn SegmentPoint::new(
  start : Int,
  end : Int,
  segment_type : SegmentType,
) -> SegmentPoint {
  { start, end, segment_type }
}

///|
/// Get the start position.
pub fn SegmentPoint::get_start(self : SegmentPoint) -> Int {
  self.start
}

///|
/// Get the end position.
pub fn SegmentPoint::get_end(self : SegmentPoint) -> Int {
  self.end
}

///|
/// Get the segment type.
pub fn SegmentPoint::get_type(self : SegmentPoint) -> SegmentType {
  self.segment_type
}

///|
/// Get the length of the segment.
pub fn SegmentPoint::length(self : SegmentPoint) -> Int {
  self.end - self.start
}

///|
/// Full segment with extracted text content.
pub struct TextSegment {
  /// The text content of the segment.
  text : String
  /// Start position (character offset) in the original text.
  start : Int
  /// End position (character offset) in the original text (exclusive).
  end : Int
  /// The type of segment.
  segment_type : SegmentType
  /// Optional heading text if this is a section under a heading.
  heading_text : String?
} derive(Eq, Show)

///|
/// Create a new TextSegment.
pub fn TextSegment::new(
  text : String,
  start : Int,
  end : Int,
  segment_type : SegmentType,
) -> TextSegment {
  { text, start, end, segment_type, heading_text: None }
}

///|
/// Create a new TextSegment with heading text.
pub fn TextSegment::with_heading(
  text : String,
  start : Int,
  end : Int,
  segment_type : SegmentType,
  heading_text : String,
) -> TextSegment {
  { text, start, end, segment_type, heading_text: Some(heading_text) }
}

///|
/// Get the text content.
pub fn TextSegment::get_text(self : TextSegment) -> String {
  self.text
}

///|
/// Get the start position.
pub fn TextSegment::get_start(self : TextSegment) -> Int {
  self.start
}

///|
/// Get the end position.
pub fn TextSegment::get_end(self : TextSegment) -> Int {
  self.end
}

///|
/// Get the segment type.
pub fn TextSegment::get_type(self : TextSegment) -> SegmentType {
  self.segment_type
}

///|
/// Get the heading text if present.
pub fn TextSegment::get_heading_text(self : TextSegment) -> String? {
  self.heading_text
}

///|
/// Get the length of the segment.
pub fn TextSegment::length(self : TextSegment) -> Int {
  self.end - self.start
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
/// Convert a SegmentPoint to a TextSegment by extracting text from the original.
pub fn SegmentPoint::to_text_segment(
  self : SegmentPoint,
  text : String,
) -> TextSegment {
  let segment_text = extract_substring(text, self.start, self.end)
  TextSegment::new(segment_text, self.start, self.end, self.segment_type)
}

///|
/// Convert an array of SegmentPoints to TextSegments.
pub fn segment_points_to_text_segments(
  points : Array[SegmentPoint],
  text : String,
) -> Array[TextSegment] {
  points.map(fn(p) { p.to_text_segment(text) })
}

///|
/// Common interface for segmentation strategies.
/// Each strategy implements this trait to provide a consistent API.
pub(open) trait SegmentationStrategy {
  /// Get the name of this strategy.
  name(Self) -> String

  /// Segment text and return an array of segment points.
  segment(Self, String) -> Array[SegmentPoint]
}

///|
/// Result of window divergence calculation.
/// Shared by tfidf and window segmentation strategies.
pub struct WindowDivergence {
  /// Array of divergence values between adjacent windows.
  divergence_values : Array[Double]
  /// Array of window end positions corresponding to each divergence value.
  window_end_positions : Array[Int]
} derive(Eq, Show)

///|
/// Create a new WindowDivergence.
pub fn WindowDivergence::new(
  divergence_values : Array[Double],
  window_end_positions : Array[Int],
) -> WindowDivergence {
  { divergence_values, window_end_positions }
}

///|
/// Get the divergence values.
pub fn WindowDivergence::get_values(self : WindowDivergence) -> Array[Double] {
  self.divergence_values
}

///|
/// Get the window end positions.
pub fn WindowDivergence::get_positions(self : WindowDivergence) -> Array[Int] {
  self.window_end_positions
}
