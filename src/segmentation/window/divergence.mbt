// Window divergence calculation functions.
// Uses shared utilities from segmentation/utils for common operations.

///|
/// Default NCD weight in hybrid mode.
let default_ncd_weight : Double = 0.5

///|
/// Default TF-IDF weight in hybrid mode.
let default_tfidf_weight : Double = 0.5

///|
/// Clamp value to [0, 1] range.
fn clamp01(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
/// Normalize weights so they sum to 1.0.
fn normalize_weights(
  ncd_weight : Double,
  tfidf_weight : Double,
) -> (Double, Double) {
  let ncd_w = clamp01(ncd_weight)
  let tfidf_w = clamp01(tfidf_weight)
  let total = ncd_w + tfidf_w
  if total <= 0.0 {
    (default_ncd_weight, default_tfidf_weight)
  } else {
    (ncd_w / total, tfidf_w / total)
  }
}

///|
/// Calculate TF-IDF divergence between adjacent sentence windows.
/// Returns divergence values and their corresponding positions.
pub fn calculate_window_tfidf_divergence(
  sentences : Array[@sentence.Sentence],
  window_size : Int,
) -> @types.WindowDivergence {
  // Delegate to hybrid with TF-IDF only (ncd_weight = 0)
  calculate_window_ncd_tfidf_divergence(sentences, window_size, 0.0, 1.0)
}

///|
/// Calculate combined NCD+TF-IDF divergence between adjacent sentence windows.
/// Uses Normalized Compression Distance and TF-IDF cosine distance,
/// normalized and weighted by the given weights.
///
/// Parameters:
/// - sentences: Array of sentences to analyze
/// - window_size: Number of sentences per window
/// - ncd_weight: Weight for NCD component (default: 0.5)
/// - tfidf_weight: Weight for TF-IDF component (default: 0.5)
///
/// Returns divergence values and their corresponding positions.
pub fn calculate_window_ncd_tfidf_divergence(
  sentences : Array[@sentence.Sentence],
  window_size : Int,
  ncd_weight : Double,
  tfidf_weight : Double,
) -> @types.WindowDivergence {
  let divergence_values : Array[Double] = []
  let window_end_positions : Array[Int] = []

  // Need at least window_size + 1 sentences to compare two windows
  if sentences.length() < window_size + 1 {
    return @types.WindowDivergence::new(divergence_values, window_end_positions)
  }

  // Normalize weights
  let (ncd_w, tfidf_w) = normalize_weights(ncd_weight, tfidf_weight)

  // Build windows
  let windows : Array[String] = []
  let window_ends : Array[Int] = []

  let num_windows = sentences.length() - window_size + 1
  for i = 0; i < num_windows; i = i + 1 {
    windows.push(@utils.combine_sentences(sentences, i, window_size))
    window_ends.push(@utils.get_window_end(sentences, i, window_size))
  }

  // Calculate NCD values between adjacent windows
  let ncd_values = @utils.calculate_adjacent_ncd(windows)

  // Tokenize windows for TF-IDF
  let tokenized : Array[Array[String]] = []
  for w in windows {
    tokenized.push(@tokenizer.tokenize_for_tfidf(w))
  }
  // Calculate TF-IDF distances between adjacent windows
  let tfidf_values = @tfidf.calculate_adjacent_tfidf_distance_from_tokenized(
    tokenized,
  )

  // Normalize both using min-max normalization
  let normalized_ncd = @utils.min_max_normalize(ncd_values)
  let normalized_tfidf = @utils.min_max_normalize(tfidf_values)

  // Combine with weights
  let length = if normalized_ncd.length() < normalized_tfidf.length() {
    normalized_ncd.length()
  } else {
    normalized_tfidf.length()
  }
  let length = if length < window_ends.length() - 1 {
    length
  } else {
    window_ends.length() - 1
  }

  for i = 0; i < length; i = i + 1 {
    let ncd_val = normalized_ncd[i]
    let tfidf_val = normalized_tfidf[i]
    let combined = ncd_w * ncd_val + tfidf_w * tfidf_val
    divergence_values.push(combined)
    window_end_positions.push(window_ends[i])
  }

  @types.WindowDivergence::new(divergence_values, window_end_positions)
}

///|
/// Normalize an array of values using Min-Max normalization.
/// Returns values in range [0, 1].
/// If all values are the same, returns 0.5 for all.
///
/// Note: This is a convenience re-export from segmentation/utils.
pub fn min_max_normalize(values : Array[Double]) -> Array[Double] {
  @utils.min_max_normalize(values)
}

///|
/// Find local maxima indices where values exceed the threshold.
/// A local maximum is a value that is greater than both its neighbors.
///
/// Note: This is a convenience re-export from segmentation/utils.
pub fn find_local_maxima(
  values : Array[Double],
  threshold : Double,
) -> Array[Int] {
  @utils.find_local_maxima(values, threshold)
}
