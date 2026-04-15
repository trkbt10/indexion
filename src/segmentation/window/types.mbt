// Type definitions for window-based segmentation.
// Uses common types from segmentation package for SegmentType, SegmentPoint, and WindowDivergence.

///|
/// Configuration for segmentation.
pub struct SegmentConfig {
  /// Target chunk size in characters.
  target_chunk_size : Int
  /// Minimum chunk size in characters.
  min_chunk_size : Int
  /// Maximum chunk size in characters.
  max_chunk_size : Int
  /// Divergence threshold for boundary detection.
  threshold : Double
  /// Number of sentences per window.
  window_size : Int
} derive(Eq, Debug)

///|
/// Create a new SegmentConfig.
pub fn SegmentConfig::new(
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
  threshold : Double,
  window_size : Int,
) -> SegmentConfig {
  { target_chunk_size, min_chunk_size, max_chunk_size, threshold, window_size }
}

///|
/// Get the target chunk size.
pub fn SegmentConfig::get_target_chunk_size(self : SegmentConfig) -> Int {
  self.target_chunk_size
}

///|
/// Get the minimum chunk size.
pub fn SegmentConfig::get_min_chunk_size(self : SegmentConfig) -> Int {
  self.min_chunk_size
}

///|
/// Get the maximum chunk size.
pub fn SegmentConfig::get_max_chunk_size(self : SegmentConfig) -> Int {
  self.max_chunk_size
}

///|
/// Get the threshold.
pub fn SegmentConfig::get_threshold(self : SegmentConfig) -> Double {
  self.threshold
}

///|
/// Get the window size.
pub fn SegmentConfig::get_window_size(self : SegmentConfig) -> Int {
  self.window_size
}

///|
/// Configuration for adaptive segmentation.
/// Adaptive mode dynamically determines threshold based on divergence distribution.
pub struct AdaptiveConfig {
  /// Percentile for threshold selection (default: 0.2 = top 20%).
  percentile : Double
  /// Minimum threshold value (default: 0.13).
  minimum_threshold : Double
  /// Target chunk size in characters.
  target_chunk_size : Int
  /// Minimum chunk size in characters.
  min_chunk_size : Int
  /// Maximum chunk size in characters.
  max_chunk_size : Int
  /// Number of sentences per window.
  window_size : Int
} derive(Eq, Debug)

///|
/// Create a new AdaptiveConfig.
pub fn AdaptiveConfig::new(
  percentile : Double,
  minimum_threshold : Double,
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
  window_size : Int,
) -> AdaptiveConfig {
  {
    percentile,
    minimum_threshold,
    target_chunk_size,
    min_chunk_size,
    max_chunk_size,
    window_size,
  }
}

///|
/// Get the percentile value.
pub fn AdaptiveConfig::get_percentile(self : AdaptiveConfig) -> Double {
  self.percentile
}

///|
/// Get the minimum threshold.
pub fn AdaptiveConfig::get_minimum_threshold(self : AdaptiveConfig) -> Double {
  self.minimum_threshold
}

///|
/// Get the target chunk size.
pub fn AdaptiveConfig::get_target_chunk_size(self : AdaptiveConfig) -> Int {
  self.target_chunk_size
}

///|
/// Get the minimum chunk size.
pub fn AdaptiveConfig::get_min_chunk_size(self : AdaptiveConfig) -> Int {
  self.min_chunk_size
}

///|
/// Get the maximum chunk size.
pub fn AdaptiveConfig::get_max_chunk_size(self : AdaptiveConfig) -> Int {
  self.max_chunk_size
}

///|
/// Get the window size.
pub fn AdaptiveConfig::get_window_size(self : AdaptiveConfig) -> Int {
  self.window_size
}

///|
/// Window-based divergence segmentation strategy.
/// Implements SegmentationStrategy trait.
pub struct WindowStrategy {
  /// Configuration for the strategy.
  config : SegmentConfig
} derive(Eq, Debug)

///|
/// Create a new WindowStrategy with default configuration.
pub fn WindowStrategy::new() -> WindowStrategy {
  { config: default_segment_config() }
}

