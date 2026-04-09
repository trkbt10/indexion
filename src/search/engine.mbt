///|
/// # Search Engine
///
/// vcdb construction, document storage, embedding, and search.
/// All consumers (search CLI, digest, wiki, grep) use this module.
///
/// ## Embedding
///
/// embed_texts(provider, texts, tfidf) is the SoT for text → vector conversion.
/// SearchEngine does not store embedding configuration — callers pass provider
/// at build time and search time. This makes multi-provider usage explicit.
///
/// ## Digest
///
/// Digest uses SearchEngine as a plain vcdb wrapper (add_raw / search_vector)
/// and manages its own Map[String, SearchEngine] for multiple providers.
/// It does not call build_index() or search_index().
///
/// ## Search CLI / Wiki
///
/// Use build_index() and search_index() for single-provider ad-hoc search.

// VcdbStrategy is defined in @embed_config (SoT).

///|
/// Search engine — vcdb owner with optional vocabulary attachment.
/// tfidf_provider is for vocabulary persistence only; it is not used
/// for embedding within this struct.
pub struct SearchEngine {
  db : @vcdb.VectorDB
  tfidf_provider : @text_embed.TfidfEmbeddingProvider?
  documents : Map[String, SearchDocument]
  id_map : Map[Int, String]
}

///|
/// Create a vcdb-backed search engine.
pub fn SearchEngine::create(
  dim? : Int = 256,
  strategy? : @embed_config.VcdbStrategy = @embed_config.Hnsw,
) -> SearchEngine {
  let db = match strategy {
    @embed_config.Hnsw => @vcdb.VectorDB::with_hnsw(dim)
    @embed_config.Ivf => @vcdb.VectorDB::with_ivf(dim)
    @embed_config.BruteForce => @vcdb.VectorDB::with_dim(dim)
  }
  { db, tfidf_provider: None, documents: {}, id_map: {} }
}

///|
/// Create an engine from a serialized vcdb database.
pub fn SearchEngine::from_bytes(data : Bytes) -> SearchEngine {
  let db = @vcdb.VectorDB::deserialize(data)
  { db, tfidf_provider: None, documents: {}, id_map: {} }
}

