///|
/// TF-IDF cosine similarity strategy.
/// NOTE: This strategy requires pre-tokenized input via TfidfBatch.
/// The string-based distance methods are deprecated.

///|
/// TF-IDF based similarity strategy.
/// For efficient batch processing, use TfidfBatch::from_tokens instead.
pub struct TfidfStrategy {
  priv _unused : Unit
} derive(Eq, Debug)

///|
/// Create a new TfidfStrategy.
pub fn TfidfStrategy::new() -> TfidfStrategy {
  { _unused: () }
}

///|
pub impl @types.SimilarityStrategy for TfidfStrategy with name(self) {
  ignore(self)
  "tfidf"
}

///|
/// String-based distance is not supported after KGF migration.
/// Use TfidfBatch::from_tokens for proper tokenization.
pub impl @types.SimilarityStrategy for TfidfStrategy with distance(self, a, b) {
  ignore(self)
  ignore(a)
  ignore(b)
  // Return 0.0 (identical) as fallback - real computation should use TfidfBatch
  0.0
}

///|
pub impl @types.SimilarityStrategy for TfidfStrategy with similarity(self, a, b) {
  1.0 - self.distance(a, b)
}

///|
/// Batch TF-IDF similarity calculator.
/// Precomputes TF-IDF vectors for efficient pairwise comparison.
pub struct TfidfBatch(@tfidf.TfidfBatch)

///|
/// Create a batch calculator from pre-tokenized documents.
pub fn TfidfBatch::from_tokens(tokenized : Array[Array[String]]) -> TfidfBatch {
  TfidfBatch(@tfidf.TfidfBatch::from_tokens(tokenized))
}

///|
/// Get the number of documents in the batch.
pub fn TfidfBatch::length(self : TfidfBatch) -> Int {
  self.0.length()
}

///|
/// Calculate similarity between two documents by index.
pub fn TfidfBatch::similarity(self : TfidfBatch, i : Int, j : Int) -> Double {
  self.0.similarity(i, j)
}

///|
/// Calculate all pairwise similarities above a threshold.
/// Returns array of (i, j, similarity) where i < j.
pub fn TfidfBatch::all_pairs_above_threshold(
  self : TfidfBatch,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  self.0.all_pairs_above_threshold(threshold)
}
