// Unified segmentation module.
// Provides access to multiple segmentation strategies through a common interface.

///|
/// Strategy type for selecting segmentation algorithm.
pub enum Strategy {
  /// Punctuation-based chunking strategy.
  Punctuation
  /// TF-IDF based semantic segmentation strategy.
  Tfidf
  /// Window-based divergence segmentation (NCD+TF-IDF, NCD currently stubbed).
  Window
} derive(Eq, Show)

///|
/// Segment text using the specified strategy with default configuration.
pub fn segment(
  text : String,
  strategy : Strategy,
) -> Array[@seg_types.SegmentPoint] {
  match strategy {
    Punctuation => @punctuation.segment(text)
    Tfidf => @tfidf.segment(text)
    Window => @window.segment(text)
  }
}

///|
/// Segment text using punctuation strategy.
pub fn segment_by_punctuation(
  text : String,
  config : @punctuation.PunctuationConfig,
) -> Array[@seg_types.SegmentPoint] {
  @punctuation.segment_by_punctuation(text, config)
}

///|
/// Segment text using TF-IDF strategy.
pub fn segment_by_tfidf(
  text : String,
  config : @tfidf.TfidfConfig,
) -> Array[@seg_types.SegmentPoint] {
  @tfidf.segment_by_tfidf(text, config)
}

///|
/// Segment text using window divergence strategy.
pub fn segment_by_divergence(
  text : String,
  config : @window.SegmentConfig,
) -> Array[@seg_types.SegmentPoint] {
  @window.segment_by_divergence(text, config)
}

///|
/// Create a SegmentPoint (helper function).
pub fn new_segment_point(
  start : Int,
  end : Int,
  segment_type : @seg_types.SegmentType,
) -> @seg_types.SegmentPoint {
  @seg_types.SegmentPoint::new(start, end, segment_type)
}

///|
/// Convert segment points to text segments.
pub fn to_text_segments(
  points : Array[@seg_types.SegmentPoint],
  text : String,
) -> Array[@seg_types.TextSegment] {
  @seg_types.segment_points_to_text_segments(points, text)
}

///|
/// Create default punctuation config.
pub fn default_punctuation_config() -> @punctuation.PunctuationConfig {
  @punctuation.PunctuationConfig::new()
}

///|
/// Create default TF-IDF config.
pub fn default_tfidf_config() -> @tfidf.TfidfConfig {
  @tfidf.TfidfConfig::new()
}

///|
/// Create default window config.
pub fn default_window_config() -> @window.SegmentConfig {
  @window.default_config()
}
