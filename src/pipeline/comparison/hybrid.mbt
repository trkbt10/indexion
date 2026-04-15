///|
/// Hybrid comparison: multi-signal evidence fusion for code duplicate detection.
///
/// Each scorer measures a different facet of similarity:
///   - BM25:  Lexical overlap with TF saturation + document length normalization.
///            Sensitive to shared identifiers and keywords.
///   - JSD:   Information-theoretic divergence of token probability distributions.
///            Sensitive to how tokens are distributed, not just which ones appear.
///   - TSED:  Tree Structure Edit Distance (Zhang-Shasha with finalized labels).
///            Sensitive to AST structure, resilient to variable renaming.
///
/// Evidence fusion model:
///
///   Each signal provides "evidence" of similarity. The fusion considers
///   how many signals agree, because a single high signal is unreliable
///   (e.g., high BM25 alone may just mean shared API usage).
///
///   Lexical evidence = agreement-weighted combination of BM25 and JSD:
///     When both are high → strong lexical evidence (bonus for agreement)
///     When one is high, other low → weaker evidence (discounted)
///
///   Final score with structural evidence:
///     When lexical AND structural agree → boost (high confidence)
///     When they disagree → take the higher but discount it
///     When only lexical available → use lexical (no discount, no boost)
///
/// Candidate generation:
///   BM25 inverted index (fast) generates candidates at a relaxed threshold.
///   JSD is computed for all candidates (cheap: O(V) per pair from precomputed TF).
///   TSED is gated by dataset size, tree complexity, and per-pair lexical score.

///|
/// Tuning parameters for hybrid comparison.
priv struct HybridParams {
  /// Minimum agreement between BM25 and JSD to count as "concordant".
  /// If |bm25 - jsd| < concordance_band, they agree.
  concordance_band : Double
  /// Bonus multiplier when lexical signals agree (both above threshold).
  concordance_bonus : Double
  /// Weight for the stronger lexical signal when signals disagree.
  discordance_higher_weight : Double
  /// Weight for the weaker lexical signal when signals disagree.
  discordance_lower_weight : Double
  /// Discount applied after blending disagreeing lexical signals.
  discordance_penalty : Double
  /// Boost when lexical and structural evidence both exceed threshold.
  cross_signal_boost : Double
  /// Discount factor when structural evidence contradicts lexical.
  /// Applied when structural is much lower than lexical.
  structural_contradiction_discount : Double
  /// Threshold below which structural score is treated as contradicting evidence.
  /// Expressed as a fraction of the lexical score.
  structural_contradiction_ratio : Double
  /// Relaxation factor for BM25 candidate generation (lower = more candidates).
  candidate_relaxation : Double
  /// Strict candidate relaxation for large datasets.
  strict_candidate_relaxation : Double
  /// Minimum lexical score (as fraction of threshold) to attempt structural comparison.
  structural_gate_factor : Double
  /// Max avg tree size before skipping structural comparison entirely.
  max_avg_tree_size : Int
  /// Avg tree size considered "small" (cheap structural comparison).
  small_tree_size : Int
  /// File count thresholds for brute-force / prefilter / strict / skip.
  brute_force_max_files : Int
  prefilter_max_files : Int
  strict_max_files : Int
  /// Max tree nodes per pair in strict mode.
  strict_max_nodes : Int
  /// Max tree nodes per pair in normal mode.
  normal_max_nodes : Int
  /// Weight for the stronger signal in partial-agreement blending.
  partial_higher_weight : Double
  /// Weight for the weaker signal in partial-agreement blending.
  partial_lower_weight : Double
}

///|
fn HybridParams::default() -> HybridParams {
  {
    // Lexical evidence fusion
    concordance_band: 0.15,
    concordance_bonus: 1.1,
    discordance_higher_weight: 0.7,
    discordance_lower_weight: 0.3,
    discordance_penalty: 0.85,
    // Cross-signal (lexical × structural) fusion
    cross_signal_boost: 1.08,
    structural_contradiction_discount: 0.75,
    structural_contradiction_ratio: 0.5,
    // Candidate generation
    candidate_relaxation: 0.5,
    strict_candidate_relaxation: 0.7,
    // Structural gating
    structural_gate_factor: 0.3,
    max_avg_tree_size: 200,
    small_tree_size: 50,
    brute_force_max_files: 20,
    prefilter_max_files: 200,
    strict_max_files: 500,
    strict_max_nodes: 100,
    normal_max_nodes: 500,
    partial_higher_weight: 0.65,
    partial_lower_weight: 0.35,
  }
}

