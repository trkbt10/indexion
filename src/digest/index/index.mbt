// DigestIndex - Main orchestration for reminiscent backtracking.
// Integrates vcdb for vector storage with function extraction and embedding.

///|
/// Configuration for DigestIndex.
pub struct IndexConfig {
  /// Embedding provider type ("tfidf" or "remote").
  embedding_provider : String
  /// Embedding dimension.
  embedding_dim : Int
  /// vcdb strategy ("bruteforce", "hnsw", "ivf").
  vcdb_strategy : String
} derive(Eq, Show)

///|
/// Default configuration: TF-IDF with 256 dimensions and HNSW.
pub fn IndexConfig::default() -> IndexConfig {
  { embedding_provider: "tfidf", embedding_dim: 256, vcdb_strategy: "hnsw" }
}

///|
/// Configuration for remote embeddings (OpenAI text-embedding-3-small).
pub fn IndexConfig::remote() -> IndexConfig {
  { embedding_provider: "remote", embedding_dim: 1536, vcdb_strategy: "hnsw" }
}

///|
/// Result of building/updating the index.
pub struct BuildResult {
  /// Number of functions indexed.
  mut indexed_count : Int
  /// Number of functions skipped (already up-to-date).
  mut skipped_count : Int
  /// Number of functions removed.
  mut removed_count : Int
  /// Errors encountered.
  errors : Array[String]
} derive(Eq, Show)

///|
/// Create an empty BuildResult.
pub fn BuildResult::new() -> BuildResult {
  { indexed_count: 0, skipped_count: 0, removed_count: 0, errors: [] }
}

///|
/// Calculate the square root using Newton's method.
fn sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x / 2.0
  for i = 0; i < 20; i = i + 1 {
    ignore(i)
    guess = (guess + x / guess) / 2.0
  }
  guess
}

///|
/// Natural logarithm approximation.
fn ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  // Use series expansion for ln(1+y) where y = (x-1)/(x+1)
  let y = (x - 1.0) / (x + 1.0)
  let y2 = y * y
  let mut result = y
  let mut term = y
  for i = 1; i < 50; i = i + 1 {
    term = term * y2
    result = result + term / (2.0 * i.to_double() + 1.0)
  }
  2.0 * result
}

///|
/// TF-IDF based embedding provider.
/// Uses sparse TF-IDF vectors converted to dense format.
pub struct TfidfEmbeddingProvider {
  /// Target dimension for output vectors.
  dim : Int
  /// Vocabulary from corpus (term -> index).
  vocabulary : Map[String, Int]
  /// IDF weights from corpus.
  idf : Map[String, Double]
  /// Whether vocabulary is built.
  built : Bool
}

///|
/// Create a new TfidfEmbeddingProvider.
pub fn TfidfEmbeddingProvider::new(dim : Int) -> TfidfEmbeddingProvider {
  { dim, vocabulary: {}, idf: {}, built: false }
}

///|
/// Build vocabulary from a corpus of texts.
pub fn TfidfEmbeddingProvider::build_vocabulary(
  self : TfidfEmbeddingProvider,
  texts : Array[String],
) -> Unit {
  // Tokenize all texts
  let tokenized : Array[Array[String]] = []
  for text in texts {
    tokenized.push(@tokenizer.tokenize_for_tfidf(text))
  }
  // Build document frequency
  let df = @tfidf.build_document_frequency(tokenized)
  let total_docs = tokenized.length()
  // Build vocabulary (most frequent terms up to dim)
  let term_counts : Array[(String, Int)] = []
  for entry in df {
    term_counts.push((entry.0, entry.1))
  }
  // Sort by frequency descending
  term_counts.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Take top dim terms
  let mut idx = 0
  for i = 0; i < term_counts.length() && idx < self.dim; i = i + 1 {
    let term = term_counts[i].0
    self.vocabulary.set(term, idx)
    // Compute IDF
    let term_df = df.get(term).unwrap_or(1)
    let idf_val = ln(
        (1.0 + total_docs.to_double()) / (1.0 + term_df.to_double()),
      ) +
      1.0
    self.idf.set(term, idf_val)
    idx = idx + 1
  }
}

///|
/// Generate embedding for text.
pub fn TfidfEmbeddingProvider::embed(
  self : TfidfEmbeddingProvider,
  text : String,
) -> Array[Double] {
  let tokens = @tokenizer.tokenize_for_tfidf(text)
  let tf = @tfidf.build_term_frequency(tokens)
  let total = tokens.length().to_double()
  let safe_total = if total < 1.0 { 1.0 } else { total }
  // Create dense vector
  let vector = Array::make(self.dim, 0.0)
  for entry in tf {
    let term = entry.0
    let count = entry.1
    match self.vocabulary.get(term) {
      Some(idx) => {
        let normalized_tf = count.to_double() / safe_total
        let idf_val = self.idf.get(term).unwrap_or(1.0)
        vector[idx] = normalized_tf * idf_val
      }
      None => () // Term not in vocabulary
    }
  }
  // Normalize vector (L2)
  let mut norm = 0.0
  for v in vector {
    norm = norm + v * v
  }
  if norm > 0.0 {
    norm = sqrt(norm)
    for i = 0; i < vector.length(); i = i + 1 {
      vector[i] = vector[i] / norm
    }
  }
  vector
}

