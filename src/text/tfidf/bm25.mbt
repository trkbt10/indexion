// Okapi BM25 scoring for document similarity.
//
// BM25 improves over raw TF-IDF by adding:
// 1. Term frequency saturation: repeated terms have diminishing returns
// 2. Document length normalization: longer documents are penalized
//
// Formula:
//   BM25(t, d) = IDF(t) × (tf × (k1 + 1)) / (tf + k1 × (1 - b + b × dl/avgdl))
//
// where:
//   k1 = 1.2 (saturation parameter; higher → slower saturation)
//   b  = 0.75 (length normalization; 0 = none, 1 = full)
//   dl = document length (token count)
//   avgdl = average document length across corpus
//
// Reference: Robertson et al. (1995) "Okapi at TREC-3"

///|
/// BM25 saturation parameter. Controls how quickly term frequency saturates.
/// k1 = 0 would ignore TF entirely; typical values 1.2–2.0.
let bm25_k1 : Double = 1.2

///|
/// BM25 document length normalization parameter.
/// b = 0 means no length normalization; b = 1 means full normalization.
let bm25_b : Double = 0.75

///|
/// Build a BM25-weighted sparse vector for a document.
///
/// Unlike TF-IDF which uses sublinear TF (1 + ln(count)),
/// BM25 uses saturating TF with document length normalization:
///   weight(t) = IDF(t) × (tf × (k1 + 1)) / (tf + k1 × (1 - b + b × dl / avgdl))
pub fn build_bm25_vector(
  tokens : Array[String],
  df : Map[String, Int],
  total_docs : Int,
  avg_doc_length : Double,
) -> TfidfVector {
  if tokens.length() == 0 {
    return TfidfVector::new()
  }
  let tf = build_term_frequency(tokens)
  let dl = tokens.length().to_double()
  let vector = TfidfVector::new()
  for entry in tf {
    let term = entry.0
    let count = entry.1
    let tf_val = count.to_double()
    let term_df = df.get(term).unwrap_or(0)
    // IDF = ln((1 + total_docs) / (1 + df)) + 1 (same as TF-IDF for consistency)
    let idf = @math.ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
    // BM25 TF component with saturation and length normalization
    let tf_norm = tf_val *
      (bm25_k1 + 1.0) /
      (tf_val + bm25_k1 * (1.0 - bm25_b + bm25_b * dl / avg_doc_length))
    vector.set(term, idf * tf_norm)
  }
  vector
}

///|
/// Precomputed BM25 vectors for batch similarity calculation.
pub struct BM25Batch {
  /// BM25-weighted vectors for each document.
  vectors : Array[TfidfVector]
  /// Cached vector norms for cosine similarity.
  norms : Array[Double]
  /// Aggregate build statistics.
  build_stats : TfidfBatchBuildStats
}

///|
/// Create a BM25Batch from pre-tokenized documents.
pub fn BM25Batch::from_tokens(tokenized : Array[Array[String]]) -> BM25Batch {
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
  let avg_doc_length = total_tokens.to_double() / total_docs.to_double()
  let document_frequency = build_document_frequency(tokenized)
  let vectors : Array[TfidfVector] = []
  let norms : Array[Double] = []
  let mut total_vector_terms = 0
  for tokens in tokenized {
    let vector = build_bm25_vector(
      tokens, document_frequency, total_docs, avg_doc_length,
    )
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
pub fn BM25Batch::length(self : BM25Batch) -> Int {
  self.vectors.length()
}

///|
/// Calculate similarity between two documents by index.
pub fn BM25Batch::similarity(self : BM25Batch, i : Int, j : Int) -> Double {
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
/// Calculate all pairwise similarities above a threshold.
/// Uses inverted index posting lists for candidate pruning (same as TfidfBatch).
pub fn BM25Batch::all_pairs_above_threshold(
  self : BM25Batch,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  let results : Array[(Int, Int, Double)] = []
  let n = self.vectors.length()
  if threshold > 1.0 {
    return results
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
        if sim >= threshold {
          results.push((i, j, sim))
        }
      }
    }
    return results
  }
  // Inverted index approach for threshold > 0
  let postings : Map[String, Array[Int]] = Map([])
  let seen_candidates : Array[Int] = Array::make(n, -1)
  let candidates : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    candidates.clear()
    for term_entry in self.vectors[i].iter() {
      let term = term_entry.0
      match postings.get(term) {
        Some(doc_ids) => {
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
  results
}