///|
/// Attach a TF-IDF vocabulary to this engine (for serialization by consumers).
pub fn SearchEngine::with_tfidf(
  self : SearchEngine,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> SearchEngine {
  { ..self, tfidf_provider: Some(provider) }
}

///|
/// Return the attached TF-IDF vocabulary, if any.
pub fn SearchEngine::tfidf_provider(
  self : SearchEngine,
) -> @text_embed.TfidfEmbeddingProvider? {
  self.tfidf_provider
}

///|
/// Set the id_map (vector ID → document ID) for a loaded engine.
pub fn SearchEngine::with_id_map(
  self : SearchEngine,
  id_map : Map[Int, String],
) -> SearchEngine {
  { ..self, id_map }
}

///|
/// Set the documents map for a loaded engine.
pub fn SearchEngine::with_documents(
  self : SearchEngine,
  documents : Map[String, SearchDocument],
) -> SearchEngine {
  { ..self, documents }
}

///|
/// Add a document with a pre-computed vector.
pub fn SearchEngine::add(
  self : SearchEngine,
  doc : SearchDocument,
  vector : Array[Double],
  vid : Int64,
) -> Unit {
  let vcdb_attrs = build_vcdb_attrs(doc)
  self.db.add(@vcdb_core.VectorId::from_int64(vid), vector, vcdb_attrs)
  self.documents[doc.id] = doc
  self.id_map[vid.to_int()] = doc.id
}

///|
/// Add a vector with raw vcdb attrs (digest, wiki — callers manage attrs).
pub fn SearchEngine::add_raw(
  self : SearchEngine,
  vid : Int64,
  vector : Array[Double],
  attrs : @vcdb_core.Attrs,
) -> Unit {
  self.db.add(@vcdb_core.VectorId::from_int64(vid), vector, attrs)
}

///|
/// Remove a vector by vcdb vector ID.
pub fn SearchEngine::remove(self : SearchEngine, vid : Int64) -> Bool {
  self.db.remove(@vcdb_core.VectorId::from_int64(vid))
}

///|
/// Get the vcdb database size.
pub fn SearchEngine::size(self : SearchEngine) -> Int {
  self.db.size()
}

///|
/// Get the vcdb embedding dimension.
pub fn SearchEngine::dim(self : SearchEngine) -> Int {
  self.db.dim()
}

///|
/// Serialize the vcdb database to bytes for persistence.
pub fn SearchEngine::serialize(self : SearchEngine) -> Bytes {
  self.db.serialize()
}

///|
/// Search by raw vector with optional filter.
/// The caller supplies the query vector (embedding is the caller's concern).
pub fn SearchEngine::search_vector(
  self : SearchEngine,
  vector : Array[Double],
  top_k : Int,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[@vcdb_core.SearchHit] {
  match filter {
    Some(expr) =>
      self.db.search_with_expr(
        vector,
        top_k,
        Some(expr),
        None,
        @vcdb_filter.Auto,
      )
    None => self.db.search(vector, top_k, None)
  }
}

///|
/// Resolve raw vcdb hits to SearchHits.
pub fn SearchEngine::resolve_hits(
  self : SearchEngine,
  raw_hits : Array[@vcdb_core.SearchHit],
  min_score : Double,
) -> Array[SearchHit] {
  let results : Array[SearchHit] = []
  for hit in raw_hits {
    if hit.score < min_score {
      continue
    }
    let vid = hit.id.to_int64().to_int()
    match self.id_map.get(vid) {
      Some(doc_id) =>
        match self.documents.get(doc_id) {
          Some(doc) => results.push({ document: doc, score: hit.score })
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Create empty vcdb attrs.
pub fn empty_attrs() -> @vcdb_core.Attrs {
  @vcdb.empty_attrs()
}

// ---------------------------------------------------------------------------
// Embedding SoT
// ---------------------------------------------------------------------------

///|
/// Embed a batch of texts using the given provider.
/// tfidf must have its vocabulary built before calling.
/// - TfIdf / Precomputed: embed with tfidf.
/// - OpenAI: call the API in batches of 100.
pub async fn embed_texts(
  provider : @embed_config.EmbeddingProvider,
  texts : Array[String],
  tfidf : @text_embed.TfidfEmbeddingProvider,
) -> Array[Array[Double]] raise @embed.EmbedError {
  match provider {
    @embed_config.TfIdf(_) | @embed_config.Precomputed(_) => {
      texts.map(fn(t) { tfidf.embed(t) })
    }
    @embed_config.OpenAI(api_config) => {
      let cfg : @embed.OpenAIConfig = {
        api_key: api_config.api_key,
        model: api_config.model,
        base_url: api_config.base_url,
      }
      let all : Array[Array[Double]] = []
      let batch_size = 100
      let mut i = 0
      while i < texts.length() {
        let batch_end = @cmp.minimum(i + batch_size, texts.length())
        let batch : Array[String] = []
        for j = i; j < batch_end; j = j + 1 {
          batch.push(texts[j])
        }
        for emb in @embed.get_embeddings(cfg, batch) {
          all.push(emb)
        }
        i = batch_end
      }
      all
    }
  }
}

///|
/// Extract the embedding dimension from a provider.
pub fn provider_dim(provider : @embed_config.EmbeddingProvider) -> Int {
  match provider {
    @embed_config.TfIdf(d) => d
    @embed_config.OpenAI(cfg) => cfg.dim
    @embed_config.Precomputed(_) => @embed_config.DEFAULT_TFIDF_DIM
  }
}

// ---------------------------------------------------------------------------
// Build and search (convenience layer for search CLI)
// ---------------------------------------------------------------------------

///|
/// Build a SearchEngine from documents.
/// TF-IDF vocabulary is always built from the corpus:
///   - TfIdf / Precomputed: embed with it.
///   - OpenAI: embed with OpenAI; attach tfidf for query-time use.
pub async fn build_index(
  documents : Array[SearchDocument],
  provider : @embed_config.EmbeddingProvider,
) -> SearchEngine raise @embed.EmbedError {
  let texts : Array[String] = documents.map(fn(d) { d.text })
  let dim = provider_dim(provider)
  let tfidf = @text_embed.TfidfEmbeddingProvider::new(dim)
  tfidf.build_vocabulary(texts)
  let embeddings = embed_texts(provider, texts, tfidf)
  let engine = SearchEngine::create(dim~).with_tfidf(tfidf)
  for i, doc in documents {
    engine.add(doc, embeddings[i], (i + 1).to_int64())
  }
  engine
}

///|
/// Search a pre-built index with a natural language query.
/// provider and tfidf must correspond to what was used at build time.
/// For OpenAI indexes: pass the OpenAI provider and the attached tfidf is
/// ignored for query embedding — OpenAI is used instead (same provider).
pub async fn search_index(
  engine : SearchEngine,
  query : String,
  provider : @embed_config.EmbeddingProvider,
  top_k : Int,
  min_score : Double,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[SearchHit] raise @embed.EmbedError {
  let tfidf = match engine.tfidf_provider() {
    Some(p) => p
    None =>
      @text_embed.TfidfEmbeddingProvider::new(provider_dim(provider))
  }
  let embs = embed_texts(provider, [query], tfidf)
  let vector = embs[0]
  let raw_hits = engine.search_vector(vector, top_k, filter~)
  engine.resolve_hits(raw_hits, min_score)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
fn build_vcdb_attrs(doc : SearchDocument) -> @vcdb_core.Attrs {
  let attrs = @vcdb.empty_attrs()
  for entry in doc.attrs {
    attrs.set(entry.0, @vcdb_core.String(entry.1))
  }
  if !doc.attrs.contains("title") {
    attrs.set("title", @vcdb_core.String(doc.title))
  }
  if !doc.attrs.contains("node_kind") {
    attrs.set("node_kind", @vcdb_core.String(doc.kind))
  }
  if !doc.attrs.contains("source") {
    attrs.set("source", @vcdb_core.String(doc.source))
  }
  attrs
}
