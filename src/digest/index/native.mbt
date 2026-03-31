// Native async embedding support using mizchi/x/http

///|
/// Build index using unified DigestConfig (async).
/// Uses DigestConfig for embedding source selection and incremental updates.
pub async fn DigestIndex::build_with_config(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  digest_config : @config.DigestConfig,
) -> BuildResult raise @embed.EmbedError {
  let result = BuildResult::new()
  // Extract function units using config
  let extract_config = digest_config.to_extract_config()
  let units = @extract.extract_function_units(graph, extract_config)
  for unit in units {
    self.units.set(unit.id(), unit)
  }
  // Find stale and deleted functions using manifest
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
  // Build stale set
  let stale_set : Map[String, Bool] = {}
  for id in stale {
    stale_set.set(id, true)
  }
  // Collect stale units and their texts (using config for text generation)
  let stale_units : Array[@types.FunctionUnit] = []
  let stale_texts : Array[String] = []
  for unit in units {
    if stale_set.contains(unit.id()) {
      stale_units.push(unit)
      // Use DigestConfig to determine embedding text
      let text = digest_config.get_embedding_text(unit)
      stale_texts.push(text)
    } else {
      result.skipped_count = result.skipped_count + 1
    }
  }
  if stale_texts.length() == 0 {
    return result
  }
  // Get embeddings based on provider
  let all_embeddings = match digest_config.embedding_provider {
    @config.OpenAI(api_config) =>
      embed_with_openai_config(api_config, stale_texts)
    @config.TfIdf(_dim) => {
      // Build TF-IDF vocabulary from all texts (including non-stale for IDF)
      let all_texts : Array[String] = []
      for unit in units {
        all_texts.push(digest_config.get_embedding_text(unit))
      }
      self.provider.build_vocabulary(all_texts)
      // Embed only stale texts
      let embeddings : Array[Array[Double]] = []
      for text in stale_texts {
        embeddings.push(self.provider.embed(text))
      }
      embeddings
    }
    @config.Precomputed(_file) =>
      // For precomputed, error out - should use build_with_remote
      raise @embed.ParseError(
        "Precomputed embeddings not supported in async build",
      )
  }
  // Index all stale functions with their embeddings
  for j = 0; j < stale_units.length(); j = j + 1 {
    let unit = stale_units[j]
    let vector = all_embeddings[j]
    // Allocate vector ID
    let (m, vid) = self.manifest.allocate_vector_id()
    self.manifest = m
    // Create attributes (including hash for verification)
    let attrs = @vcdb.empty_attrs()
    attrs.set("name", @vcdb_core.String(unit.name()))
    attrs.set("kind", @vcdb_core.String(unit.symbol.kind))
    attrs.set("module", @vcdb_core.String(unit.module_id))
    attrs.set("depth", @vcdb_core.Int(unit.depth.to_int64()))
    attrs.set("source_hash", @vcdb_core.String(unit.source_hash.to_string()))
    attrs.set("context_hash", @vcdb_core.String(unit.context_hash.to_string()))
    match unit.symbol.doc {
      Some(doc) => attrs.set("doc", @vcdb_core.String(doc))
      None => ()
    }
    // Add to vcdb
    self.db.add(@vcdb_core.VectorId(vid), vector, attrs)
    // Update manifest
    let entry = @manifest.FunctionEntry::from_unit(unit, Some(vid))
    self.manifest = self.manifest.update_function(entry)
    result.indexed_count = result.indexed_count + 1
  }
  result
}

///|
/// Helper: Embed texts using OpenAI-compatible API with batching.
async fn embed_with_openai_config(
  api_config : @config.EmbeddingApiConfig,
  texts : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  let config : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let all_embeddings : Array[Array[Double]] = []
  let batch_size = 100
  let mut i = 0
  while i < texts.length() {
    let batch_end = if i + batch_size < texts.length() {
      i + batch_size
    } else {
      texts.length()
    }
    let batch : Array[String] = []
    for j = i; j < batch_end; j = j + 1 {
      batch.push(texts[j])
    }
    let batch_embeddings = @embed.get_embeddings(config, batch)
    for emb in batch_embeddings {
      all_embeddings.push(emb)
    }
    i = batch_end
  }
  all_embeddings
}

///|
/// Build index using native HTTP to OpenAI API (async).
/// Backwards compatible wrapper - use build_with_config for new code.
pub async fn DigestIndex::build_native(
  self : DigestIndex,
  graph : @graph.CodeGraph,
  extract_config : @extract.ExtractConfig,
  api_key : String,
) -> BuildResult raise @embed.EmbedError {
  let digest_config : @config.DigestConfig = {
    embedding_source: @config.Raw,
    embedding_provider: @config.OpenAI(@config.EmbeddingApiConfig::new(api_key)),
    vcdb_strategy: @config.Hnsw,
    include_external: extract_config.include_external,
    exclude_kinds: extract_config.exclude_kinds,
    index_dir: @config.DEFAULT_INDEX_DIR,
    llm_config: None,
  }
  self.build_with_config(graph, digest_config)
}

///|
/// Query using OpenAI-compatible embedding API (async).
pub async fn DigestIndex::query_native(
  self : DigestIndex,
  purpose : String,
  top_k : Int,
  api_config : @config.EmbeddingApiConfig,
) -> Array[@types.QueryHit] raise @embed.EmbedError {
  let config : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let vector = @embed.get_embedding(config, purpose)
  let hits = self.db.search(vector, top_k, None)
  let results : Array[@types.QueryHit] = []
  for hit in hits {
    let vid = hit.id.0
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
/// Create DigestIndex from saved manifest (for incremental updates).
pub fn DigestIndex::from_manifest(
  manifest : @manifest.DigestManifest,
  db_bytes : Bytes,
) -> DigestIndex {
  let dim = manifest.embedding_dim
  let db = @vcdb.VectorDB::deserialize(db_bytes)
  let provider = TfidfEmbeddingProvider::new(dim)
  { manifest, db, provider, units: {} }
}

///|
/// Create DigestIndex with unified config.
pub fn DigestIndex::with_config(config : @config.DigestConfig) -> DigestIndex {
  let spec_hash = @hash.to_content_hash(
    @types.FunctionHash::from_string("digest-v1"),
  )
  let provider_name = match config.embedding_provider {
    @config.TfIdf(_) => "tfidf"
    @config.OpenAI(_) => "openai"
    @config.Precomputed(_) => "precomputed"
  }
  let manifest = @manifest.DigestManifest::new(
    spec_hash,
    provider_name,
    config.embedding_dim(),
  )
  let db = match config.vcdb_strategy {
    @config.Hnsw => @vcdb.VectorDB::with_hnsw(config.embedding_dim())
    @config.Ivf => @vcdb.VectorDB::with_ivf(config.embedding_dim())
    @config.BruteForce => @vcdb.VectorDB::with_dim(config.embedding_dim())
  }
  let provider = TfidfEmbeddingProvider::new(config.embedding_dim())
  { manifest, db, provider, units: {} }
}
