// Jensen-Shannon Divergence for token distribution comparison.
//
// JSD is an information-theoretic distance between probability distributions.
// Unlike cosine similarity (geometric), JSD treats token frequencies as
// probability distributions and measures their divergence:
//
//   JSD(P, Q) = (KL(P || M) + KL(Q || M)) / 2
//   where M = (P + Q) / 2
//
// Properties:
//   - Symmetric: JSD(P,Q) = JSD(Q,P)
//   - Bounded: 0 ≤ JSD ≤ ln(2) (with natural log)
//   - JSD = 0 iff P = Q
//   - Metric: √JSD is a proper distance metric
//
// We normalize to [0, 1] by dividing by ln(2).
//
// Reference: Lin (1991) "Divergence measures based on the Shannon entropy"

///|
/// Calculate Jensen-Shannon Divergence between two token frequency maps.
/// Returns a value in [0, 1] where 0 = identical distributions, 1 = maximally different.
///
/// The input maps are raw term counts (not probabilities); they are
/// normalized internally to sum to 1.
pub fn jensen_shannon_divergence(
  tf_a : Map[String, Int],
  tf_b : Map[String, Int],
) -> Double {
  if tf_a.is_empty() && tf_b.is_empty() {
    return 0.0
  }
  if tf_a.is_empty() || tf_b.is_empty() {
    return 1.0
  }
  // Compute total counts for normalization
  let mut total_a = 0.0
  for entry in tf_a {
    total_a += entry.1.to_double()
  }
  let mut total_b = 0.0
  for entry in tf_b {
    total_b += entry.1.to_double()
  }
  if total_a == 0.0 || total_b == 0.0 {
    return 1.0
  }
  // Collect all terms from both distributions
  let all_terms : Map[String, Bool] = Map([])
  for entry in tf_a {
    all_terms.set(entry.0, true)
  }
  for entry in tf_b {
    all_terms.set(entry.0, true)
  }
  // Compute JSD = (KL(P||M) + KL(Q||M)) / 2
  // where P = tf_a/total_a, Q = tf_b/total_b, M = (P+Q)/2
  let mut kl_pm = 0.0
  let mut kl_qm = 0.0
  for entry in all_terms {
    let term = entry.0
    let p = tf_a.get(term).unwrap_or(0).to_double() / total_a
    let q = tf_b.get(term).unwrap_or(0).to_double() / total_b
    let m = (p + q) / 2.0
    // KL(P||M) += p * ln(p/m) for p > 0
    if p > 0.0 && m > 0.0 {
      kl_pm += p * @math.ln(p / m)
    }
    // KL(Q||M) += q * ln(q/m) for q > 0
    if q > 0.0 && m > 0.0 {
      kl_qm += q * @math.ln(q / m)
    }
  }
  let jsd = (kl_pm + kl_qm) / 2.0
  // Normalize by ln(2) to get [0, 1] range
  let ln2 = @math.ln(2.0)
  let normalized = jsd / ln2
  // Clamp to handle floating point errors
  if normalized < 0.0 {
    0.0
  } else if normalized > 1.0 {
    1.0
  } else {
    normalized
  }
}

///|
/// Calculate JSD between two token arrays.
/// Convenience function that builds term frequencies internally.
pub fn jsd_from_tokens(
  tokens_a : Array[String],
  tokens_b : Array[String],
) -> Double {
  let tf_a = build_term_frequency(tokens_a)
  let tf_b = build_term_frequency(tokens_b)
  jensen_shannon_divergence(tf_a, tf_b)
}

///|
/// Convert JSD (divergence) to similarity score in [0, 1].
/// JSD = 0 → similarity = 1 (identical)
/// JSD = 1 → similarity = 0 (maximally different)
pub fn jsd_similarity(
  tokens_a : Array[String],
  tokens_b : Array[String],
) -> Double {
  1.0 - jsd_from_tokens(tokens_a, tokens_b)
}

///|
/// Batch JSD computation.
/// Precomputes term frequencies for all documents, then computes
/// pairwise JSD efficiently.
pub struct JSDBatch {
  /// Term frequency maps for each document.
  term_freqs : Array[Map[String, Int]]
}

///|
/// Create a JSDBatch from pre-tokenized documents.
pub fn JSDBatch::from_tokens(tokenized : Array[Array[String]]) -> JSDBatch {
  let term_freqs : Array[Map[String, Int]] = []
  for tokens in tokenized {
    term_freqs.push(build_term_frequency(tokens))
  }
  { term_freqs, }
}

///|
/// Get the number of documents in the batch.
pub fn JSDBatch::length(self : JSDBatch) -> Int {
  self.term_freqs.length()
}

///|
/// Calculate JSD similarity between two documents by index.
/// Returns 1.0 for identical, 0.0 for maximally different.
pub fn JSDBatch::similarity(self : JSDBatch, i : Int, j : Int) -> Double {
  if i < 0 ||
    j < 0 ||
    i >= self.term_freqs.length() ||
    j >= self.term_freqs.length() {
    return 0.0
  }
  if i == j {
    return 1.0
  }
  1.0 - jensen_shannon_divergence(self.term_freqs[i], self.term_freqs[j])
}

///|
/// Calculate all pairwise JSD similarities above a threshold.
/// Returns array of (i, j, similarity) tuples where i < j.
pub fn JSDBatch::all_pairs_above_threshold(
  self : JSDBatch,
  threshold : Double,
) -> Array[(Int, Int, Double)] {
  let results : Array[(Int, Int, Double)] = []
  let n = self.term_freqs.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let sim = self.similarity(i, j)
      if sim >= threshold {
        results.push((i, j, sim))
      }
    }
  }
  results
}
