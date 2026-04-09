///|
/// Vocabulary divergence measurement between two token sets.
///
/// Given a "source" token set and a "target" token set (both produced by
/// @kgf_tokenize), computes cosine distance and extracts gap terms —
/// feature strings present in source but absent from target.
///
/// Used by:
/// - `spec verify`: spec (source) vs implementation (target)
/// - `plan reconcile`: code (source) vs documentation (target)

///|
/// A term found in source but absent from target.
pub(all) struct GapTerm {
  /// Full feature string ("Kind:value")
  term : String
  /// Extracted value part
  value : String
  /// TF-IDF weight in source
  weight : Double
  /// Extracted kind part
  kind : String
} derive(Eq, Show)

///|
/// Configuration for gap term extraction.
pub(all) struct GapConfig {
  /// Minimum value length to consider (default: 2)
  min_value_length : Int
  /// Maximum number of gap terms to return (0 = no limit beyond threshold)
  max_terms : Int
} derive(Eq, Show)

///|
pub fn GapConfig::default() -> GapConfig {
  { min_value_length: 2, max_terms: 0 }
}

///|
/// Result of vocabulary divergence measurement.
pub(all) struct DivergenceResult {
  /// Cosine distance between source and target (0.0 = identical, 1.0 = orthogonal)
  cosine_distance : Double
  /// Gap terms: source terms absent from target, sorted by weight descending,
  /// thresholded by Kneedle to separate signal from noise.
  gap_terms : Array[GapTerm]
} derive(Eq, Show)

///|
/// Measure vocabulary divergence between two sets of per-file token arrays.
///
/// Builds project-wide document frequency from all files for ubiquity filtering,
/// then extracts gap terms using module-local TF-IDF with Kneedle thresholding.
pub fn measure_divergence(
  source_file_tokens : Array[Array[String]],
  target_file_tokens : Array[Array[String]],
  config : GapConfig,
) -> DivergenceResult {
  // Build project-wide document frequency across all files
  let all_file_tokens : Array[Array[String]] = []
  for t in source_file_tokens {
    all_file_tokens.push(t)
  }
  for t in target_file_tokens {
    all_file_tokens.push(t)
  }
  let project_df = @tfidf.build_document_frequency(all_file_tokens)
  let total_docs = all_file_tokens.length()
  // Flatten into aggregate token arrays
  let source_flat = source_file_tokens.flatten()
  let target_flat = target_file_tokens.flatten()
  // Cosine distance
  let cosine_dist = @tfidf.calculate_tfidf_distance_from_tokens(
    source_flat, target_flat,
  )
  // Module-local TF-IDF for gap term extraction
  let local_df = @tfidf.build_document_frequency([source_flat, target_flat])
  let source_vec = @tfidf.build_tfidf_vector(source_flat, local_df, 2)
  let target_tf = @tfidf.build_term_frequency(target_flat)
  let ubiquity_threshold = total_docs / 3 + 1
  let gap_terms = extract_gap_terms(
    source_vec, target_tf, project_df, ubiquity_threshold, config,
  )
  { cosine_distance: cosine_dist, gap_terms }
}

///|
/// Extract gap terms: feature strings with high TF-IDF weight in source
/// that are absent from target, filtered by project-wide document frequency
/// to suppress ubiquitous terms.
fn extract_gap_terms(
  source_vec : @tfidf.TfidfVector,
  target_tf : Map[String, Int],
  project_df : Map[String, Int],
  ubiquity_threshold : Int,
  config : GapConfig,
) -> Array[GapTerm] {
  // Build cross-prefix value index from target tokens.
  // Enables matching "Ident:jsonrpc" in source against "StringLit:jsonrpc" in target.
  let target_values : Map[String, Bool] = {}
  for kv in target_tf {
    let value = @kgf_tokenize.feature_value(kv.0)
    if value.length() >= config.min_value_length {
      target_values[value] = true
    }
  }
  let value_weights : Map[String, (Double, String)] = {}
  for entry in source_vec.iter() {
    let term = entry.0
    let weight = entry.1
    // Only identifier-style tokens (Kind:value), not vocab: sub-tokens
    if !@kgf_tokenize.feature_has_value(term) || term.has_prefix("vocab:") {
      continue
    }
    let value = @kgf_tokenize.feature_value(term)
    if value.length() < config.min_value_length {
      continue
    }
    // Skip if value exists in target under any prefix
    if target_values.contains(value) {
      continue
    }
    // Skip if exact term exists in target
    if target_tf.get(term).unwrap_or(0) > 0 {
      continue
    }
    // Skip ubiquitous terms
    if project_df.get(term).unwrap_or(0) >= ubiquity_threshold {
      continue
    }
    // Skip numeric values
    if is_numeric_value(value) {
      continue
    }
    let kind = @kgf_tokenize.feature_kind(term)
    match value_weights.get(value) {
      Some((existing_weight, _)) =>
        if weight > existing_weight {
          value_weights[value] = (weight, kind)
        }
      None => value_weights[value] = (weight, kind)
    }
  }
  let gaps : Array[GapTerm] = []
  for vw in value_weights {
    let value = vw.0
    let (weight, kind) = vw.1
    gaps.push({ term: kind + ":" + value, value, weight, kind })
  }
  gaps.sort_by(fn(a, b) { b.weight.compare(a.weight) })
  // Kneedle thresholding: find the "knee" in the weight curve to separate
  // signal from noise. However, when nearly all tokens are gaps (high cosine
  // distance), the weight distribution is flat and Kneedle produces an
  // artificially low cutoff. In that case, return all gaps.
  if gaps.length() <= 1 {
    return apply_limit(gaps, config.max_terms)
  }
  let weights = gaps.map(fn(g) { g.weight })
  let cutoff = @stats.kneedle_threshold_index(weights)
  // If Kneedle would discard more than 90% of gaps, the weight curve is
  // too flat for meaningful thresholding — return all gaps instead.
  let min_cutoff = gaps.length() / 10 + 1
  let effective_cutoff = if cutoff < min_cutoff {
    gaps.length()
  } else {
    cutoff
  }
  let limit = if effective_cutoff < gaps.length() {
    effective_cutoff
  } else {
    gaps.length()
  }
  let result : Array[GapTerm] = []
  for i = 0; i < limit; i = i + 1 {
    result.push(gaps[i])
  }
  apply_limit(result, config.max_terms)
}

///|
fn apply_limit(terms : Array[GapTerm], max : Int) -> Array[GapTerm] {
  if max <= 0 || terms.length() <= max {
    return terms
  }
  let result : Array[GapTerm] = []
  for i = 0; i < max; i = i + 1 {
    result.push(terms[i])
  }
  result
}

///|
fn is_numeric_value(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  let mut start = 0
  if s[0] == '-' {
    start = 1
  }
  if start >= s.length() {
    return false
  }
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}
