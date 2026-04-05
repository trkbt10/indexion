// Window divergence calculation functions.
// Uses shared utilities from segmentation/utils for common operations.

///|
/// RRF smoothing constant (standard value from Cormack et al. 2009).
let rrf_k : Double = 60.0

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
/// Uses Reciprocal Rank Fusion (RRF) to combine NCD and TF-IDF signals.
/// RRF is rank-based, so it is invariant to scale differences between signals
/// and robust to outliers in either signal.
///
/// Parameters:
/// - sentences: Array of sentences to analyze
/// - window_size: Number of sentences per window
/// - ncd_weight: When <= 0, NCD is skipped (TF-IDF only). Otherwise both signals are fused via RRF.
/// - tfidf_weight: When <= 0, TF-IDF is skipped (NCD only). Otherwise both signals are fused via RRF.
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

  let use_ncd = ncd_weight > 0.0
  let use_tfidf = tfidf_weight > 0.0

  // Build windows
  let windows : Array[String] = []
  let window_ends : Array[Int] = []

  let num_windows = sentences.length() - window_size + 1
  for i = 0; i < num_windows; i = i + 1 {
    windows.push(@utils.combine_sentences(sentences, i, window_size))
    window_ends.push(@utils.get_window_end(sentences, i, window_size))
  }

  // Calculate raw signal arrays
  let ncd_values : Array[Double] = if use_ncd {
    @utils.calculate_adjacent_ncd(windows)
  } else {
    []
  }

  let tfidf_values : Array[Double] = if use_tfidf {
    let tokenized : Array[Array[String]] = []
    for w in windows {
      tokenized.push(@tokenizer.tokenize_for_tfidf(w))
    }
    @tfidf.calculate_adjacent_tfidf_distance_from_tokenized(tokenized)
  } else {
    []
  }

  // Determine output length
  let max_signal_len = if ncd_values.length() > tfidf_values.length() {
    ncd_values.length()
  } else {
    tfidf_values.length()
  }
  let length = if max_signal_len < window_ends.length() - 1 {
    max_signal_len
  } else {
    window_ends.length() - 1
  }

  if use_ncd && use_tfidf {
    // Both signals: fuse via RRF
    let min_len = if ncd_values.length() < tfidf_values.length() {
      ncd_values.length()
    } else {
      tfidf_values.length()
    }
    let length = if min_len < window_ends.length() - 1 {
      min_len
    } else {
      window_ends.length() - 1
    }
    let ncd_trimmed : Array[Double] = []
    let tfidf_trimmed : Array[Double] = []
    for i = 0; i < length; i = i + 1 {
      ncd_trimmed.push(ncd_values[i])
      tfidf_trimmed.push(tfidf_values[i])
    }
    let fused = @utils.reciprocal_rank_fusion(
      [ncd_trimmed, tfidf_trimmed],
      rrf_k,
    )
    for i = 0; i < fused.length(); i = i + 1 {
      divergence_values.push(fused[i])
      window_end_positions.push(window_ends[i])
    }
  } else if use_tfidf {
    // TF-IDF only: use robust normalization
    let normalized = @utils.robust_normalize(tfidf_values)
    for i = 0; i < length; i = i + 1 {
      divergence_values.push(normalized[i])
      window_end_positions.push(window_ends[i])
    }
  } else if use_ncd {
    // NCD only: use robust normalization
    let normalized = @utils.robust_normalize(ncd_values)
    for i = 0; i < length; i = i + 1 {
      divergence_values.push(normalized[i])
      window_end_positions.push(window_ends[i])
    }
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
