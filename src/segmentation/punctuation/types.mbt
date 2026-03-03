// Type definitions for punctuation-based segmentation.

///|
/// Configuration for punctuation-based chunking.
pub struct PunctuationConfig {
  /// Target chunk size in characters.
  /// Chunks will be accumulated until this size is reached.
  /// Default: 500
  target_chunk_size : Int
  /// Minimum chunk size in characters.
  /// Won't create chunks smaller than this unless it's the last chunk.
  /// Default: 100
  min_chunk_size : Int
  /// Maximum chunk size in characters.
  /// Hard limit - will split even mid-sentence if exceeded.
  /// Default: 2000
  max_chunk_size : Int
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
/// Create a new PunctuationConfig with default values.
pub fn PunctuationConfig::new() -> PunctuationConfig {
  {
    target_chunk_size: default_target_chunk_size,
    min_chunk_size: default_min_chunk_size,
    max_chunk_size: default_max_chunk_size,
  }
}

///|
/// Create a PunctuationConfig with custom values.
pub fn PunctuationConfig::create(
  target_chunk_size : Int,
  min_chunk_size : Int,
  max_chunk_size : Int,
) -> PunctuationConfig {
  { target_chunk_size, min_chunk_size, max_chunk_size }
}

///|
/// Get the target chunk size.
pub fn PunctuationConfig::get_target_chunk_size(
  self : PunctuationConfig,
) -> Int {
  self.target_chunk_size
}

///|
/// Get the minimum chunk size.
pub fn PunctuationConfig::get_min_chunk_size(self : PunctuationConfig) -> Int {
  self.min_chunk_size
}

///|
/// Get the maximum chunk size.
pub fn PunctuationConfig::get_max_chunk_size(self : PunctuationConfig) -> Int {
  self.max_chunk_size
}

///|
/// Punctuation-based segmentation strategy.
/// Implements SegmentationStrategy trait.
pub struct PunctuationStrategy {
  /// Configuration for the strategy.
  config : PunctuationConfig
} derive(Eq, Show)

///|
/// Create a new PunctuationStrategy with default configuration.
pub fn PunctuationStrategy::new() -> PunctuationStrategy {
  { config: PunctuationConfig::new() }
}

///|
/// Create a PunctuationStrategy with custom configuration.
pub fn PunctuationStrategy::with_config(
  config : PunctuationConfig,
) -> PunctuationStrategy {
  { config, }
}

///|
/// Get the configuration.
pub fn PunctuationStrategy::get_config(
  self : PunctuationStrategy,
) -> PunctuationConfig {
  self.config
}
