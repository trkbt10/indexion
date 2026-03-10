///|
/// Hybrid NCD + TF-IDF similarity strategy.
/// NOTE: TF-IDF component requires KGF tokenization.
/// For string-based fallback, only NCD is used.

///|
/// Hybrid similarity strategy combining NCD and TF-IDF.
/// Uses weighted average of both metrics for robust similarity measurement.
pub struct HybridStrategy {
  config : @types.HybridConfig
} derive(Eq, Show)

///|
/// Create a new HybridStrategy with default config (50/50 weights).
pub fn HybridStrategy::new() -> HybridStrategy {
  { config: @types.HybridConfig::new() }
}

///|
/// Create a HybridStrategy with custom config.
pub fn HybridStrategy::with_config(
  config : @types.HybridConfig,
) -> HybridStrategy {
  { config, }
}

///|
/// Get the configuration.
pub fn HybridStrategy::get_config(self : HybridStrategy) -> @types.HybridConfig {
  self.config
}

///|
pub impl @types.SimilarityStrategy for HybridStrategy with name(self) {
  ignore(self)
  "hybrid"
}

///|
/// String-based distance uses NCD only (TF-IDF requires KGF tokenization).
pub impl @types.SimilarityStrategy for HybridStrategy with distance(self, a, b) {
  ignore(self)
  // After KGF migration, string-based TF-IDF is not available.
  // Use NCD only for fallback.
  @utils.ncd(a, b)
}

///|
pub impl @types.SimilarityStrategy for HybridStrategy with similarity(
  self,
  a,
  b,
) {
  1.0 - self.distance(a, b)
}

///|
/// Calculate hybrid distances for adjacent texts using NCD only.
pub fn calculate_adjacent_hybrid(
  texts : Array[String],
  config : @types.HybridConfig,
) -> Array[Double] {
  ignore(config)
  if texts.length() < 2 {
    return []
  }
  // After KGF migration, use NCD only
  @utils.calculate_adjacent_ncd(texts)
}
