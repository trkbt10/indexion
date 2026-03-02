// Type definitions for TF-IDF based segmentation.

///|
/// Configuration for TF-IDF based segmentation.
pub struct TfidfConfig {
  /// Target chunk size in characters.
  /// Default: 500
  target_chunk_size : Int
  /// Minimum chunk size in characters.
  /// Default: 100
  min_chunk_size : Int
  /// Maximum chunk size in characters.
  /// Default: 2000
  max_chunk_size : Int
  /// TF-IDF cosine distance threshold for boundary candidates.
  /// Default: 0.45
  tfidf_threshold : Double
  /// Number of sentences to combine per window.
  /// Default: 3
  window_size : Int
} derive(Eq, Show)

///|
/// Default target chunk size.
pub let default_target_chunk_size : Int = 500

///|
/// Default minimum chunk size.
pub let default_min_chunk_size : Int = 100

///|
/// Default maximum chunk size.
pub let default_max_chunk_size : Int = 2000

///|
/// Default TF-IDF threshold.
pub let default_tfidf_threshold : Double = 0.45

///|
/// Default window size.
pub let default_window_size : Int = 3

///|
/// Create a new TfidfConfig with default values.
pub fn TfidfConfig::new() -> TfidfConfig {
  {
    target_chunk_size: default_target_chunk_size,
    min_chunk_size: default_min_chunk_size,
    max_chunk_size: default_max_chunk_size,
    tfidf_threshold: default_tfidf_threshold,
    window_size: default_window_size,
  }
}

///|
/// Create a TfidfConfig with custom values.
pub fn TfidfConfig::create(
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
  tfidf_threshold : Double,
  window_size : Int,
) -> TfidfConfig {
  {
    target_chunk_size,
    min_chunk_size,
    max_chunk_size,
    tfidf_threshold,
    window_size,
  }
}

///|
/// Get the target chunk size.
pub fn TfidfConfig::get_target_chunk_size(self : TfidfConfig) -> Int {
  self.target_chunk_size
}

///|
/// Get the minimum chunk size.
pub fn TfidfConfig::get_min_chunk_size(self : TfidfConfig) -> Int {
  self.min_chunk_size
}

///|
/// Get the maximum chunk size.
pub fn TfidfConfig::get_max_chunk_size(self : TfidfConfig) -> Int {
  self.max_chunk_size
}

///|
/// Get the TF-IDF threshold.
pub fn TfidfConfig::get_tfidf_threshold(self : TfidfConfig) -> Double {
  self.tfidf_threshold
}

///|
/// Get the window size.
pub fn TfidfConfig::get_window_size(self : TfidfConfig) -> Int {
  self.window_size
}

///|
/// TF-IDF based segmentation strategy.
/// Implements SegmentationStrategy trait.
pub struct TfidfStrategy {
  /// Configuration for the strategy.
  config : TfidfConfig
} derive(Eq, Show)

///|
/// Create a new TfidfStrategy with default configuration.
pub fn TfidfStrategy::new() -> TfidfStrategy {
  { config: TfidfConfig::new() }
}

///|
/// Create a TfidfStrategy with custom configuration.
pub fn TfidfStrategy::with_config(config : TfidfConfig) -> TfidfStrategy {
  { config, }
}

///|
/// Get the configuration.
pub fn TfidfStrategy::get_config(self : TfidfStrategy) -> TfidfConfig {
  self.config
}
