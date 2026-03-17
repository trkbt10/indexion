///|
/// Tree-based comparison: APTED and TSED with TF-IDF pre-filtering.

///|
/// Run batch comparison using APTED strategy.
pub fn compare_apted(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let cost_config = @apted.CostConfig::default()
  compare_trees_core(files, threshold, fn(ti, tj) {
    @apted.tree_similarity(ti, tj, cost_config)
  })
}

///|
/// Run batch comparison using TSED strategy.
pub fn compare_tsed(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let tsed_config = @apted.TSEDConfig::default()
  compare_trees_core(files, threshold, fn(ti, tj) {
    @apted.calculate_tsed(ti, tj, tsed_config)
  })
}

///|
/// Core tree comparison with TF-IDF pre-filtering.
fn compare_trees_core(
  files : Array[FileEntry],
  threshold : Double,
  tree_score_fn : (@apted.TreeNode, @apted.TreeNode) -> Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0 }
  }
  let registry = @kgf_features.load_registry()
  let all_trees : Array[Array[@apted.TreeNode]] = []
  for file in files {
    let trees = @tree_extract.extract(file.display_name, file.content, registry)
    all_trees.push(trees)
  }
  let n = files.length()
  let candidate_pairs = if n > prefilter_min_files {
    let file_pairs : Array[(String, String)] = []
    for file in files {
      file_pairs.push((file.display_name, file.content))
    }
    @candidates.tfidf_prefilter(
      file_pairs,
      registry,
      threshold * prefilter_factor,
    )
  } else {
    @candidates.brute_force(n)
  }
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  for pair in candidate_pairs {
    let (i, j) = pair
    let trees_i = all_trees[i]
    let trees_j = all_trees[j]
    let mut best_sim = 0.0
    for ti in trees_i {
      for tj in trees_j {
        pairs_compared += 1
        let sim = tree_score_fn(ti, tj)
        if sim > best_sim {
          best_sim = sim
        }
      }
    }
    if best_sim >= threshold {
      matches.push(
        SimilarityMatch::new(
          i,
          j,
          files[i].display_name,
          files[j].display_name,
          best_sim,
        ),
      )
    }
  }
  { matches, file_count: n, pairs_compared }
}
