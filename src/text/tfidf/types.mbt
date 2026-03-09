// TF-IDF types for text similarity computation.

///|
/// Build-time statistics for a TF-IDF batch.
pub struct TfidfBatchBuildStats {
  document_count : Int
  total_tokens : Int
  total_vector_terms : Int
  vocabulary_size : Int
}

///|
/// Search statistics for TF-IDF pair generation.
pub struct TfidfPairSearchStats {
  posting_hits : Int
  candidate_pairs : Int
  cosine_evaluations : Int
  output_pairs : Int
}

///|
/// A sparse TF-IDF vector representation using term-weight mapping.
pub struct TfidfVector {
  /// Map from term to TF-IDF weight.
  terms : Map[String, Double]
}

///|
/// Create a new empty TfidfVector.
pub fn TfidfVector::new() -> TfidfVector {
  { terms: {} }
}

///|
/// Create a TfidfVector from an existing term map.
pub fn TfidfVector::from_terms(terms : Map[String, Double]) -> TfidfVector {
  { terms, }
}

///|
/// Get the weight for a given term. Returns 0.0 if not found.
pub fn TfidfVector::get(self : TfidfVector, term : String) -> Double {
  self.terms.get(term).unwrap_or(0.0)
}

///|
/// Set the weight for a given term.
pub fn TfidfVector::set(
  self : TfidfVector,
  term : String,
  weight : Double,
) -> Unit {
  self.terms.set(term, weight)
}

///|
/// Get the number of terms in the vector.
pub fn TfidfVector::length(self : TfidfVector) -> Int {
  self.terms.length()
}

///|
/// Check if the vector is empty.
pub fn TfidfVector::is_empty(self : TfidfVector) -> Bool {
  self.terms.is_empty()
}

///|
/// Get an iterator over the terms.
pub fn TfidfVector::iter(self : TfidfVector) -> Iter[(String, Double)] {
  self.terms.iter()
}