///|
/// Get embedding dimension.
pub fn TfidfEmbeddingProvider::dim(self : TfidfEmbeddingProvider) -> Int {
  self.dim
}

///|
/// DigestIndex - Main index structure.
pub struct DigestIndex {
  /// Manifest for tracking state.
  mut manifest : @manifest.DigestManifest
  /// vcdb vector database.
  db : @vcdb.VectorDB
  /// TF-IDF embedding provider.
  provider : TfidfEmbeddingProvider
  /// Cached function units.
  units : Map[String, @types.FunctionUnit]
}

///|
/// Create a new DigestIndex.
pub fn DigestIndex::new(config : IndexConfig) -> DigestIndex {
  let spec_hash = @hash.to_content_hash(
    @types.FunctionHash::from_string("digest-v1"),
  )
  let manifest = @manifest.DigestManifest::new(
    spec_hash,
    config.embedding_provider,
    config.embedding_dim,
  )
  let db = match config.vcdb_strategy {
    "hnsw" => @vcdb.VectorDB::with_hnsw(config.embedding_dim)
    "ivf" => @vcdb.VectorDB::with_ivf(config.embedding_dim)
    _ => @vcdb.VectorDB::with_dim(config.embedding_dim)
  }
  let provider = TfidfEmbeddingProvider::new(config.embedding_dim)
  { manifest, db, provider, units: {} }
}

///|
/// Build index from CodeGraph.
pub fn DigestIndex::build(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  extract_config : @extract.ExtractConfig,
) -> BuildResult {
  let result = BuildResult::new()
  // Extract function units
  let units = @extract.extract_function_units(graph, extract_config)
  // Build vocabulary from function info
  let texts : Array[String] = []
  for unit in units {
    // Use symbol info as text for vocabulary
    let text = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
    texts.push(text)
    self.units.set(unit.id(), unit)
  }
  self.provider.build_vocabulary(texts)
  // Find stale and deleted functions
  let stale = self.manifest.get_stale_functions(units)
  let current_ids : Array[String] = []
  for unit in units {
    current_ids.push(unit.id())
  }
  let (updated_manifest, removed_ids) = self.manifest.remove_deleted_functions(
    current_ids,
  )
  // Update manifest
  self.manifest = updated_manifest
  // Remove deleted from vcdb
  for vid in removed_ids {
    let _ = self.db.remove(@vcdb_core.VectorId(vid))
  }
  result.removed_count = removed_ids.length()
  // Process functions in bottom-up order
  let stale_set : Map[String, Bool] = {}
  for id in stale {
    stale_set.set(id, true)
  }
  @traverse.traverse_bottom_up(units, fn(unit) {
    if stale_set.contains(unit.id()) {
      // Generate embedding
      let text = unit.name() + " " + unit.symbol.kind + " " + unit.symbol.ns
      let vector = self.provider.embed(text)
      // Allocate vector ID
      let (m, vid) = self.manifest.allocate_vector_id()
      self.manifest = m
      // Create attributes
      let attrs = @vcdb.empty_attrs()
      attrs.set("name", @vcdb_core.AttrValue::String(unit.name()))
      attrs.set("kind", @vcdb_core.AttrValue::String(unit.symbol.kind))
      attrs.set("module", @vcdb_core.AttrValue::String(unit.module_id))
      attrs.set("depth", @vcdb_core.AttrValue::Int(unit.depth.to_int64()))
      match unit.symbol.doc {
        Some(doc) => attrs.set("doc", @vcdb_core.AttrValue::String(doc))
        None => ()
      }
      // Add to vcdb
      self.db.add(@vcdb_core.VectorId(vid), vector, attrs)
      // Update manifest
      let entry = @manifest.FunctionEntry::from_unit(unit, Some(vid))
      self.manifest = self.manifest.update_function(entry)
      result.indexed_count = result.indexed_count + 1
    } else {
      result.skipped_count = result.skipped_count + 1
    }
  })
  result
}