///|
/// Fuse BM25 and JSD into a single lexical evidence score.
///
/// Rather than max or average, this considers the agreement between signals:
/// - Both high and close together → strong evidence, slight bonus
/// - One high and one low → weaker evidence, discounted
/// - Both low → low score (correctly reflects low similarity)
fn fuse_lexical(bm25 : Double, jsd : Double, params : HybridParams) -> Double {
  let higher = if bm25 > jsd { bm25 } else { jsd }
  let lower = if bm25 > jsd { jsd } else { bm25 }
  let gap = higher - lower
  if gap <= params.concordance_band {
    // Signals agree: take average and apply concordance bonus.
    // Average is more robust than max when both signals provide evidence.
    let avg = (bm25 + jsd) / 2.0
    let boosted = avg * params.concordance_bonus
    // Cap at 1.0
    if boosted > 1.0 {
      1.0
    } else {
      boosted
    }
  } else {
    // Signals disagree: the high signal might be a false positive.
    // Use a weighted combination that favors the higher signal
    // but applies a discount for the disagreement.
    //
    // Weighted towards higher because the higher signal
    // does carry information, but the low counterpart reduces confidence.
    let weighted = higher * params.discordance_higher_weight +
      lower * params.discordance_lower_weight
    weighted * params.discordance_penalty
  }
}

///|
/// Fuse lexical evidence with structural evidence into final score.
///
/// The key insight: structural similarity is the stronger signal for
/// code duplication (catches renamed copies), but lexical provides
/// context that prevents structural false positives (e.g., two simple
/// for-loops that happen to have the same structure).
///
/// - Both high → high confidence, slight boost
/// - Lexical high, structural low → structural contradicts: discount
/// - Structural high, lexical low → possible renamed copy, but uncertain
/// - Only lexical available → pass through (no structural evidence to use)
fn fuse_final(
  lexical : Double,
  structural : Double,
  has_structural : Bool,
  threshold : Double,
  params : HybridParams,
) -> Double {
  if !has_structural {
    // No structural evidence: lexical score stands alone.
    // Not boosted (no corroboration) but not penalized either
    // (absence of evidence is not evidence of absence).
    return lexical
  }
  // Both signals available: evaluate agreement
  let both_above = lexical >= threshold && structural >= threshold
  if both_above {
    // Cross-signal agreement: strong confidence in similarity.
    // Take the higher signal as base and apply a modest boost.
    let base = if lexical > structural { lexical } else { structural }
    let boosted = base * params.cross_signal_boost
    if boosted > 1.0 {
      1.0
    } else {
      boosted
    }
  } else if structural < lexical * params.structural_contradiction_ratio {
    // Structural evidence contradicts: structure is very different
    // despite lexical similarity. This is a strong signal against
    // true duplication (likely just shared API/vocabulary).
    // Discount the lexical score.
    lexical * params.structural_contradiction_discount
  } else {
    // Partial agreement or structural is moderate.
    // Blend with emphasis on the stronger signal.
    // This handles cases like:
    //   - lexical=0.7, structural=0.5 → result ≈ 0.65 (reasonable)
    //   - lexical=0.4, structural=0.8 → result ≈ 0.68 (structural lifts)
    let higher = if lexical > structural { lexical } else { structural }
    let lower = if lexical > structural { structural } else { lexical }
    higher * params.partial_higher_weight + lower * params.partial_lower_weight
  }
}

