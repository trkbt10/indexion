///|
/// Tree-based comparison: APTED and TSED with TF-IDF pre-filtering.
/// Trees are indexed once and reused across all pairwise comparisons.
/// Size-based upper bounds prune comparisons that cannot reach the threshold
/// or beat the current best score.

///|
/// Run batch comparison using APTED strategy.
pub fn compare_apted(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let cost_config = @apted.CostConfig::default()
  compare_trees_core(
    files,
    threshold,
    fn(tree) { @apted.index_tree_with_size(tree) },
    fn(size1, size2) {
      @apted.unit_cost_tree_similarity_upper_bound(size1, size2)
    },
    fn(ti, tj) {
      let (idx_i, size_i) = ti
      let (idx_j, size_j) = tj
      @apted.tree_similarity_indexed(idx_i, size_i, idx_j, size_j, cost_config)
    },
  )
}

///|
/// Run batch comparison using TSED strategy.
pub fn compare_tsed(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let tsed_config = @apted.TSEDConfig::default()
  compare_trees_core(
    files,
    threshold,
    fn(tree) { @apted.prepare_tsed_tree(tree, tsed_config) },
    fn(size1, size2) { @apted.tsed_similarity_upper_bound(size1, size2) },
    fn(ti, tj) {
      let (idx_i, size_i) = ti
      let (idx_j, size_j) = tj
      @apted.calculate_tsed_indexed(idx_i, size_i, idx_j, size_j, tsed_config)
    },
  )
}

///|
/// Core tree comparison with TF-IDF pre-filtering and cached indexed trees.
fn compare_trees_core(
  files : Array[FileEntry],
  threshold : Double,
  prepare_tree_fn : (@apted.TreeNode) -> (@apted.IndexedTree, Int),
  upper_bound_fn : (Int, Int) -> Double,
  tree_score_fn : ((@apted.IndexedTree, Int), (@apted.IndexedTree, Int)) -> Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let registry = @kgf_features.load_registry()
  // Extract and index trees once per file
  let all_trees : Array[Array[(@apted.IndexedTree, Int)]] = []
  for file in files {
    let raw_trees = @tree_extract.extract(
      file.display_name,
      file.content,
      registry,
    )
    let prepared : Array[(@apted.IndexedTree, Int)] = []
    for tree in raw_trees {
      prepared.push(prepare_tree_fn(tree))
    }
    all_trees.push(prepared)
  }
  let n = files.length()
  let candidate_pairs = if n <= prefilter_min_files {
    @candidates.brute_force(n)
  } else {
    let file_pairs : Array[(String, String)] = []
    for file in files {
      file_pairs.push((file.display_name, file.content))
    }
    if n >= minhash_min_files {
      @candidates.minhash_prefilter(
        file_pairs,
        registry,
        threshold * prefilter_factor,
      )
    } else {
      @candidates.tfidf_prefilter(
        file_pairs,
        registry,
        threshold * prefilter_factor,
      )
    }
  }
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  for pair in candidate_pairs {
    let (i, j) = pair
    let trees_i = all_trees[i]
    let trees_j = all_trees[j]
    let mut best_sim = 0.0
    for ti in trees_i {
      let (_, size_i) = ti
      for tj in trees_j {
        let (_, size_j) = tj
        let upper_bound = upper_bound_fn(size_i, size_j)
        // Skip if upper bound cannot reach threshold or beat current best
        if upper_bound < threshold || upper_bound <= best_sim {
          continue
        }
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
  { matches, file_count: n, pairs_compared, }
}

///|
/// Run function-level batch comparison using APTED strategy.
/// Returns matches with qualified function names (file::func) in file1/file2.
pub fn compare_apted_functions(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let cost_config = @apted.CostConfig::default()
  compare_functions_core(
    files,
    threshold,
    fn(tree) { @apted.index_tree_with_size(tree) },
    fn(size1, size2) {
      @apted.unit_cost_tree_similarity_upper_bound(size1, size2)
    },
    fn(ti, tj) {
      let (idx_i, size_i) = ti
      let (idx_j, size_j) = tj
      @apted.tree_similarity_indexed(idx_i, size_i, idx_j, size_j, cost_config)
    },
  )
}

///|
/// Run function-level batch comparison using TSED strategy.
/// Returns matches with qualified function names (file::func) in file1/file2.
pub fn compare_tsed_functions(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  let tsed_config = @apted.TSEDConfig::default()
  compare_functions_core(
    files,
    threshold,
    fn(tree) { @apted.prepare_tsed_tree(tree, tsed_config) },
    fn(size1, size2) { @apted.tsed_similarity_upper_bound(size1, size2) },
    fn(ti, tj) {
      let (idx_i, size_i) = ti
      let (idx_j, size_j) = tj
      @apted.calculate_tsed_indexed(idx_i, size_i, idx_j, size_j, tsed_config)
    },
  )
}

///|
/// Core function-level comparison with cached indexed trees and size-based pruning.
fn compare_functions_core(
  files : Array[FileEntry],
  threshold : Double,
  prepare_tree_fn : (@apted.TreeNode) -> (@apted.IndexedTree, Int),
  upper_bound_fn : (Int, Int) -> Double,
  tree_score_fn : ((@apted.IndexedTree, Int), (@apted.IndexedTree, Int)) -> Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let registry = @kgf_features.load_registry()
  // Extract functions and index trees once per function
  let all_functions : Array[
    (@kgf_features.ExtractedFunction, (@apted.IndexedTree, Int)),
  ] = []
  for file in files {
    let func_trees = @tree_extract.extract_functions(
      file.display_name,
      file.content,
      registry,
    )
    for ft in func_trees {
      let (func, tree) = ft
      all_functions.push((func, prepare_tree_fn(tree)))
    }
  }
  if all_functions.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let matches : Array[SimilarityMatch] = []
  let mut pairs_compared = 0
  for i = 0; i < all_functions.length(); i = i + 1 {
    let (func1, prepared1) = all_functions[i]
    let (_, size1) = prepared1
    for j = i + 1; j < all_functions.length(); j = j + 1 {
      let (func2, prepared2) = all_functions[j]
      // Skip same-name functions in the same file
      if func1.get_file() == func2.get_file() &&
        func1.get_name() == func2.get_name() {
        continue
      }
      let (_, size2) = prepared2
      if upper_bound_fn(size1, size2) < threshold {
        continue
      }
      pairs_compared += 1
      let sim = tree_score_fn(prepared1, prepared2)
      if sim >= threshold {
        matches.push(
          SimilarityMatch::new(
            i,
            j,
            func1.qualified_name(),
            func2.qualified_name(),
            sim,
          ),
        )
      }
    }
  }
  { matches, file_count: files.length(), pairs_compared, }
}