///|
/// Query by purpose text.
pub fn DigestIndex::query(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
) -> Array[@types.QueryHit] {
  let vector = self.provider.embed(purpose)
  let hits = self.db.search(vector, top_k, None)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    // Get function ID from vector ID
    let vid = hit.id.to_int64()
    // Find function by looking up manifest
    for entry in self.manifest.functions {
      match entry.1.vector_id {
        Some(v) =>
          if v == vid {
            match self.units.get(entry.0) {
              Some(unit) =>
                results.push(@types.QueryHit::new(unit, hit.score, []))
              None => ()
            }
          }
        None => ()
      }
    }
  }
  results
}

///|
/// Build index using pre-computed remote embeddings.
/// Requires JSONL file with {id, embedding} pairs from scripts/embed.py.
pub fn DigestIndex::build_with_remote(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  extract_config : @extract.ExtractConfig,
  embeddings_content : String,
) -> BuildResult {
  let result = BuildResult::new()
  // Load pre-computed embeddings
  let remote_provider = @types.RemoteEmbeddingProvider::new(
    @types.RemoteEmbeddingConfig::default(),
  )
  let loaded = remote_provider.load_from_file(embeddings_content)
  if loaded == 0 {
    result.errors.push("No embeddings loaded from file")
    return result
  }
  // Detect dimension from first embedding and rebuild db if needed
  let first_embedding = remote_provider.get(remote_provider.cached_ids()[0])
  match first_embedding {
    Some(vec) =>
      if vec.length() != self.db.dim() {
        // Dimension mismatch - we need to recreate the db with correct dim
        // For now, just note the error
        result.errors.push(
          "Dimension mismatch: expected " +
          self.db.dim().to_string() +
          ", got " +
          vec.length().to_string(),
        )
        return result
      }
    None => ()
  }
  // Extract function units
  let units = @extract.extract_function_units(graph, extract_config)
  for unit in units {
    self.units.set(unit.id(), unit)
  }
  // Find stale and deleted functions
  let stale = self.manifest.get_stale_functions(units)
  let current_ids : Array[String] = []
  for unit in units {
    current_ids.push(unit.id())
  }
  let (updated_manifest, removed_ids) = self.manifest.remove_deleted_functions(
    current_ids,
  )
  self.manifest = updated_manifest
  // Remove deleted from vcdb
  for vid in removed_ids {
    let _ = self.db.remove(@vcdb_core.VectorId(vid))
  }
  result.removed_count = removed_ids.length()
  // Process functions
  let stale_set : Map[String, Bool] = {}
  for id in stale {
    stale_set.set(id, true)
  }
  @traverse.traverse_bottom_up(units, fn(unit) {
    if stale_set.contains(unit.id()) {
      match remote_provider.get(unit.id()) {
        Some(vector) => {
          // Allocate vector ID
          let (m, vid) = self.manifest.allocate_vector_id()
          self.manifest = m
          // Create attributes
          let attrs = @vcdb.empty_attrs()
          attrs.set("name", @vcdb_core.AttrValue::String(unit.name()))
          attrs.set("kind", @vcdb_core.AttrValue::String(unit.symbol.kind))
          attrs.set("module", @vcdb_core.AttrValue::String(unit.module_id))
          attrs.set("depth", @vcdb_core.AttrValue::Int(unit.depth.to_int64()))
          // Add to vcdb
          self.db.add(@vcdb_core.VectorId(vid), vector, attrs)
          // Update manifest
          let entry = @manifest.FunctionEntry::from_unit(unit, Some(vid))
          self.manifest = self.manifest.update_function(entry)
          result.indexed_count = result.indexed_count + 1
        }
        None =>
          // No embedding found, skip
          result.skipped_count = result.skipped_count + 1
      }
    } else {
      result.skipped_count = result.skipped_count + 1
    }
  })
  result
}

///|
/// Query using remote embeddings (requires embedding in query itself).
pub fn DigestIndex::query_with_remote(
  self : DigestIndex,
  query_embedding : Array[Double],
  top_k : Int,
) -> Array[@types.QueryHit] {
  let hits = self.db.search(query_embedding, top_k, None)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    let vid = hit.id.to_int64()
    for entry in self.manifest.functions {
      match entry.1.vector_id {
        Some(v) =>
          if v == vid {
            match self.units.get(entry.0) {
              Some(unit) =>
                results.push(@types.QueryHit::new(unit, hit.score, []))
              None => ()
            }
          }
        None => ()
      }
    }
  }
  results
}

///|
/// Serialize index for persistence.
pub fn DigestIndex::serialize(self : DigestIndex) -> (String, Bytes) {
  let manifest_json = self.manifest.to_json_string()
  let db_bytes = self.db.serialize()
  (manifest_json, db_bytes)
}

///|
/// Get statistics about the index.
pub fn DigestIndex::stats(self : DigestIndex) -> Map[String, Int] {
  let stats : Map[String, Int] = {}
  stats.set("function_count", self.manifest.functions.length())
  stats.set("vector_count", self.db.size())
  stats.set("embedding_dim", self.provider.dim)
  stats
}
