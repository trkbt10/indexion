// TF-IDF calculation and cosine similarity functions.

///|
/// Build term frequency map from a list of tokens.
/// Returns a map from term to count.
pub fn build_term_frequency(tokens : Array[String]) -> Map[String, Int] {
  let frequency : Map[String, Int] = {}
  for token in tokens {
    let current = frequency.get(token).unwrap_or(0)
    frequency.set(token, current + 1)
  }
  frequency
}

///|
/// Build document frequency map from multiple tokenized documents.
/// Returns a map from term to the number of documents containing that term.
pub fn build_document_frequency(
  docs : Array[Array[String]],
) -> Map[String, Int] {
  let document_frequency : Map[String, Int] = {}
  for tokens in docs {
    // Get unique tokens in this document
    let unique_tokens : Map[String, Bool] = {}
    for token in tokens {
      unique_tokens.set(token, true)
    }
    // Increment document frequency for each unique token
    for entry in unique_tokens {
      let current = document_frequency.get(entry.0).unwrap_or(0)
      document_frequency.set(entry.0, current + 1)
    }
  }
  document_frequency
}

///|
/// Build a TF-IDF vector from tokens, document frequency, and total document count.
/// Uses sublinear TF (1 + ln(count)) to address term saturation.
/// IDF(term) = log((1 + total_docs) / (1 + df)) + 1
pub fn build_tfidf_vector(
  tokens : Array[String],
  df : Map[String, Int],
  total_docs : Int,
) -> TfidfVector {
  if tokens.length() == 0 {
    return TfidfVector::new()
  }
  let tf = build_term_frequency(tokens)
  let vector = TfidfVector::new()
  for entry in tf {
    let term = entry.0
    let count = entry.1
    // Sublinear TF: 1 + ln(count) — saturates high-frequency terms
    let sublinear_tf = 1.0 + @math.ln(count.to_double())
    let term_df = df.get(term).unwrap_or(0)
    // IDF = log((1 + total_docs) / (1 + df)) + 1
    let idf = @math.ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
    vector.set(term, sublinear_tf * idf)
  }
  vector
}

///|
/// Calculate the square root using Newton's method.
pub fn sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x / 2.0
  for i = 0; i < 20; i = i + 1 {
    ignore(i)
    guess = (guess + x / guess) / 2.0
  }
  guess
}

///|
/// Calculate the L2 norm of a TF-IDF vector.
fn vector_norm(vector : TfidfVector) -> Double {
  let mut sum = 0.0
  for entry in vector.iter() {
    let value = entry.1
    sum = sum + value * value
  }
  sqrt(sum)
}

///|
fn cosine_similarity_with_norms(
  a : TfidfVector,
  norm_a : Double,
  b : TfidfVector,
  norm_b : Double,
) -> Double {
  if a.is_empty() && b.is_empty() {
    return 1.0
  }
  if a.is_empty() || b.is_empty() {
    return 0.0
  }
  if norm_a == 0.0 || norm_b == 0.0 {
    return 0.0
  }
  let (small, large) = if a.length() <= b.length() { (a, b) } else { (b, a) }
  let mut dot = 0.0
  for entry in small.iter() {
    let key = entry.0
    let value = entry.1
    let other = large.get(key)
    dot = dot + value * other
  }
  dot / (norm_a * norm_b)
}

///|
/// Calculate cosine similarity between two TF-IDF vectors.
/// Returns 1.0 for identical vectors, 0.0 for orthogonal vectors.
/// If both vectors are empty, returns 1.0.
/// If only one vector is empty, returns 0.0.
pub fn cosine_similarity(a : TfidfVector, b : TfidfVector) -> Double {
  let norm_a = vector_norm(a)
  let norm_b = vector_norm(b)
  cosine_similarity_with_norms(a, norm_a, b, norm_b)
}

///|
/// Calculate cosine distance between two TF-IDF vectors.
/// Returns 0.0 for identical vectors, 1.0 for orthogonal vectors.
/// cosine_distance = 1 - cosine_similarity
pub fn cosine_distance(a : TfidfVector, b : TfidfVector) -> Double {
  let similarity = cosine_similarity(a, b)
  let distance = 1.0 - similarity
  // Clamp to [0, 1] to handle floating point errors
  if distance < 0.0 {
    0.0
  } else if distance > 1.0 {
    1.0
  } else {
    distance
  }
}

///|
/// Calculate TF-IDF cosine distance between two pre-tokenized documents.
pub fn calculate_tfidf_distance_from_tokens(
  tokens_a : Array[String],
  tokens_b : Array[String],
) -> Double {
  if tokens_a.length() == 0 && tokens_b.length() == 0 {
    return 0.0
  }
  if tokens_a.length() == 0 || tokens_b.length() == 0 {
    return 1.0
  }
  let docs = [tokens_a, tokens_b]
  let document_frequency = build_document_frequency(docs)
  let vec_a = build_tfidf_vector(tokens_a, document_frequency, 2)
  let vec_b = build_tfidf_vector(tokens_b, document_frequency, 2)
  cosine_distance(vec_a, vec_b)
}

///|
/// Calculate TF-IDF cosine distances between adjacent pre-tokenized documents.
pub fn calculate_adjacent_tfidf_distance_from_tokenized(
  tokenized : Array[Array[String]],
) -> Array[Double] {
  if tokenized.length() < 2 {
    return []
  }
  let document_frequency = build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  let vectors : Array[TfidfVector] = []
  for tokens in tokenized {
    vectors.push(build_tfidf_vector(tokens, document_frequency, total_docs))
  }
  let distances : Array[Double] = []
  for i = 0; i < vectors.length() - 1; i = i + 1 {
    let current = vectors[i]
    let next = vectors[i + 1]
    distances.push(cosine_distance(current, next))
  }
  distances
}

