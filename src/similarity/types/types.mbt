///|
/// Type definitions for similarity calculation strategies.

///|
/// Result of similarity calculation between two items.
pub struct SimilarityResult {
  /// Normalized distance in [0, 1] where 0 = identical.
  distance : Double
  /// Normalized similarity in [0, 1] where 1 = identical (1 - distance).
  similarity : Double
} derive(Eq, Show)

///|
/// Create a SimilarityResult from distance.
pub fn SimilarityResult::from_distance(distance : Double) -> SimilarityResult {
  { distance, similarity: 1.0 - distance }
}

///|
/// Create a SimilarityResult from similarity.
pub fn SimilarityResult::from_similarity(
  similarity : Double,
) -> SimilarityResult {
  { distance: 1.0 - similarity, similarity }
}

///|
/// Get the distance value.
pub fn SimilarityResult::get_distance(self : SimilarityResult) -> Double {
  self.distance
}

///|
/// Get the similarity value.
pub fn SimilarityResult::get_similarity(self : SimilarityResult) -> Double {
  self.similarity
}

///|
/// Common interface for text similarity strategies.
/// Each strategy implements this trait to provide a consistent API.
pub(open) trait SimilarityStrategy {
  /// Get the name of this strategy.
  name(Self) -> String

  /// Calculate distance between two texts.
  /// Returns normalized distance in [0, 1] where 0 = identical.
  distance(Self, String, String) -> Double

  /// Calculate similarity between two texts.
  /// Returns normalized similarity in [0, 1] where 1 = identical.
  similarity(Self, String, String) -> Double
}

///|
/// Configuration for the hybrid NCD + TF-IDF strategy.
pub struct HybridConfig {
  /// Weight for NCD component (normalized to sum to 1.0 with tfidf_weight).
  ncd_weight : Double
  /// Weight for TF-IDF component (normalized to sum to 1.0 with ncd_weight).
  tfidf_weight : Double
} derive(Eq, Show)

///|
/// Create a default HybridConfig with equal weights (0.5, 0.5).
pub fn HybridConfig::new() -> HybridConfig {
  { ncd_weight: 0.5, tfidf_weight: 0.5 }
}

///|
/// Create a HybridConfig with custom weights.
/// Weights are normalized to sum to 1.0.
pub fn HybridConfig::create(
  ncd_weight : Double,
  tfidf_weight : Double,
) -> HybridConfig {
  let ncd_w = if ncd_weight < 0.0 { 0.0 } else { ncd_weight }
  let tfidf_w = if tfidf_weight < 0.0 { 0.0 } else { tfidf_weight }
  let total = ncd_w + tfidf_w
  if total <= 0.0 {
    // Fallback to default weights
    return HybridConfig::new()
  }
  { ncd_weight: ncd_w / total, tfidf_weight: tfidf_w / total }
}

///|
/// Get the NCD weight.
pub fn HybridConfig::get_ncd_weight(self : HybridConfig) -> Double {
  self.ncd_weight
}

///|
/// Get the TF-IDF weight.
pub fn HybridConfig::get_tfidf_weight(self : HybridConfig) -> Double {
  self.tfidf_weight
}