///|
/// Hybrid comparison with multi-signal evidence fusion.
pub fn compare_hybrid(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  let n = files.length()
  let params = HybridParams::default()
  let registry = @kgf_features.load_registry()
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  // Tokenize once, shared across all lexical scorers
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  // Build lexical scoring batches
  let bm25_batch = @tfidf.BM25Batch::from_tokens(tokenized)
  let jsd_batch = @tfidf.JSDBatch::from_tokens(tokenized)
  // Candidate generation via BM25 inverted index (fast).
  // Relaxed threshold: we need candidates that JSD or structural might elevate.
  let candidate_threshold = threshold * params.candidate_relaxation
  let bm25_candidates = bm25_batch.all_pairs_above_threshold(
    candidate_threshold,
  )
  // Compute lexical evidence for all candidates
  let pair_lexical : Map[String, Double] = {}
  let pair_indices : Array[(Int, Int)] = []
  let pair_keys_seen : Map[String, Bool] = {}
  for pair in bm25_candidates {
    let (raw_i, raw_j, bm25_sim) = pair
    let i = if raw_i < raw_j { raw_i } else { raw_j }
    let j = if raw_i < raw_j { raw_j } else { raw_i }
    let key = @candidates.pair_key(i, j)
    if pair_keys_seen.contains(key) {
      continue
    }
    pair_keys_seen.set(key, true)
    let jsd_sim = jsd_batch.similarity(i, j)
    let lexical = fuse_lexical(bm25_sim, jsd_sim, params)
    pair_lexical.set(key, lexical)
    pair_indices.push((i, j))
  }
  // Extract trees and measure complexity
  let all_trees : Array[Array[@apted.TreeNode]] = []
  let mut total_tree_nodes = 0
  let mut total_trees = 0
  for file in files {
    let trees = @tree_extract.extract(file.display_name, file.content, registry)
    for tree in trees {
      total_tree_nodes += tree.size()
      total_trees += 1
    }
    all_trees.push(trees)
  }
  let avg_tree_size = if total_trees > 0 {
    total_tree_nodes / total_trees
  } else {
    0
  }
  // Decide structural analysis intensity
  let structural_mode = select_structural_mode(n, avg_tree_size, params)
  if structural_mode == 0 {
    // No structural analysis possible: emit lexical-only results
    return emit_lexical_only(pair_lexical, pair_indices, threshold, files, n)
  }
  // Determine which pairs warrant structural comparison
  let structural_candidate_set : Map[String, Bool] = {}
  let structural_pairs = if structural_mode == 1 {
    @candidates.brute_force(n)
  } else if structural_mode == 2 {
    @candidates.normalize_pairs(
      bm25_batch.all_pairs_above_threshold(candidate_threshold),
    )
  } else {
    @candidates.normalize_pairs(
      bm25_batch.all_pairs_above_threshold(
        threshold * params.strict_candidate_relaxation,
      ),
    )
  }
  for pair in structural_pairs {
    let (i, j) = pair
    structural_candidate_set.set(@candidates.pair_key(i, j), true)
  }
  // TSED with finalized labels: structure-aware comparison that encodes
  // child count into node labels, making "if with 2 branches" distinct
  // from "if with 3 branches".
  let tsed_config = @apted.TSEDConfig::default()
  let max_nodes = if structural_mode == 3 {
    params.strict_max_nodes
  } else {
    params.normal_max_nodes
  }
  let structural_gate = threshold * params.structural_gate_factor
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  for pair in pair_indices {
    let (i, j) = pair
    let key = @candidates.pair_key(i, j)
    let lexical = pair_lexical.get(key).unwrap_or(0.0)
    // Should we attempt structural comparison for this pair?
    let do_structural = structural_candidate_set.contains(key) &&
      lexical >= structural_gate
    let mut best_tsed = 0.0
    let mut has_structural = false
    if do_structural {
      let trees_i = all_trees[i]
      let trees_j = all_trees[j]
      if max_tree_nodes(trees_i, trees_j) <= max_nodes {
        for ti in trees_i {
          for tj in trees_j {
            if @apted.should_compare_trees(ti, tj, threshold) {
              pairs_compared += 1
              has_structural = true
              let sim = @apted.calculate_tsed(ti, tj, tsed_config)
              if sim > best_tsed {
                best_tsed = sim
              }
            }
          }
        }
      }
    }
    let combined = fuse_final(
      lexical, best_tsed, has_structural, threshold, params,
    )
    if combined >= threshold {
      matches.push(
        SimilarityMatch::new(
          i,
          j,
          files[i].display_name,
          files[j].display_name,
          combined,
        ),
      )
    }
  }
  { matches, file_count: n, pairs_compared }
}

///|
/// Structural mode selection:
/// 0 = lexical only (too many files or trees too large)
/// 1 = brute-force TSED (small dataset, every pair)
/// 2 = prefiltered TSED (medium dataset, BM25 candidates only)
/// 3 = strict prefiltered TSED (large dataset, tighter BM25 filter)
fn select_structural_mode(
  file_count : Int,
  avg_tree_size : Int,
  params : HybridParams,
) -> Int {
  // Trees too large: TSED O(n²m²) would be prohibitive
  if avg_tree_size > params.max_avg_tree_size {
    return 0
  }
  if avg_tree_size <= params.small_tree_size {
    // Small trees: TSED is cheap
    if file_count <= params.brute_force_max_files {
      return 1
    }
    if file_count <= params.prefilter_max_files {
      return 2
    }
    return 3
  }
  // Medium trees: tighter file count limits
  if file_count <= params.brute_force_max_files / 2 {
    1
  } else if file_count <= params.prefilter_max_files / 2 {
    2
  } else if file_count <= params.strict_max_files {
    3
  } else {
    0
  }
}

///|
/// Compute maximum total tree node count across two tree sets.
fn max_tree_nodes(
  trees_a : Array[@apted.TreeNode],
  trees_b : Array[@apted.TreeNode],
) -> Int {
  let mut max_a = 0
  let mut max_b = 0
  for t in trees_a {
    let s = t.size()
    if s > max_a {
      max_a = s
    }
  }
  for t in trees_b {
    let s = t.size()
    if s > max_b {
      max_b = s
    }
  }
  max_a + max_b
}

///|
/// Emit results when only lexical evidence is available.
fn emit_lexical_only(
  pair_lexical : Map[String, Double],
  pair_indices : Array[(Int, Int)],
  threshold : Double,
  files : Array[FileEntry],
  file_count : Int,
) -> BatchResult {
  let matches : Array[SimilarityMatch] = []
  for pair in pair_indices {
    let (i, j) = pair
    let key = @candidates.pair_key(i, j)
    let score = pair_lexical.get(key).unwrap_or(0.0)
    if score >= threshold {
      matches.push(
        SimilarityMatch::new(
          i,
          j,
          files[i].display_name,
          files[j].display_name,
          score,
        ),
      )
    }
  }
  { matches, file_count, pairs_compared: file_count * (file_count - 1) / 2 }
}
