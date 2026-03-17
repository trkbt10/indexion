///|
/// Tuning parameters for hybrid comparison.
/// Controls the dynamic switching between TF-IDF and APTED.
priv struct HybridParams {
  /// TF-IDF prefilter relaxation (lower = more candidates)
  prefilter_factor : Double
  /// Strict prefilter relaxation
  strict_prefilter_factor : Double
  /// Max avg tree size before skipping APTED
  max_avg_tree_size : Int
  /// Avg tree size considered "small" (cheap APTED)
  small_tree_size : Int
  /// File count thresholds for brute-force / prefilter / strict / skip
  brute_force_max_files : Int
  prefilter_max_files : Int
  strict_max_files : Int
  /// Max tree nodes per pair for APTED (strict mode)
  strict_max_nodes : Int
  /// Max tree nodes per pair for APTED (normal mode)
  normal_max_nodes : Int
}

///|
fn HybridParams::default() -> HybridParams {
  {
    prefilter_factor: 0.5,
    strict_prefilter_factor: 0.7,
    max_avg_tree_size: 200,
    small_tree_size: 50,
    brute_force_max_files: 20,
    prefilter_max_files: 200,
    strict_max_files: 500,
    strict_max_nodes: 100,
    normal_max_nodes: 500,
  }
}

///|
/// Dynamic hybrid comparison: combines TF-IDF (fast lexical) and
/// APTED (precise structural) based on dataset characteristics.

///|
/// Hybrid comparison with automatic strategy selection.
pub fn compare_hybrid(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  let n = files.length()
  let registry = @kgf_features.load_registry()
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  // TF-IDF: always computed (fast, also needed for pre-filtering)
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
  let tfidf_pairs = batch.all_pairs_above_threshold(threshold)
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
  // Dynamic strategy selection
  let params = HybridParams::default()
  let apted_mode = select_apted_mode(n, avg_tree_size, params)
  if apted_mode == 0 {
    return tfidf_to_result(tfidf_pairs, files)
  }
  // Determine APTED candidate pairs
  let apted_candidates = if apted_mode == 1 {
    @candidates.brute_force(n)
  } else if apted_mode == 2 {
    @candidates.normalize_pairs(
      batch.all_pairs_above_threshold(threshold * params.prefilter_factor),
    )
  } else {
    @candidates.normalize_pairs(
      batch.all_pairs_above_threshold(
        threshold * params.strict_prefilter_factor,
      ),
    )
  }
  // Score candidates with APTED, merge with TF-IDF
  let tfidf_scores : Map[String, Double] = {}
  for pair in tfidf_pairs {
    let (i, j, sim) = pair
    tfidf_scores.set(@candidates.pair_key(i, j), sim)
  }
  let cost_config = @apted.CostConfig::default()
  let max_nodes = if apted_mode == 3 {
    params.strict_max_nodes
  } else {
    params.normal_max_nodes
  }
  let matches : Array[SimilarityMatch] = []
  let seen : Map[String, Bool] = {}
  let mut pairs_compared = 0
  for pair in apted_candidates {
    let (i, j) = pair
    let key = @candidates.pair_key(i, j)
    if seen.contains(key) {
      continue
    }
    seen.set(key, true)
    let trees_i = all_trees[i]
    let trees_j = all_trees[j]
    // Skip APTED when tree pair exceeds node budget
    let mut best_tree_sim = 0.0
    if max_tree_nodes(trees_i, trees_j) <= max_nodes {
      for ti in trees_i {
        for tj in trees_j {
          pairs_compared += 1
          let sim = @apted.tree_similarity(ti, tj, cost_config)
          if sim > best_tree_sim {
            best_tree_sim = sim
          }
        }
      }
    }
    let tfidf_sim = match tfidf_scores.get(key) {
      Some(s) => s
      None => 0.0
    }
    let combined = if tfidf_sim > best_tree_sim {
      tfidf_sim
    } else {
      best_tree_sim
    }
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
  // Add TF-IDF-only pairs not covered by APTED candidates
  for pair in tfidf_pairs {
    let (pi, pj, sim) = pair
    let i = if pi < pj { pi } else { pj }
    let j = if pi < pj { pj } else { pi }
    let key = @candidates.pair_key(i, j)
    if not(seen.contains(key)) && sim >= threshold {
      matches.push(
        SimilarityMatch::new(
          i,
          j,
          files[i].display_name,
          files[j].display_name,
          sim,
        ),
      )
    }
  }
  { matches, file_count: n, pairs_compared }
}

///|
/// 0=TF-IDF only, 1=brute_force APTED, 2=prefilter APTED, 3=strict prefilter
fn select_apted_mode(
  file_count : Int,
  avg_tree_size : Int,
  params : HybridParams,
) -> Int {
  if avg_tree_size > params.max_avg_tree_size {
    return 0
  }
  if avg_tree_size <= params.small_tree_size {
    if file_count <= params.brute_force_max_files {
      return 1
    }
    if file_count <= params.prefilter_max_files {
      return 2
    }
    return 3
  }
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
fn tfidf_to_result(
  pairs : Array[(Int, Int, Double)],
  files : Array[FileEntry],
) -> BatchResult {
  let matches : Array[SimilarityMatch] = []
  for pair in pairs {
    let (i, j, sim) = pair
    matches.push(
      SimilarityMatch::new(
        i,
        j,
        files[i].display_name,
        files[j].display_name,
        sim,
      ),
    )
  }
  let n = files.length()
  { matches, file_count: n, pairs_compared: n * (n - 1) / 2 }
}
