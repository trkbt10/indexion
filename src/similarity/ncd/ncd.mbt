///|
/// NCD (Normalized Compression Distance) similarity strategy.
/// Wraps the existing NCD implementation from segmentation/utils.

///|
/// NCD-based similarity strategy.
/// Uses compression-based distance to measure semantic similarity.
pub struct NCDStrategy {
  priv _unused : Unit
} derive(Eq, Show)

///|
/// Create a new NCDStrategy.
pub fn NCDStrategy::new() -> NCDStrategy {
  { _unused: () }
}

///|
pub impl @types.SimilarityStrategy for NCDStrategy with name(self) {
  ignore(self)
  "ncd"
}

///|
pub impl @types.SimilarityStrategy for NCDStrategy with distance(self, a, b) {
  ignore(self)
  @utils.ncd(a, b)
}

///|
pub impl @types.SimilarityStrategy for NCDStrategy with similarity(self, a, b) {
  1.0 - self.distance(a, b)
}

///|
/// Calculate NCD distances for adjacent texts in an array.
/// Returns array where result[i] = ncd(texts[i], texts[i+1]).
pub fn calculate_adjacent_ncd(texts : Array[String]) -> Array[Double] {
  @utils.calculate_adjacent_ncd(texts)
}
