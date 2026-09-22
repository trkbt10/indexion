///|
/// TF-IDF batch comparison: fast lexical similarity using KGF tokenization.

///|
/// Run batch comparison using TF-IDF strategy.
pub fn compare_tfidf(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  let registry = @kgf_features.load_registry()
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  let batch = @tfidf.TfidfBatch::from_tokens(tokenized)
  let pairs = batch.all_pairs_above_threshold(threshold)
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
  { matches, file_count: n, pairs_compared: n * (n - 1) / 2, }
}

///|
/// Run batch comparison using BM25 strategy.
/// BM25 adds document length normalization and term frequency saturation
/// over standard TF-IDF, producing more accurate similarity for documents
/// of varying lengths.
pub fn compare_bm25(
  files : Array[FileEntry],
  threshold : Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  let registry = @kgf_features.load_registry()
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  let batch = @tfidf.BM25Batch::from_tokens(tokenized)
  let pairs = batch.all_pairs_above_threshold(threshold)
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
  { matches, file_count: n, pairs_compared: n * (n - 1) / 2, }
}

///|
/// Run batch comparison using Jensen-Shannon Divergence.
/// JSD measures divergence between token probability distributions,
/// capturing different information than cosine similarity.
pub fn compare_jsd(files : Array[FileEntry], threshold : Double) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let file_pairs : Array[(String, String)] = []
  for file in files {
    file_pairs.push((file.display_name, file.content))
  }
  let registry = @kgf_features.load_registry()
  let (tokenized, _) = @kgf_features.tokenize_files_with_kgf(
    file_pairs, registry,
  )
  let batch = @tfidf.JSDBatch::from_tokens(tokenized)
  let pairs = batch.all_pairs_above_threshold(threshold)
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
  { matches, file_count: n, pairs_compared: n * (n - 1) / 2, }
}

///|
/// Run pairwise comparison with pre-filtering.
/// Uses brute-force for small sets, TF-IDF inverted index for medium sets,
/// and MinHash+LSH for large sets.
/// The score_fn receives (content_i, content_j) and returns similarity in [0, 1].
pub fn compare_with_prefilter(
  files : Array[FileEntry],
  threshold : Double,
  score_fn : (String, String) -> Double,
) -> BatchResult {
  if files.length() < 2 {
    return { matches: [], file_count: files.length(), pairs_compared: 0, }
  }
  let n = files.length()
  let candidate_pairs = if n <= prefilter_min_files {
    @candidates.brute_force(n)
  } else {
    let file_pairs : Array[(String, String)] = []
    for file in files {
      file_pairs.push((file.display_name, file.content))
    }
    let registry = @kgf_features.load_registry()
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
  for pair in candidate_pairs {
    let (i, j) = pair
    let sim = score_fn(files[i].content, files[j].content)
    if sim >= threshold {
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
  { matches, file_count: n, pairs_compared: candidate_pairs.length(), }
}
