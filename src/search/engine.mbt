///|
/// # Search Engine
///
/// Single source of truth for vcdb construction, document storage, and search.
/// All consumers (search CLI, digest, wiki, grep) obtain vcdb through this module.

///|
/// vcdb construction strategy.
pub(all) enum VcdbStrategy {
  Hnsw
  Ivf
  BruteForce
}

///|
/// Search engine — the sole vcdb owner and accessor.
pub struct SearchEngine {
  db : @vcdb.VectorDB
  tfidf_provider : @text_embed.TfidfEmbeddingProvider?
  openai_config : @dconfig.EmbeddingApiConfig?
  documents : Map[String, SearchDocument]
  id_map : Map[Int, String]
}

///|
/// Create a vcdb-backed search engine. This is the SoT for vcdb construction.
/// All consumers must use this function to obtain a vcdb instance.
pub fn SearchEngine::create(
  dim? : Int = 256,
  strategy? : VcdbStrategy = Hnsw,
) -> SearchEngine {
  let db = match strategy {
    Hnsw => @vcdb.VectorDB::with_hnsw(dim)
    Ivf => @vcdb.VectorDB::with_ivf(dim)
    BruteForce => @vcdb.VectorDB::with_dim(dim)
  }
  { db, tfidf_provider: None, openai_config: None, documents: {}, id_map: {} }
}

///|
/// Create an engine from a serialized vcdb database.
pub fn SearchEngine::from_bytes(data : Bytes) -> SearchEngine {
  let db = @vcdb.VectorDB::deserialize(data)
  { db, tfidf_provider: None, openai_config: None, documents: {}, id_map: {} }
}

///|
/// Set the TF-IDF embedding provider.
pub fn SearchEngine::with_tfidf(
  self : SearchEngine,
  provider : @text_embed.TfidfEmbeddingProvider,
) -> SearchEngine {
  { ..self, tfidf_provider: Some(provider) }
}

///|
/// Set the OpenAI embedding config.
pub fn SearchEngine::with_openai(
  self : SearchEngine,
  config : @dconfig.EmbeddingApiConfig,
) -> SearchEngine {
  { ..self, openai_config: Some(config) }
}

///|
/// Add a single document with a pre-computed vector and explicit vector ID.
/// Attrs are forwarded to vcdb using the unified schema.
pub fn SearchEngine::add(
  self : SearchEngine,
  doc : SearchDocument,
  vector : Array[Double],
  vid : Int64,
) -> Unit {
  let vcdb_attrs = build_vcdb_attrs(doc)
  self.db.add(@vcdb_core.VectorId(vid), vector, vcdb_attrs)
  self.documents[doc.id] = doc
  self.id_map[vid.to_int()] = doc.id
}

///|
/// Add a document with raw vcdb attrs (for digest compatibility).
/// Digest manages its own attrs; this bypasses SearchDocument attr conversion.
pub fn SearchEngine::add_raw(
  self : SearchEngine,
  vid : Int64,
  vector : Array[Double],
  attrs : @vcdb_core.Attrs,
) -> Unit {
  self.db.add(@vcdb_core.VectorId(vid), vector, attrs)
}

///|
/// Remove a document by vcdb vector ID.
pub fn SearchEngine::remove(self : SearchEngine, vid : Int64) -> Bool {
  self.db.remove(@vcdb_core.VectorId(vid))
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
/// Build a search engine from documents using the specified embedding provider.
/// Convenience function for ad-hoc search (search CLI, wiki search).
pub async fn SearchEngine::build(
  documents : Array[SearchDocument],
  provider? : @dconfig.EmbeddingProvider = @dconfig.TfIdf(256),
) -> SearchEngine raise @embed.EmbedError {
  let texts : Array[String] = []
  for doc in documents {
    texts.push(doc.text)
  }
  let dim : Int = match provider {
    @dconfig.TfIdf(d) => d
    @dconfig.OpenAI(cfg) => cfg.dim
    @dconfig.Precomputed(_) => 256
  }
  let (embeddings, tfidf_prov, openai_cfg) = match provider {
    @dconfig.TfIdf(_) => {
      let prov = @text_embed.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      let embs : Array[Array[Double]] = []
      for text in texts {
        embs.push(prov.embed(text))
      }
      (embs, Some(prov), None)
    }
    @dconfig.OpenAI(api_config) => {
      let embs = embed_openai_batched(api_config, texts)
      let prov = @text_embed.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      (embs, Some(prov), Some(api_config))
    }
    @dconfig.Precomputed(_) => {
      let prov = @text_embed.TfidfEmbeddingProvider::new(dim)
      prov.build_vocabulary(texts)
      let embs : Array[Array[Double]] = []
      for text in texts {
        embs.push(prov.embed(text))
      }
      (embs, Some(prov), None)
    }
  }
  let engine = SearchEngine::create(dim~)
  let doc_map : Map[String, SearchDocument] = {}
  let id_map : Map[Int, String] = {}
  for i, doc in documents {
    let vector = embeddings[i]
    let vid_int = i + 1
    let vid = @vcdb_core.VectorId::from_int(vid_int)
    let vcdb_attrs = build_vcdb_attrs(doc)
    engine.db.add(vid, vector, vcdb_attrs)
    doc_map[doc.id] = doc
    id_map[vid_int] = doc.id
  }
  {
    ..engine,
    tfidf_provider: tfidf_prov,
    openai_config: openai_cfg,
    documents: doc_map,
    id_map,
  }
}

///|
/// Search by raw vector with optional filter.
/// Used by digest and other consumers that manage their own embedding.
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
/// Search the engine with a natural language query.
/// Uses OpenAI embedding if configured, falls back to TF-IDF.
pub async fn SearchEngine::search(
  self : SearchEngine,
  query : String,
  top_k? : Int = 20,
  min_score? : Double = 0.05,
  filter? : @vcdb_filter.FilterExpr? = None,
) -> Array[SearchHit] {
  let vector = match self.openai_config {
    Some(api_config) => {
      let cfg : @embed.OpenAIConfig = {
        api_key: api_config.api_key,
        model: api_config.model,
        base_url: api_config.base_url,
      }
      let results = @embed.get_embeddings(cfg, [query]) catch {
        _ =>
          match self.tfidf_provider {
            Some(prov) => [prov.embed(query)]
            None => return []
          }
      }
      results[0]
    }
    None =>
      match self.tfidf_provider {
        Some(prov) => prov.embed(query)
        None => return []
      }
  }
  let hits = match filter {
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
  let results : Array[SearchHit] = []
  for hit in hits {
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
/// Create empty vcdb attrs. SoT for attr construction.
pub fn empty_attrs() -> @vcdb_core.Attrs {
  @vcdb.empty_attrs()
}

// --- Internal helpers ---

///|
/// Build vcdb attrs from a SearchDocument using the unified schema.
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

///|
/// Embed texts in batches using OpenAI API.
async fn embed_openai_batched(
  api_config : @dconfig.EmbeddingApiConfig,
  texts : Array[String],
) -> Array[Array[Double]] raise @embed.EmbedError {
  let cfg : @embed.OpenAIConfig = {
    api_key: api_config.api_key,
    model: api_config.model,
    base_url: api_config.base_url,
  }
  let all : Array[Array[Double]] = []
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
    let embs = @embed.get_embeddings(cfg, batch)
    for emb in embs {
      all.push(emb)
    }
    i = batch_end
  }
  all
}
