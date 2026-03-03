// Node importance scoring for dependency graphs.
// Combines reference count, edge centrality, and TF-IDF uniqueness.

///|
/// Score all modules in a CodeGraph by importance.
/// Returns scores sorted descending by importance.
pub fn score_modules(
  graph : @graph.CodeGraph,
  config : FoldConfig,
) -> Array[NodeImportance] {
  let modules = graph.get_modules()
  if modules.length() == 0 {
    return []
  }
  // Collect module IDs
  let module_ids : Array[String] = []
  for entry in modules {
    module_ids.push(entry.0)
  }
  // Signal 1: Reference count / dependency fan-in
  let ref_scores = compute_ref_scores(graph, module_ids)
  // Signal 2: Edge centrality (fan-in + fan-out)
  let centrality_scores = compute_centrality_scores(graph, module_ids)
  // Signal 3: TF-IDF uniqueness of node names
  let tfidf_scores = compute_tfidf_scores(module_ids)
  // Aggregate signals with configured weights
  let total_weight = config.ref_weight +
    config.centrality_weight +
    config.tfidf_weight
  let results : Array[NodeImportance] = []
  for id in module_ids {
    let ref_s = ref_scores.get(id).unwrap_or(0.0)
    let centrality_s = centrality_scores.get(id).unwrap_or(0.0)
    let tfidf_s = tfidf_scores.get(id).unwrap_or(0.0)
    let composite = if total_weight > 0.0 {
      (
        config.ref_weight * ref_s +
        config.centrality_weight * centrality_s +
        config.tfidf_weight * tfidf_s
      ) /
      total_weight
    } else {
      0.0
    }
    let signals = ImportanceSignals::new(ref_s, centrality_s, tfidf_s)
    results.push(NodeImportance::new(id, composite, signals))
  }
  // Sort descending by score
  sort_by_score_desc(results)
  results
}

///|
/// Score all symbols in a CodeGraph by importance.
pub fn score_symbols(
  graph : @graph.CodeGraph,
  config : FoldConfig,
) -> Array[NodeImportance] {
  let symbols = graph.get_symbols()
  if symbols.length() == 0 {
    return []
  }
  let symbol_ids : Array[String] = []
  for entry in symbols {
    symbol_ids.push(entry.0)
  }
  let ref_scores = compute_ref_scores(graph, symbol_ids)
  let centrality_scores = compute_centrality_scores(graph, symbol_ids)
  let tfidf_scores = compute_tfidf_scores(symbol_ids)
  let total_weight = config.ref_weight +
    config.centrality_weight +
    config.tfidf_weight
  let results : Array[NodeImportance] = []
  for id in symbol_ids {
    let ref_s = ref_scores.get(id).unwrap_or(0.0)
    let centrality_s = centrality_scores.get(id).unwrap_or(0.0)
    let tfidf_s = tfidf_scores.get(id).unwrap_or(0.0)
    let composite = if total_weight > 0.0 {
      (
        config.ref_weight * ref_s +
        config.centrality_weight * centrality_s +
        config.tfidf_weight * tfidf_s
      ) /
      total_weight
    } else {
      0.0
    }
    let signals = ImportanceSignals::new(ref_s, centrality_s, tfidf_s)
    results.push(NodeImportance::new(id, composite, signals))
  }
  sort_by_score_desc(results)
  results
}

///|
/// Compute reference scores: how many edges point TO each node.
/// Normalized to [0, 1] via min-max.
fn compute_ref_scores(
  graph : @graph.CodeGraph,
  node_ids : Array[String],
) -> Map[String, Double] {
  let counts : Map[String, Int] = {}
  for id in node_ids {
    counts.set(id, 0)
  }
  // Count incoming edges
  for edge in graph.get_edges() {
    match counts.get(edge.to) {
      Some(c) => counts.set(edge.to, c + 1)
      None => ()
    }
  }
  // Normalize
  let values : Array[Double] = []
  for id in node_ids {
    values.push(counts.get(id).unwrap_or(0).to_double())
  }
  let normalized = min_max_normalize(values)
  let result : Map[String, Double] = {}
  for i, id in node_ids {
    result.set(id, normalized[i])
  }
  result
}

///|
/// Compute centrality scores: fan-in + fan-out per node.
/// Normalized to [0, 1] via min-max.
fn compute_centrality_scores(
  graph : @graph.CodeGraph,
  node_ids : Array[String],
) -> Map[String, Double] {
  let in_counts : Map[String, Int] = {}
  let out_counts : Map[String, Int] = {}
  for id in node_ids {
    in_counts.set(id, 0)
    out_counts.set(id, 0)
  }
  for edge in graph.get_edges() {
    match out_counts.get(edge.from) {
      Some(c) => out_counts.set(edge.from, c + 1)
      None => ()
    }
    match in_counts.get(edge.to) {
      Some(c) => in_counts.set(edge.to, c + 1)
      None => ()
    }
  }
  // Centrality = fan-in + fan-out
  let values : Array[Double] = []
  for id in node_ids {
    let fan_in = in_counts.get(id).unwrap_or(0)
    let fan_out = out_counts.get(id).unwrap_or(0)
    values.push((fan_in + fan_out).to_double())
  }
  let normalized = min_max_normalize(values)
  let result : Map[String, Double] = {}
  for i, id in node_ids {
    result.set(id, normalized[i])
  }
  result
}

///|
/// Compute TF-IDF uniqueness scores for node names.
/// Nodes with unique/distinctive names get higher scores.
/// Uses the node ID/name as a "document" and computes how distinctive
/// each node's terms are across the corpus of all node names.
fn compute_tfidf_scores(node_ids : Array[String]) -> Map[String, Double] {
  if node_ids.length() == 0 {
    return {}
  }
  // Tokenize each node name
  let tokenized : Array[Array[String]] = []
  for id in node_ids {
    tokenized.push(@tokenizer.tokenize_for_tfidf(id))
  }
  // Build document frequency
  let df = @tfidf.build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  // Build TF-IDF vectors and compute L2 norm as "uniqueness"
  let norms : Array[Double] = []
  for tokens in tokenized {
    let vector = @tfidf.build_tfidf_vector(tokens, df, total_docs)
    let mut sum = 0.0
    for entry in vector.iter() {
      sum = sum + entry.1 * entry.1
    }
    norms.push(sum.sqrt())
  }
  // Normalize
  let normalized = min_max_normalize(norms)
  let result : Map[String, Double] = {}
  for i, id in node_ids {
    result.set(id, normalized[i])
  }
  result
}

///|
/// Min-max normalize values to [0, 1].
fn min_max_normalize(values : Array[Double]) -> Array[Double] {
  if values.length() == 0 {
    return []
  }
  let mut min_val = values[0]
  let mut max_val = values[0]
  for v in values {
    if v < min_val {
      min_val = v
    }
    if v > max_val {
      max_val = v
    }
  }
  let range = max_val - min_val
  if range == 0.0 {
    // All values are equal; return uniform scores
    let result : Array[Double] = []
    for _v in values {
      result.push(if max_val > 0.0 { 1.0 } else { 0.0 })
    }
    return result
  }
  let result : Array[Double] = []
  for v in values {
    result.push((v - min_val) / range)
  }
  result
}

///|
/// Sort NodeImportance array descending by score (in-place).
fn sort_by_score_desc(arr : Array[NodeImportance]) -> Unit {
  // Simple insertion sort - graphs are typically not huge
  for i = 1; i < arr.length(); i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && arr[j].score < key.score {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}
