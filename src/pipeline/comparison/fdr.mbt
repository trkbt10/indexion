// Benjamini-Hochberg False Discovery Rate (FDR) correction.
//
// When comparing N files, there are N*(N-1)/2 pairs. With a fixed threshold
// (e.g., similarity ≥ 0.8), some pairs will exceed it by chance. The BH
// procedure controls the expected proportion of false discoveries (FDR).
//
// The approach uses an exponential tail model for the null distribution:
//
//   Under the null hypothesis (random pair), the probability of observing
//   similarity ≥ s decays exponentially above the threshold t:
//
//     p-value(s) = exp(-λ × (s - t))
//
//   where λ controls how quickly the null tail decays. We set λ adaptively
//   based on the expected number of false positives at the threshold.
//
// This avoids the pitfall of estimating the null from threshold-filtered
// scores, which would be contaminated by true positives and could cause
// valid matches to be rejected.
//
// Reference: Benjamini & Hochberg (1995)
//   "Controlling the false discovery rate: a practical and powerful approach
//    to multiple testing"

///|
/// Apply Benjamini-Hochberg FDR correction to batch comparison results.
///
/// `alpha` is the target FDR level (e.g., 0.05 for 5% expected false discoveries).
/// `total_pairs` is the total number of pairs tested (N*(N-1)/2), needed
/// to account for pairs that fell below the initial threshold.
/// `threshold` is the similarity threshold that was used to produce the matches.
///
/// Returns filtered matches that survive FDR correction.
pub fn apply_fdr_correction(
  matches : Array[SimilarityMatch],
  alpha : Double,
  total_pairs : Int,
  threshold? : Double = 0.0,
) -> Array[SimilarityMatch] {
  if matches.length() == 0 || alpha <= 0.0 {
    return []
  }
  if alpha >= 1.0 {
    return matches.copy()
  }
  let m = total_pairs
  if m <= 0 {
    return matches.copy()
  }
  // Determine the effective threshold for the exponential tail model.
  // If no threshold provided, use the minimum observed score.
  let effective_threshold = if threshold > 0.0 {
    threshold
  } else {
    let mut min_s = matches[0].similarity
    for match_ in matches {
      if match_.similarity < min_s {
        min_s = match_.similarity
      }
    }
    min_s
  }
  // Compute the exponential rate parameter λ.
  //
  // Under the null, we expect the number of false positives above threshold
  // to be roughly |matches| (conservative: assume all could be false).
  // The expected fraction of null pairs exceeding threshold t is:
  //   |matches| / total_pairs
  //
  // For the exponential tail: P(S ≥ t) ≈ |matches| / total_pairs
  // and P(S ≥ s) = P(S ≥ t) × exp(-λ(s-t))
  //
  // We set λ so that the p-value at score=1.0 (perfect match) is very small,
  // calibrated by the ratio of matches to total pairs.
  // λ = -ln(ε) / (1 - t), where ε is a small floor (ensures high scores
  // get very small p-values).
  //
  // The scale factor (matches/total_pairs) normalizes p-values to account
  // for the base rate of exceeding the threshold.
  let tail_range = 1.0 - effective_threshold
  let lambda = if tail_range > 1.0e-10 {
    // Calibrate so that p-value at score=1.0 is ~1e-6
    // λ = ln(1e6) / tail_range ≈ 13.8 / tail_range
    13.815510558 / tail_range
  } else {
    // Threshold is essentially 1.0; all matches are perfect
    1.0
  }
  // Base rate: fraction of all pairs that exceed the threshold
  let base_rate = matches.length().to_double() / m.to_double()
  // Step 1: Compute p-values using exponential tail model.
  // p-value(s) = base_rate × exp(-λ × (s - threshold))
  // This gives p=base_rate at the threshold and decays for higher scores.
  let p_values : Array[(Int, Double)] = [] // (original_index, p_value)
  for i = 0; i < matches.length(); i = i + 1 {
    let excess = matches[i].similarity - effective_threshold
    let p = base_rate * @math.exp(-lambda * excess)
    // Clamp to [1e-15, 1]
    let p_clamped = if p < 1.0e-15 {
      1.0e-15
    } else if p > 1.0 {
      1.0
    } else {
      p
    }
    p_values.push((i, p_clamped))
  }
  // Step 2: BH step-up procedure.
  // Sort by p-value ascending.
  p_values.sort_by(fn(a, b) { a.1.compare(b.1) })
  // Find the largest k such that p_(k) ≤ (k / m) × α
  let mut max_k = 0
  for k = 1; k <= p_values.length(); k = k + 1 {
    let bh_threshold = k.to_double() / m.to_double() * alpha
    if p_values[k - 1].1 <= bh_threshold {
      max_k = k
    }
  }
  // Reject all hypotheses with rank ≤ max_k (i.e., accept these matches)
  let accepted_indices : Map[Int, Bool] = {}
  for k = 0; k < max_k; k = k + 1 {
    accepted_indices.set(p_values[k].0, true)
  }
  let filtered : Array[SimilarityMatch] = []
  for i = 0; i < matches.length(); i = i + 1 {
    if accepted_indices.contains(i) {
      filtered.push(matches[i])
    }
  }
  filtered
}

///|
/// Apply FDR correction to a BatchResult, returning a new BatchResult
/// with only statistically significant matches.
///
/// `alpha` is the target FDR level.
/// `threshold` is the similarity threshold used to generate the matches.
/// If not provided, the minimum observed score is used.
pub fn BatchResult::apply_fdr(
  self : BatchResult,
  alpha : Double,
  threshold? : Double = 0.0,
) -> BatchResult {
  let total_pairs = self.file_count * (self.file_count - 1) / 2
  let filtered = apply_fdr_correction(
    self.matches,
    alpha,
    total_pairs,
    threshold~,
  )
  {
    matches: filtered,
    file_count: self.file_count,
    pairs_compared: self.pairs_compared,
  }
}
