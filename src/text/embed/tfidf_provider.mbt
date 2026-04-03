///|
/// TF-IDF embedding provider — converts text to dense TF-IDF vectors.
/// Shared infrastructure used by digest, grep, and any module that needs
/// text-to-vector conversion.

///|
/// Natural logarithm approximation via series expansion.
fn ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let y = (x - 1.0) / (x + 1.0)
  let y2 = y * y
  let mut result = y
  let mut term = y
  for i = 1; i < 50; i = i + 1 {
    term = term * y2
    result = result + term / (2.0 * i.to_double() + 1.0)
  }
  2.0 * result
}

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
/// Selects the top `dim` terms by document frequency and computes IDF weights.
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
  // Rank terms by document frequency descending
  let term_counts : Array[(String, Int)] = []
  for entry in df {
    term_counts.push((entry.0, entry.1))
  }
  term_counts.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Take top dim terms
  let mut idx = 0
  for i = 0; i < term_counts.length() && idx < self.dim; i = i + 1 {
    let term = term_counts[i].0
    self.vocabulary.set(term, idx)
    let term_df = df.get(term).unwrap_or(1)
    let idf_val = ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
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
  let total = tokens.length().to_double()
  let safe_total = if total < 1.0 { 1.0 } else { total }
  let vector = Array::make(self.dim, 0.0)
  for entry in tf {
    let term = entry.0
    let count = entry.1
    match self.vocabulary.get(term) {
      Some(idx) => {
        let normalized_tf = count.to_double() / safe_total
        let idf_val = self.idf.get(term).unwrap_or(1.0)
        vector[idx] = normalized_tf * idf_val
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