///|
/// Create a WindowStrategy with custom configuration.
pub fn WindowStrategy::with_config(config : SegmentConfig) -> WindowStrategy {
  { config, }
}

///|
/// Get the configuration.
pub fn WindowStrategy::get_config(self : WindowStrategy) -> SegmentConfig {
  self.config
}

///|
/// Default SegmentConfig.
fn default_segment_config() -> SegmentConfig {
  SegmentConfig::new(500, 100, 2000, 0.42, 3)
}

///|
/// Implement SegmentationStrategy trait for WindowStrategy.
pub impl @types.SegmentationStrategy for WindowStrategy with name(self) {
  ignore(self)
  "window"
}

///|
pub impl @types.SegmentationStrategy for WindowStrategy with segment(self, text) {
  segment_by_divergence(text, self.config)
}

///|
/// Configuration for NCD+TF-IDF hybrid adaptive segmentation.
/// Combines compression-based (NCD) and lexical (TF-IDF) divergence.
pub struct HybridAdaptiveConfig {
  /// Percentile for threshold selection (default: 0.2 = top 20%).
  percentile : Double
  /// Minimum threshold value (default: 0.13).
  minimum_threshold : Double
  /// Target chunk size in characters.
  target_chunk_size : Int
  /// Minimum chunk size in characters.
  min_chunk_size : Int
  /// Maximum chunk size in characters.
  max_chunk_size : Int
  /// Number of sentences per window.
  window_size : Int
  /// Weight for NCD component (default: 0.5).
  ncd_weight : Double
  /// Weight for TF-IDF component (default: 0.5).
  tfidf_weight : Double
} derive(Eq, Debug)

///|
/// Create a new HybridAdaptiveConfig.
pub fn HybridAdaptiveConfig::new(
  percentile : Double,
  minimum_threshold : Double,
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
  window_size : Int,
  ncd_weight : Double,
  tfidf_weight : Double,
) -> HybridAdaptiveConfig {
  {
    percentile,
    minimum_threshold,
    target_chunk_size,
    min_chunk_size,
    max_chunk_size,
    window_size,
    ncd_weight,
    tfidf_weight,
  }
}

///|
/// Create a HybridAdaptiveConfig with default weights (0.5/0.5).
pub fn HybridAdaptiveConfig::with_default_weights(
  percentile : Double,
  minimum_threshold : Double,
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
  window_size : Int,
) -> HybridAdaptiveConfig {
  HybridAdaptiveConfig::new(
    percentile, minimum_threshold, target_chunk_size, min_chunk_size, max_chunk_size,
    window_size, 0.5, 0.5,
  )
}

///|
/// Get the percentile value.
pub fn HybridAdaptiveConfig::get_percentile(
  self : HybridAdaptiveConfig,
) -> Double {
  self.percentile
}

///|
/// Get the minimum threshold.
pub fn HybridAdaptiveConfig::get_minimum_threshold(
  self : HybridAdaptiveConfig,
) -> Double {
  self.minimum_threshold
}

///|
/// Get the target chunk size.
pub fn HybridAdaptiveConfig::get_target_chunk_size(
  self : HybridAdaptiveConfig,
) -> Int {
  self.target_chunk_size
}

///|
/// Get the minimum chunk size.
pub fn HybridAdaptiveConfig::get_min_chunk_size(
  self : HybridAdaptiveConfig,
) -> Int {
  self.min_chunk_size
}

///|
/// Get the maximum chunk size.
pub fn HybridAdaptiveConfig::get_max_chunk_size(
  self : HybridAdaptiveConfig,
) -> Int {
  self.max_chunk_size
}

///|
/// Get the window size.
pub fn HybridAdaptiveConfig::get_window_size(
  self : HybridAdaptiveConfig,
) -> Int {
  self.window_size
}

///|
/// Get the NCD weight.
pub fn HybridAdaptiveConfig::get_ncd_weight(
  self : HybridAdaptiveConfig,
) -> Double {
  self.ncd_weight
}

///|
/// Get the TF-IDF weight.
pub fn HybridAdaptiveConfig::get_tfidf_weight(
  self : HybridAdaptiveConfig,
) -> Double {
  self.tfidf_weight
}
