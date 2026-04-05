///|
/// TF-IDF embedding provider — converts text to dense TF-IDF vectors.
/// Shared infrastructure used by digest, grep, and any module that needs
/// text-to-vector conversion.

///|
/// TF-IDF based embedding provider.
/// Builds a vocabulary from a text corpus, then projects new texts into
/// a fixed-dimension dense vector space using TF-IDF weights.
pub struct TfidfEmbeddingProvider {
  /// Target dimension for output vectors.
  dim : Int
  /// Vocabulary from corpus (term -> index in dense vector).
  vocabulary : Map[String, Int]
  /// IDF weights from corpus.
  idf : Map[String, Double]
}

///|
/// Create a new TfidfEmbeddingProvider with given dimension.
pub fn TfidfEmbeddingProvider::new(dim : Int) -> TfidfEmbeddingProvider {
  { dim, vocabulary: {}, idf: {} }
}

///|
/// Build vocabulary from a corpus of texts.
/// Selects the top `dim` terms by aggregate TF-IDF weight across the corpus,
/// which naturally favors discriminative terms (high IDF) over ubiquitous noise.
pub fn TfidfEmbeddingProvider::build_vocabulary(
  self : TfidfEmbeddingProvider,
  texts : Array[String],
) -> Unit {
  let tokenized : Array[Array[String]] = []
  for text in texts {
    tokenized.push(@tokenizer.tokenize_for_tfidf(text))
  }
  let df = @tfidf.build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  // Precompute IDF for all terms
  let idf_map : Map[String, Double] = {}
  for entry in df {
    let term = entry.0
    let term_df = entry.1
    let idf_val = @math.ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
    idf_map.set(term, idf_val)
  }
  // Accumulate aggregate TF-IDF weight per term across all documents
  let aggregate_weight : Map[String, Double] = {}
  for tokens in tokenized {
    let tf = @tfidf.build_term_frequency(tokens)
    for entry in tf {
      let term = entry.0
      let count = entry.1
      let sublinear_tf = 1.0 + @math.ln(count.to_double())
      let idf_val = idf_map.get(term).unwrap_or(1.0)
      let weight = sublinear_tf * idf_val
      let current = aggregate_weight.get(term).unwrap_or(0.0)
      aggregate_weight.set(term, current + weight)
    }
  }
  // Rank terms by aggregate TF-IDF weight descending
  let term_weights : Array[(String, Double)] = []
  for entry in aggregate_weight {
    term_weights.push((entry.0, entry.1))
  }
  term_weights.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Take top dim terms
  let mut idx = 0
  for i = 0; i < term_weights.length() && idx < self.dim; i = i + 1 {
    let term = term_weights[i].0
    self.vocabulary.set(term, idx)
    let idf_val = idf_map.get(term).unwrap_or(1.0)
    self.idf.set(term, idf_val)
    idx += 1
  }
}

///|
/// Generate a dense embedding vector for the given text.
/// Returns an L2-normalized vector of length `dim`.
pub fn TfidfEmbeddingProvider::embed(
  self : TfidfEmbeddingProvider,
  text : String,
) -> Array[Double] {
  let tokens = @tokenizer.tokenize_for_tfidf(text)
  let tf = @tfidf.build_term_frequency(tokens)
  let vector = Array::make(self.dim, 0.0)
  for entry in tf {
    let term = entry.0
    let count = entry.1
    match self.vocabulary.get(term) {
      Some(idx) => {
        // Sublinear TF: 1 + ln(count) — saturates high-frequency terms
        let sublinear_tf = 1.0 + @math.ln(count.to_double())
        let idf_val = self.idf.get(term).unwrap_or(1.0)
        vector[idx] = sublinear_tf * idf_val
      }
      None => ()
    }
  }
  // L2 normalization
  let mut norm = 0.0
  for v in vector {
    norm = norm + v * v
  }
  if norm > 0.0 {
    norm = @tfidf.sqrt(norm)
    for i = 0; i < vector.length(); i = i + 1 {
      vector[i] = vector[i] / norm
    }
  }
  vector
}

///|
/// Get embedding dimension.
pub fn TfidfEmbeddingProvider::dim(self : TfidfEmbeddingProvider) -> Int {
  self.dim
}

///|
/// Compute cosine similarity between two dense vectors.
pub fn cosine_similarity_dense(a : Array[Double], b : Array[Double]) -> Double {
  if a.length() != b.length() || a.length() == 0 {
    return 0.0
  }
  let mut dot = 0.0
  let mut norm_a = 0.0
  let mut norm_b = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    dot += a[i] * b[i]
    norm_a += a[i] * a[i]
    norm_b += b[i] * b[i]
  }
  if norm_a == 0.0 || norm_b == 0.0 {
    return 0.0
  }
  dot / (@tfidf.sqrt(norm_a) * @tfidf.sqrt(norm_b))
}