///|
/// Precomputed TF-IDF vectors for batch similarity calculation.
/// This allows efficient pairwise comparison without re-tokenizing.
pub struct TfidfBatch {
  /// TF-IDF vectors for each document.
  vectors : Array[TfidfVector]
  /// Cached vector norms for cosine similarity.
  norms : Array[Double]
  /// Aggregate build statistics for diagnostics.
  build_stats : TfidfBatchBuildStats
}

///|
/// Create a TfidfBatch from pre-tokenized documents.
/// Each inner array is a list of tokens for one document.
pub fn TfidfBatch::from_tokens(tokenized : Array[Array[String]]) -> TfidfBatch {
  build_batch_from_tokenized(tokenized)
}

///|
fn build_batch_from_tokenized(tokenized : Array[Array[String]]) -> TfidfBatch {
  if tokenized.length() == 0 {
    return {
      vectors: [],
      norms: [],
      build_stats: {
        document_count: 0,
        total_tokens: 0,
        total_vector_terms: 0,
        vocabulary_size: 0,
      },
    }
  }
  let total_docs = tokenized.length()
  let mut total_tokens = 0
  for tokens in tokenized {
    total_tokens += tokens.length()
  }
  let document_frequency = build_document_frequency(tokenized)
  let vectors : Array[TfidfVector] = []
  let norms : Array[Double] = []
  let mut total_vector_terms = 0
  for tokens in tokenized {
    let vector = build_tfidf_vector(tokens, document_frequency, total_docs)
    total_vector_terms += vector.length()
    norms.push(vector_norm(vector))
    vectors.push(vector)
  }
  {
    vectors,
    norms,
    build_stats: {
      document_count: total_docs,
      total_tokens,
      total_vector_terms,
      vocabulary_size: document_frequency.length(),
    },
  }
}

///|
/// Get the number of documents in the batch.
pub fn TfidfBatch::length(self : TfidfBatch) -> Int {
  self.vectors.length()
}

///|
/// Get aggregate build statistics for the batch.
pub fn TfidfBatch::build_stats(self : TfidfBatch) -> TfidfBatchBuildStats {
  self.build_stats
}

///|
/// Calculate similarity between two documents by index.
/// Returns 1.0 for identical, 0.0 for completely different.
pub fn TfidfBatch::similarity(self : TfidfBatch, i : Int, j : Int) -> Double {
  if i < 0 || j < 0 || i >= self.vectors.length() || j >= self.vectors.length() {
    return 0.0
  }
  if i == j {
    return 1.0
  }
  cosine_similarity_with_norms(
    self.vectors[i],
    self.norms[i],
    self.vectors[j],
    self.norms[j],
  )
}

///|
/// Calculate all pairwise similarities above a threshold with diagnostics.
pub fn TfidfBatch::all_pairs_above_threshold_with_stats(
  self : TfidfBatch,
  threshold : Double,
) -> (Array[(Int, Int, Double)], TfidfPairSearchStats) {
  let results : Array[(Int, Int, Double)] = []
  let n = self.vectors.length()
  let mut posting_hits = 0
  let mut candidate_pairs = 0
  let mut cosine_evaluations = 0
  if threshold > 1.0 {
    return (
      results,
      { posting_hits, candidate_pairs, cosine_evaluations, output_pairs: 0 },
    )
  }
  if threshold <= 0.0 {
    for i = 0; i < n; i = i + 1 {
      for j = i + 1; j < n; j = j + 1 {
        let sim = cosine_similarity_with_norms(
          self.vectors[i],
          self.norms[i],
          self.vectors[j],
          self.norms[j],
        )
        candidate_pairs += 1
        cosine_evaluations += 1
        if sim >= threshold {
          results.push((i, j, sim))
        }
      }
    }
    return (
      results,
      {
        posting_hits,
        candidate_pairs,
        cosine_evaluations,
        output_pairs: results.length(),
      },
    )
  }
  let postings : Map[String, Array[Int]] = {}
  let seen_candidates : Array[Int] = Array::make(n, -1)
  let candidates : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    candidates.clear()
    for term_entry in self.vectors[i].iter() {
      let term = term_entry.0
      match postings.get(term) {
        Some(doc_ids) => {
          posting_hits += doc_ids.length()
          for doc_id in doc_ids {
            if seen_candidates[doc_id] != i {
              seen_candidates[doc_id] = i
              candidates.push(doc_id)
            }
          }
          doc_ids.push(i)
        }
        None => postings.set(term, [i])
      }
    }
    candidate_pairs += candidates.length()
    cosine_evaluations += candidates.length()
    for j in candidates {
      let sim = cosine_similarity_with_norms(
        self.vectors[j],
        self.norms[j],
        self.vectors[i],
        self.norms[i],
      )
      if sim >= threshold {
        results.push((j, i, sim))
      }
    }
  }
  (
    results,
    {
      posting_hits,
      candidate_pairs,
      cosine_evaluations,
      output_pairs: results.length(),
    },
  )
}

///|
/// Calculate all pairwise similarities above a threshold.
/// Returns array of (i, j, similarity) tuples where i < j and similarity >= threshold.
pub fn TfidfBatch::all_pairs_above_threshold(
  self : TfidfBatch,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  self.all_pairs_above_threshold_with_stats(threshold).0
}
